import Foundation
import Photos
import CleanSlateCore

@MainActor
final class PhotoDeletionCoordinator {
    private let library: PhotoLibraryClient
    private let networkPolicy: NetworkPolicy
    private var activeCommit = false

    /// The commit-time recheck reads local files first. It downloads only if the user opted in to
    /// iCloud checking (same budget), because a group that was verified through a download must stay deletable.
    init(library: PhotoLibraryClient, networkPolicy: NetworkPolicy? = nil) {
        self.library = library
        self.networkPolicy = networkPolicy ?? NetworkPolicy.shared
    }

    enum DeletionError: LocalizedError, Equatable {
        case busy, revoked, vanished, unsafe(String), changedResource, cannotVerify, noSelection, confirmationFailed
        var errorDescription: String? {
            switch self {
            case .busy: "Another photo deletion is still being reconciled."
            case .revoked: "Photos permissions changed. No deletion was attempted."
            case .vanished: "A photo or its keeper is no longer available. Please rescan."
            case .unsafe(let reason): "Safety policy blocked deletion: \(reason)."
            case .changedResource: "Original resource bytes changed. Please rescan before deleting."
            case .cannotVerify: "Couldn't verify the original files right now. Nothing was deleted."
            case .noSelection: "No eligible photos are selected."
            case .confirmationFailed: "Photos did not confirm the deletion."
            }
        }
    }

    struct DeletionResult: Equatable {
        let requested: Int
        let verifiedRemoved: Int
        let logicalBytesRemoved: Int64
        let uncertain: Int
    }

    private var hasAccess: Bool { [.authorized, .limited].contains(library.authorization) }

    /// Only invoked after the user reviews the image pair(s) and confirms an additional
    /// SwiftUI alert. PhotoKit presents its OWN OS confirmation as the final authority.
    /// Photos deletion is not transactional with iCloud synchronization: reconcile afterward.
    func commit(group: PhotoReviewGroup, selected: Set<String>, manuallyReviewed: Set<String>,
                keeperIDs: Set<String>? = nil) async throws -> DeletionResult {
        guard !activeCommit else { throw DeletionError.busy }
        guard !selected.isEmpty else { throw DeletionError.noSelection }
        guard hasAccess else { throw DeletionError.revoked }
        activeCommit = true
        defer { activeCommit = false }

        let keepers = keeperIDs ?? [group.keeper.id]            // the user may keep several photos
        let involved = selected.union(keepers)
        var fresh: [String: AssetRecord] = [:]
        for id in involved {
            guard let snapshot = library.snapshot(id: id, inspectAlbums: true) else { throw DeletionError.vanished }
            fresh[id] = snapshot.record
        }
        let expected = Dictionary(uniqueKeysWithValues: group.all.map { ($0.id, $0.record.revision) })
        let plan = ApprovedDeletionPlan(selectedIDs: selected, keeperIDs: keepers,
                                        expectedRevisions: expected,
                                        wasExplicitlyConfirmedByUser: true,
                                        evidence: group.evidence,
                                        manuallyReviewedIDs: manuallyReviewed)
        if let invalid = SafetyPolicy.validateCommit(plan, currentByID: fresh) {
            throw DeletionError.unsafe(invalid.rawValue)
        }

        // For exact duplicates, rehash all ORIGINAL resources immediately before mutation,
        // not merely their cached fingerprints or metadata revisions.
        if group.kind == .exact {
            // Every kept photo AND every photo to delete must still be byte-identical to each other.
            let firstKeeper = keepers.sorted()[0]
            let keeperSignature = ResourceSignatures.canonical(try await verifiedDigests(firstKeeper))
            guard let keeperSignature else { throw DeletionError.changedResource }
            for id in selected.union(keepers.subtracting([firstKeeper])).sorted() {
                guard let signature = ResourceSignatures.canonical(try await verifiedDigests(id)),
                      signature == keeperSignature else { throw DeletionError.changedResource }
            }
        }

        // Revalidate after asynchronous hashes, too: favorites/edits may have changed in between.
        // The FULL policy runs again on fresh records (not just the hard flags), so a conditional
        // flag appearing late (e.g. "edited") is judged against the keeper as well.
        var freshAfterHash: [String: AssetRecord] = [:]
        for id in involved {
            guard let current = library.snapshot(id: id, inspectAlbums: true),
                  current.record.revision == expected[id] else { throw DeletionError.vanished }
            freshAfterHash[id] = current.record
        }
        if let invalid = SafetyPolicy.validateCommit(plan, currentByID: freshAfterHash) {
            throw DeletionError.unsafe(invalid.rawValue)
        }
        guard hasAccess else { throw DeletionError.revoked }

        do {
            try await library.delete(ids: Array(selected), expectedRevisions: expected)
        } catch LibraryResourceError.notAccessible {
            throw DeletionError.vanished
        } catch LibraryResourceError.changed {
            throw DeletionError.changedResource
        }

        let access = library.authorization
        var removed = 0
        var bytes: Int64 = 0
        for id in selected {
            // Absence with restricted/limited permissions cannot conclusively establish deletion.
            if access == .authorized && library.snapshot(id: id, inspectAlbums: false) == nil {
                removed += 1
                bytes += group.verifiedCandidateBytes[id] ?? 0
            }
        }
        return DeletionResult(requested: selected.count, verifiedRemoved: removed,
                              logicalBytesRemoved: bytes, uncertain: selected.count - removed)
    }

