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
    /// Like `verdict`, but a pending write does not make the answer indeterminate. For MARKING things as protected
    /// (tray invalidation), where "protected by the rules loaded so far" is already enough. Never use it to allow a deletion.
    func ruleVerdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict
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

    /// Decorates every member of a group. `settled` uses `ruleVerdict` (a pending write does not make photos "uncertain").
    func decoratedGroup(_ group: PhotoReviewGroup, settled: Bool = false) -> PhotoReviewGroup {
        func decorate(_ snapshot: PhotoSnapshot) -> PhotoSnapshot {
            guard settled else { return decorated(snapshot) }
            let flag: PreservationFlag
            switch ruleVerdict(for: snapshot) {
            case .unprotected: return snapshot
            case .protected: flag = .userProtected
            case .indeterminate: flag = .uncertainMetadata
            }
            var copy = snapshot
            copy.record = Self.record(snapshot.record, adding: flag)
            return copy
        }
        return PhotoReviewGroup(id: group.id, kind: group.kind, keeper: decorate(group.keeper),
                                candidates: group.candidates.map(decorate), evidence: group.evidence,
                                verifiedCandidateBytes: group.verifiedCandidateBytes)
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
    /// Where the real database lives when `store` is only an in-memory stand-in. If a file exists there, rules may exist in it.
    private let onDiskDatabasePath: String?
    private var ruleSet: ProtectionRuleSet
    #if DEBUG
    /// Test seam: makes the next rule-set rebuild after a committed write fail.
    var debugFailNextRebuild = false
    #endif

    /// - Parameter requiresDurableStore: writes are refused on the in-memory fallback store, because rules that
    ///   cannot be kept must never look protected.
    /// - Parameter onDiskDatabasePath: pass the real database path ONLY when `store` is a fallback because opening it failed.
    init(store: LibraryStore, defaults: UserDefaults = .standard, requiresDurableStore: Bool = true,
         onDiskDatabasePath: String? = nil) {
        self.store = store
        self.defaults = defaults
        self.requiresDurableStore = requiresDurableStore
        self.onDiskDatabasePath = onDiskDatabasePath
        // An empty set is safe here: `availability` starts at `.loading`, which makes every verdict indeterminate.
        self.ruleSet = ProtectionRuleSet.empty
    }

    private var storeIsDurable: Bool { store.path != nil }

    // MARK: Gate

    func verdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict {
        if availability == .ready, pendingWrites > 0 { return .indeterminate(.ruleWritePending) }
        return ruleVerdict(for: snapshot)
    }

    func ruleVerdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict {
        switch availability {
        case .loading: return .indeterminate(.rulesLoading)
        case .unavailable, .lost: return .indeterminate(.rulesUnavailable)
        case .ready: break
        }
        // The App cannot resolve album membership yet, so album rules answer "unknown" (fail closed).
        return ruleSet.verdict(ProtectionSubject(id: snapshot.id, capturedAt: snapshot.capturedAt, albumIDs: nil))
    }

    private func buildRuleSet(_ rules: [ProtectionRule], revision: Int64) throws -> ProtectionRuleSet {
        #if DEBUG
        if debugFailNextRebuild { debugFailNextRebuild = false; throw ProtectionRuleSet.Invalid.emptyInterval }
        #endif
        return try ProtectionRuleSet(rules: rules, revision: revision)
    }

    // MARK: Load

    /// Reads the rules and decides the availability. Safe to call again (retry).
    func load() async {
        let everCreated = defaults.bool(forKey: Self.everCreatedKey)
        let mirrored = Int64(defaults.integer(forKey: Self.lastRevisionKey))
        // Evidence that rules exist which does NOT depend on UserDefaults (which can be cleared or restored independently).
        var evidence = false
        if !storeIsDurable, let path = onDiskDatabasePath, FileManager.default.fileExists(atPath: path) { evidence = true }
        var state: (revision: Int64, rules: [ProtectionRule])?
        var set: ProtectionRuleSet?
        let outcome: Result<Int64, Error>
        do {
            let read = try await store.protectionRules()
            state = read
            set = try buildRuleSet(read.rules, revision: read.revision)
            outcome = .success(read.revision)
        } catch {
            // Rows that cannot be understood, or a missing revision row, prove that rules exist, whatever UserDefaults says.
            if error is ProtectionRuleSet.Invalid { evidence = true }
            if case LibraryStore.StoreError.malformedProtectionRule = error { evidence = true }
            if case LibraryStore.StoreError.protectionRevisionMissing = error { evidence = true }
            outcome = .failure(error)
        }
        let decision = ProtectionLoadPolicy.availability(read: outcome, everCreated: everCreated, mirroredRevision: mirrored,
                                                         storeDurable: storeIsDurable, evidenceOfExistingRules: evidence)
        if let state {
            // Always list what is stored, even when the set is unusable, so the user can still remove rules.
            // Never let an older read lower the revision under a newer in-flight write (the write publishes its own).
            if state.revision >= revision || pendingWrites == 0 { rules = state.rules; revision = state.revision }
        } else if decision == .ready {
            rules = []                                     // never created, nothing to read
        }
        if let set, decision == .ready || decision == .lost { ruleSet = set }
        else if decision == .ready { ruleSet = ProtectionRuleSet.empty }
        availability = decision
        if decision == .ready {
            lastError = nil
            // Rebuild the UserDefaults sentinel from the database when it was cleared.
            if let state, storeIsDurable, !state.rules.isEmpty || state.revision > 1 {
                defaults.set(true, forKey: Self.everCreatedKey)
                if Int(state.revision) > Int(mirrored) { defaults.set(Int(state.revision), forKey: Self.lastRevisionKey) }
            }
        }
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
        let existing = Set(rules.compactMap { rule -> String? in if case .asset(let id) = rule.scope { id } else { nil } })
        let new = ids.filter { !existing.contains($0) }.map { ProtectionRule(scope: .asset(localIdentifier: $0), createdAt: now) }
        return await write(creating: true, change: .added, adding: new) { [store] in try await store.insertProtectionRules(new) }
    }

    @discardableResult
    func protect(range: ClosedRange<LocalDay>, timeZoneID: String = TimeZone.current.identifier) async -> Bool {
        guard let interval = ProtectionDateResolver.interval(start: range.lowerBound, end: range.upperBound, timeZoneID: timeZoneID) else {
            lastError = "That date range isn't valid."
            return false
        }
        let rule = ProtectionRule(scope: .dateRange(start: range.lowerBound, end: range.upperBound, timeZoneID: timeZoneID,
                                                    startInclusive: interval.start, endExclusive: interval.endExclusive))
        let duplicate = rules.contains { existing in
            if case .dateRange(let s, let e, let z, _, _) = existing.scope { return s == range.lowerBound && e == range.upperBound && z == timeZoneID }
            return false
        }
        return await write(creating: true, change: .added, adding: duplicate ? [] : [rule]) { [store] in try await store.insertProtectionRules([rule]) }
    }

    /// For callers that detect an impossible range before asking.
    func reportInvalidRange() { lastError = "That date range isn't valid." }

    @discardableResult
    func remove(ruleID: UUID) async -> Bool {
        await write(creating: false, change: .removed, adding: [], allowWhenUnavailable: true) { [store] in try await store.deleteProtectionRule(id: ruleID) }
    }

    @discardableResult
    func removeAll() async -> Bool {
        await write(creating: false, change: .removed, adding: [], allowWhenUnavailable: true) { [store] in try await store.deleteAllProtectionRules() }
    }

    /// One write: validate BEFORE touching the store, mark pending synchronously, persist, rebuild from the store, publish,
    /// notify, then clear pending. Nothing looks protected before the store confirmed the write, and anything that goes
    /// wrong AFTER a commit makes the rules unavailable (never "nothing was changed").
    /// Removals are also allowed from `.unavailable` (a broken rule set must never lock the user out of fixing it).
    private func write(creating: Bool, change: ProtectionChange, adding: [ProtectionRule], allowWhenUnavailable: Bool = false,
                       _ operation: () async throws -> Int64) async -> Bool {
        var startedUnavailable = false
        switch availability {
        case .ready: break
        case .unavailable where allowWhenUnavailable: startedUnavailable = true
        default:
            lastError = "Protection rules aren't available right now."
            return false
        }
        guard storeIsDurable || !requiresDurableStore else {
            lastError = "Protection rules can't be saved on this device right now. Nothing was changed."
            return false
        }
        if !adding.isEmpty, let message = validationFailure(adding) { lastError = message; return false }
        pendingWrites += 1
        lastError = nil
        if creating { defaults.set(true, forKey: Self.everCreatedKey) }
        do {
            _ = try await operation()
        } catch {
            pendingWrites -= 1
            lastError = "Couldn't save your protection rule. Nothing was changed."
            if (try? await store.protectionRules()) == nil, !startedUnavailable {
                // The write may or may not have landed and the store can't be read: fail closed.
                availability = .unavailable("Protection rules couldn't be read after a failed save.")
            }
            return false
        }
        // Committed from here on.
        if startedUnavailable {
            pendingWrites -= 1
            await load()
            if availability != .ready { lastError = "Some protection rules still can't be read. Remove them to continue." }
            return availability == .ready
        }
        do {
            let state = try await store.protectionRules()
            let set = try buildRuleSet(state.rules, revision: state.revision)
            // A slower, older read must never overwrite a newer one (overlapping writes).
            if state.revision >= revision {
                ruleSet = set; rules = state.rules; revision = state.revision
                if Int(state.revision) > defaults.integer(forKey: Self.lastRevisionKey) {
                    defaults.set(Int(state.revision), forKey: Self.lastRevisionKey)
                }
            }
            onChange?(change)
            pendingWrites -= 1
            return true
        } catch {
            pendingWrites -= 1
            availability = .unavailable("Your protection change was saved, but the rules couldn't be reloaded.")
            lastError = "Your change was saved, but protection rules couldn't be reloaded. Try again."
            onChange?(.reloaded)
            return false
        }
    }

    /// Would the rule set still be valid with these rules added? nil = yes. Checked BEFORE anything is written.
    private func validationFailure(_ adding: [ProtectionRule]) -> String? {
        do {
            _ = try ProtectionRuleSet(rules: rules + adding, revision: revision)
            return nil
        } catch ProtectionRuleSet.Invalid.tooManyAssetRules {
            return "You've reached the limit of \(ProtectionRuleSet.maximumAssetRules) protected photos. Remove some to add more."
        } catch ProtectionRuleSet.Invalid.tooManyDateRules {
            return "You've reached the limit of \(ProtectionRuleSet.maximumDateRules) protected date ranges. Remove some to add more."
        } catch {
            return "That protection rule isn't valid."
        }
    }
}

