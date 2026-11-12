import Foundation
import CleanSlateCore

/// What a rule change did, so observers can revalidate cheaply.
enum ProtectionChange: Equatable {
    case added, removed, reloaded
}

/// The only thing the deletion path and the suggestion path know about protection rules.
/// Implementations answer from memory and must be cheap: they run inside loops over fresh snapshots.
@MainActor
protocol ProtectionGate: AnyObject {
    var availability: ProtectionAvailability { get }
    /// Bumps on every durable change to the rule set.
    var revision: Int64 { get }
    /// Rule writes that were started and have not yet finished.
    var pendingWrites: Int { get }
    /// `.indeterminate` unless the rules are ready and no write is pending.
    func verdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict
}

extension ProtectionGate {
    /// The fresh record with the evaluation-time overlay applied: `.userProtected` for a match,
    /// `.uncertainMetadata` (also a hard block) when the rules cannot give an answer.
    func decoratedRecord(_ snapshot: PhotoSnapshot) -> AssetRecord {
        switch verdict(for: snapshot) {
        case .unprotected: return snapshot.record
        case .protected: return Self.record(snapshot.record, adding: .userProtected)
        case .indeterminate: return Self.record(snapshot.record, adding: .uncertainMetadata)
        }
    }

    func decorated(_ snapshot: PhotoSnapshot) -> PhotoSnapshot {
        let record = decoratedRecord(snapshot)
        guard record != snapshot.record else { return snapshot }
        var copy = snapshot
        copy.record = record
        return copy
    }

    /// Non-nil means a commit that began at `startRevision` must not delete anything.
    func commitBlock(since startRevision: Int64) -> IndeterminateReason? {
        ProtectionCommitGate.block(availability: availability, pendingWrites: pendingWrites,
                                   startRevision: startRevision, currentRevision: revision)
    }

    private static func record(_ record: AssetRecord, adding flag: PreservationFlag) -> AssetRecord {
        AssetRecord(id: record.id, revision: record.revision, flags: record.flags.union([flag]),
                    verifiedLogicalBytes: record.verifiedLogicalBytes)
    }
}

/// Owns the user's protection rules: loads them fail-closed, writes them durably, and answers verdicts.
@MainActor
final class ProtectionRuleService: ObservableObject, ProtectionGate {
    static let everCreatedKey = "protection.everCreated"
    static let lastRevisionKey = "protection.lastRevision"

    @Published private(set) var availability: ProtectionAvailability = .loading
    @Published private(set) var rules: [ProtectionRule] = []
    @Published private(set) var revision: Int64 = 0
    @Published private(set) var pendingWrites = 0
    @Published private(set) var lastError: String?
    var onChange: ((ProtectionChange) -> Void)?

    private let store: LibraryStore
    private let defaults: UserDefaults
    private let requiresDurableStore: Bool
    private var ruleSet: ProtectionRuleSet

    /// - Parameter requiresDurableStore: writes are refused on the in-memory fallback store, because rules that
    ///   cannot be kept must never look protected.
    init(store: LibraryStore, defaults: UserDefaults = .standard, requiresDurableStore: Bool = true) {
        self.store = store
        self.defaults = defaults
        self.requiresDurableStore = requiresDurableStore
        // An empty set is safe here: `availability` starts at `.loading`, which makes every verdict indeterminate.
        self.ruleSet = ProtectionRuleSet.empty
    }

    private var storeIsDurable: Bool { store.path != nil }

    // MARK: Gate

    func verdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict {
        switch availability {
        case .loading: return .indeterminate(.rulesLoading)
        case .unavailable, .lost: return .indeterminate(.rulesUnavailable)
        case .ready: break
        }
        if pendingWrites > 0 { return .indeterminate(.ruleWritePending) }
        // The App cannot resolve album membership yet, so album rules answer "unknown" (fail closed).
        return ruleSet.verdict(ProtectionSubject(id: snapshot.id, capturedAt: snapshot.capturedAt, albumIDs: nil))
    }

    // MARK: Load