    /// Maps "can't read the original" failures to a safe, explicit abort. Cancellation passes through.
    private func verifiedDigests(_ id: String) async throws -> [ResourceDigest] {
        do {
            return try await DigestFetcher(library: library, policy: networkPolicy).fetch(id: id).digests
        } catch let error as LibraryResourceError {
            switch error {
            case .cancelled: throw CancellationError()
            case .changed: throw DeletionError.changedResource
            case .notAccessible, .empty: throw DeletionError.cannotVerify
            }
        }
    }

    /// Keeper-less deletion (screenshots, recordings, large videos). Uses the separate
    /// `validateStandalone` policy; `commit` (duplicates) can never be used for these items.
    func commitStandalone(items: [StandaloneItem]) async throws -> DeletionResult {
        guard !activeCommit else { throw DeletionError.busy }
        guard !items.isEmpty else { throw DeletionError.noSelection }
        guard hasAccess else { throw DeletionError.revoked }
        activeCommit = true
        defer { activeCommit = false }

        let ids = Set(items.map(\.id))
        var fresh: [String: AssetRecord] = [:]
        for id in ids {
            guard let snapshot = library.snapshot(id: id, inspectAlbums: true) else { throw DeletionError.vanished }
            fresh[id] = snapshot.record
        }
        let expected = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.snapshot.record.revision) })
        // The user selected each item in the list (or chose "select all" and saw the count); the tray holds only those.
        let plan = StandaloneDeletionPlan(selectedIDs: ids, expectedRevisions: expected,
                                          individuallyConfirmedIDs: ids, wasExplicitlyConfirmedByUser: true)
        if let invalid = SafetyPolicy.validateStandalone(plan, currentByID: fresh) {
            throw DeletionError.unsafe(invalid.rawValue)
        }
        guard hasAccess else { throw DeletionError.revoked }
        do {
            try await library.delete(ids: Array(ids), expectedRevisions: expected)
        } catch LibraryResourceError.notAccessible {
            throw DeletionError.vanished
        } catch LibraryResourceError.changed {
            throw DeletionError.changedResource
        }
        let access = library.authorization
        var removed = 0
        var bytes: Int64 = 0
        for item in items where access == .authorized && library.snapshot(id: item.id, inspectAlbums: false) == nil {
            removed += 1
            bytes += item.verifiedBytes ?? 0
        }
        return DeletionResult(requested: ids.count, verifiedRemoved: removed, logicalBytesRemoved: bytes, uncertain: ids.count - removed)
    }
}

/// What a batch commit reports. Either nothing was deleted (`blocked`), or everything that was requested was
/// sent to Apple in ONE request (`completed`).
enum BatchOutcome {
    /// Nothing was deleted. Maps each affected tray entry id to a plain-words reason.
    case blocked([String: String])
    case completed(BatchReceipt)
}

struct BatchReceipt: Equatable {
    var requested = 0
    var verifiedRemoved = 0
    var uncertain = 0
    var logicalBytesRemoved: Int64 = 0
    /// Entry ids that were removed completely (they leave the tray).
    var removedEntryIDs: Set<String> = []
}

