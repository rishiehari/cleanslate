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