private extension ProtectionRuleSet {
    static let empty: ProtectionRuleSet = {
        do { return try ProtectionRuleSet(rules: [], revision: 0) } catch { fatalError("an empty rule set is always valid") }
    }()
}

/// Wraps the real gate for one scan session: a photo that was protected at any point this session stays protected until
/// the next scan, so removing a rule mid-session can never bring a suggestion back ("protection only grows").
@MainActor
final class SessionShieldingGate: ProtectionGate {
    private let inner: ProtectionGate
    private var shieldedIDs: Set<String> = []

    init(_ inner: ProtectionGate) { self.inner = inner }

    var availability: ProtectionAvailability { inner.availability }
    var revision: Int64 { inner.revision }
    var pendingWrites: Int { inner.pendingWrites }

    func verdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict { shield(inner.verdict(for: snapshot), snapshot.id) }
    func ruleVerdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict { shield(inner.ruleVerdict(for: snapshot), snapshot.id) }

    /// A new scan starts a new session.
    func resetSession() { shieldedIDs.removeAll() }

    private func shield(_ verdict: ProtectionVerdict, _ id: String) -> ProtectionVerdict {
        switch verdict {
        case .protected: shieldedIDs.insert(id); return verdict
        case .unprotected: return shieldedIDs.contains(id) ? .protected(ruleIDs: []) : verdict
        case .indeterminate: return verdict
        }
    }
}