extension PhotoDeletionCoordinator {
    /// Deletes everything the user approved with ONE system confirmation.
    /// Order: fresh snapshots -> batch policy -> rehash every exact group (progress, cancellable) ->
    /// snapshots and policy AGAIN -> a single delete request -> reconcile. Any problem anywhere means nothing is deleted.
    func commitBatch(groups: [TrayEntry], standalone: [StandaloneTrayEntry],
                     progress: ((Int, Int) -> Void)? = nil) async throws -> BatchOutcome {
        guard !activeCommit else { throw DeletionError.busy }
        guard !groups.isEmpty || !standalone.isEmpty else { throw DeletionError.noSelection }
        guard [.authorized, .limited].contains(library.authorization) else { throw DeletionError.revoked }
        activeCommit = true
        defer { activeCommit = false }

        // 1. + 2. Fresh state, then the whole-batch policy.
        if let blocked = evaluate(groups: groups, standalone: standalone) { return .blocked(blocked) }

        // 3. Rehash every exact group's kept and deleted photos (this is the slow part; report progress, allow cancel).
        let exact = groups.filter { $0.group.kind == .exact }
        for (index, entry) in exact.enumerated() {
            try Task.checkCancellation()
            progress?(index, exact.count)
            let involved = entry.involvedIDs.sorted()
            var reference: String?
            for id in involved {
                let digests: [ResourceDigest]
                do { digests = try await DigestFetcher(library: library, policy: networkPolicy).fetch(id: id).digests }
                catch let error as LibraryResourceError where error == .cancelled { throw CancellationError() }
                catch { return .blocked([entry.id: "Couldn't re-check the original files"]) }
                guard let signature = ResourceSignatures.canonical(digests) else { return .blocked([entry.id: "Couldn't re-check the original files"]) }
                if let reference, reference != signature { return .blocked([entry.id: "These files are no longer identical"]) }
                reference = signature
            }
        }
        progress?(exact.count, exact.count)
        try Task.checkCancellation()

        // 4. Again, after the slow part: nothing may have changed meanwhile.
        if let blocked = evaluate(groups: groups, standalone: standalone) { return .blocked(blocked) }
        guard [.authorized, .limited].contains(library.authorization) else { throw DeletionError.revoked }

        // 5. ONE request, ONE system prompt.
        var targets: Set<String> = []
        var expected: [String: String] = [:]
        for entry in groups {
            targets.formUnion(entry.selectedIDs)
            for member in entry.group.all where entry.involvedIDs.contains(member.id) { expected[member.id] = member.record.revision }
        }
        for entry in standalone {
            for item in entry.items { targets.insert(item.id); expected[item.id] = item.snapshot.record.revision }
        }
        do {
            try await library.delete(ids: Array(targets), expectedRevisions: expected)
        } catch LibraryResourceError.notAccessible {
            throw DeletionError.vanished
        } catch LibraryResourceError.changed {
            throw DeletionError.changedResource
        }

        // 6. Reconcile per entry. Absence is only conclusive with full access.
        let conclusive = library.authorization == .authorized
        var receipt = BatchReceipt()
        for entry in groups {
            let gone = entry.selectedIDs.filter { conclusive && library.snapshot(id: $0, inspectAlbums: false) == nil }
            receipt.requested += entry.selectedIDs.count
            receipt.verifiedRemoved += gone.count
            receipt.uncertain += entry.selectedIDs.count - gone.count
            receipt.logicalBytesRemoved += gone.reduce(Int64(0)) { $0 + (entry.group.verifiedCandidateBytes[$1] ?? 0) }
            if gone.count == entry.selectedIDs.count { receipt.removedEntryIDs.insert(entry.id) }
        }
        for entry in standalone {
            let gone = entry.items.filter { conclusive && library.snapshot(id: $0.id, inspectAlbums: false) == nil }
            receipt.requested += entry.items.count
            receipt.verifiedRemoved += gone.count
            receipt.uncertain += entry.items.count - gone.count
            receipt.logicalBytesRemoved += gone.reduce(Int64(0)) { $0 + ($1.verifiedBytes ?? 0) }
            if gone.count == entry.items.count { receipt.removedEntryIDs.insert(entry.id) }
        }
        return .completed(receipt)
    }

    /// Fresh snapshots + batch policy + standalone policy. nil = all fine; otherwise entry id -> reason.
    private func evaluate(groups: [TrayEntry], standalone: [StandaloneTrayEntry]) -> [String: String]? {
        var fresh: [String: AssetRecord] = [:]
        var blocked: [String: String] = [:]
        func load(_ ids: Set<String>, entryID: String) {
            for id in ids where fresh[id] == nil {
                if let snapshot = library.snapshot(id: id, inspectAlbums: true) { fresh[id] = snapshot.record }
                else { blocked[entryID] = "A photo is no longer in your library" }
            }
        }
        for entry in groups { load(entry.involvedIDs, entryID: entry.id) }
        for entry in standalone { load(Set(entry.items.map(\.id)), entryID: entry.id) }
        if !blocked.isEmpty { return blocked }

        let plans = groups.map { entry in
            ApprovedDeletionPlan(
                selectedIDs: entry.selectedIDs, keeperIDs: entry.effectiveKeeperIDs,
                expectedRevisions: Dictionary(uniqueKeysWithValues: entry.group.all.filter { entry.involvedIDs.contains($0.id) }.map { ($0.id, $0.record.revision) }),
                wasExplicitlyConfirmedByUser: true, evidence: entry.group.evidence, manuallyReviewedIDs: entry.manuallyReviewedIDs)
        }
        if !plans.isEmpty {
            let result = SafetyPolicy.validateBatch(plans, currentByID: fresh)
            for (index, reason) in result.planFailures { blocked[groups[index].id] = TrayChecker.words(reason) }
            if blocked.isEmpty, result.batchFailure != nil { for entry in groups { blocked[entry.id] = "These groups overlap, so they need another look" } }
        }
        for entry in standalone {
            let ids = Set(entry.items.map(\.id))
            let plan = StandaloneDeletionPlan(
                selectedIDs: ids, expectedRevisions: Dictionary(uniqueKeysWithValues: entry.items.map { ($0.id, $0.snapshot.record.revision) }),
                individuallyConfirmedIDs: ids, wasExplicitlyConfirmedByUser: true)
            if let reason = SafetyPolicy.validateStandalone(plan, currentByID: fresh) { blocked[entry.id] = TrayChecker.words(reason) }
        }
        return blocked.isEmpty ? nil : blocked
    }
}