    /// Reads the rules and decides the availability. Safe to call again (retry).
    func load() async {
        let everCreated = defaults.bool(forKey: Self.everCreatedKey)
        let mirrored = Int64(defaults.integer(forKey: Self.lastRevisionKey))
        var treatAsCreated = everCreated
        var loaded: (revision: Int64, rules: [ProtectionRule], set: ProtectionRuleSet)?
        let outcome: Result<Int64, Error>
        do {
            let state = try await store.protectionRules()
            let set = try ProtectionRuleSet(rules: state.rules, revision: state.revision)
            loaded = (state.revision, state.rules, set)
            outcome = .success(state.revision)
        } catch {
            // Stored rows that cannot be understood prove that rules exist, whatever UserDefaults says.
            if error is ProtectionRuleSet.Invalid { treatAsCreated = true }
            if case LibraryStore.StoreError.malformedProtectionRule = error { treatAsCreated = true }
            outcome = .failure(error)
        }
        let decision = ProtectionLoadPolicy.availability(read: outcome, everCreated: treatAsCreated,
                                                         mirroredRevision: mirrored, storeDurable: storeIsDurable)
        if let loaded, decision == .ready || decision == .lost {
            ruleSet = loaded.set; rules = loaded.rules; revision = loaded.revision
        } else if case .failure = outcome, decision == .ready {
            // Never created, nothing to read: no rules.
            ruleSet = ProtectionRuleSet.empty; rules = []
        }
        availability = decision
        if decision == .ready { lastError = nil }
        onChange?(.reloaded)
    }

    /// The user accepted that their rules may be gone. Adopts the current database as the new baseline.
    func acknowledgeLost() {
        guard availability == .lost else { return }
        defaults.set(Int(revision), forKey: Self.lastRevisionKey)
        availability = .ready
        onChange?(.reloaded)
    }

    // MARK: Writes

    @discardableResult
    func protect(assetIDs: [String]) async -> Bool {
        let ids = Array(Set(assetIDs.filter { !$0.isEmpty })).sorted()
        guard !ids.isEmpty else { return true }
        let now = Date()
        let new = ids.map { ProtectionRule(scope: .asset(localIdentifier: $0), createdAt: now) }
        return await write(creating: true, change: .added) { [store] in try await store.insertProtectionRules(new) }
    }

    @discardableResult
    func protect(range: ClosedRange<LocalDay>, timeZoneID: String = TimeZone.current.identifier) async -> Bool {
        guard let interval = ProtectionDateResolver.interval(start: range.lowerBound, end: range.upperBound, timeZoneID: timeZoneID) else {
            lastError = "That date range isn't valid."
            return false
        }
        let rule = ProtectionRule(scope: .dateRange(start: range.lowerBound, end: range.upperBound, timeZoneID: timeZoneID,
                                                    startInclusive: interval.start, endExclusive: interval.endExclusive))
        return await write(creating: true, change: .added) { [store] in try await store.insertProtectionRules([rule]) }
    }

    @discardableResult
    func remove(ruleID: UUID) async -> Bool {
        await write(creating: false, change: .removed) { [store] in try await store.deleteProtectionRule(id: ruleID) }
    }

    @discardableResult
    func removeAll() async -> Bool {
        await write(creating: false, change: .removed) { [store] in try await store.deleteAllProtectionRules() }
    }

    /// One write: mark pending synchronously, persist, rebuild from the store, publish, notify, then clear pending.
    /// Nothing looks protected before the store confirmed the write.
    private func write(creating: Bool, change: ProtectionChange, _ operation: () async throws -> Int64) async -> Bool {
        guard availability == .ready else {
            lastError = "Protection rules aren't available right now."
            return false
        }
        guard storeIsDurable || !requiresDurableStore else {
            lastError = "Protection rules can't be saved on this device right now. Nothing was changed."
            return false
        }
        pendingWrites += 1
        lastError = nil
        if creating { defaults.set(true, forKey: Self.everCreatedKey) }
        do {
            _ = try await operation()
            let state = try await store.protectionRules()
            ruleSet = try ProtectionRuleSet(rules: state.rules, revision: state.revision)
            rules = state.rules
            revision = state.revision
            defaults.set(Int(state.revision), forKey: Self.lastRevisionKey)
            onChange?(change)
            pendingWrites -= 1
            return true
        } catch {
            pendingWrites -= 1
            lastError = "Couldn't save your protection rule. Nothing was changed."
            if (try? await store.protectionRules()) == nil {
                // The write may or may not have landed and the store can't be read: fail closed.
                availability = .unavailable("Protection rules couldn't be read after a failed save.")
            }
            return false
        }
    }
}

private extension ProtectionRuleSet {
    static let empty: ProtectionRuleSet = {
        do { return try ProtectionRuleSet(rules: [], revision: 0) } catch { fatalError("an empty rule set is always valid") }
    }()
}
