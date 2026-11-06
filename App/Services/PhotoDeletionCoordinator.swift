import Foundation
import Photos
import CleanSlateCore

@MainActor
final class PhotoDeletionCoordinator {
    static let shared = PhotoDeletionCoordinator()
    private let catalog = PhotoCatalog.shared
    private var activeCommit = false

    enum DeletionError: LocalizedError {
        case busy, revoked, vanished, unsafe(String), changedResource, noSelection, confirmationFailed
        var errorDescription: String? {
            switch self {
            case .busy: "Another photo deletion is still being reconciled."
            case .revoked: "Photos permissions changed. No deletion was attempted."
            case .vanished: "A photo or its keeper is no longer available. Please rescan."
            case .unsafe(let reason): "Safety policy blocked deletion: \(reason)."
            case .changedResource: "Original resource bytes changed. Please rescan before deleting."
            case .noSelection: "No eligible photos are selected."
            case .confirmationFailed: "Photos did not confirm the deletion."
            }
        }
    }

    struct DeletionResult {
        let requested: Int
        let verifiedRemoved: Int
        let logicalBytesRemoved: Int64
        let uncertain: Int
    }

    /// Only invoked after the user reviews the image pair(s) and confirms an additional
    /// SwiftUI alert. PhotoKit presents its OWN OS confirmation as the final authority.
    /// Photos deletion is not transactional with iCloud synchronization: reconcile afterward.
    func commit(group: PhotoReviewGroup, selected: Set<String>, manuallyReviewed: Set<String>) async throws -> DeletionResult {
        guard !activeCommit else { throw DeletionError.busy }
        guard !selected.isEmpty else { throw DeletionError.noSelection }
        guard [.authorized, .limited].contains(catalog.authorization) else { throw DeletionError.revoked }
        activeCommit = true
        defer { activeCommit = false }

        let involved = selected.union([group.keeper.id])
        var fresh: [String: AssetRecord] = [:]
        var phAssets: [String: PHAsset] = [:]
        for id in involved {
            guard let asset = catalog.fetchAsset(id) else { throw DeletionError.vanished }
            let snapshot = catalog.snapshot(asset, inspectAlbums: true)
            fresh[id] = snapshot.record
            phAssets[id] = asset
        }
        let expected = Dictionary(uniqueKeysWithValues: group.all.map { ($0.id, $0.record.revision) })
        let plan = ApprovedDeletionPlan(selectedIDs: selected, keeperIDs: [group.keeper.id],
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
            guard let keeper = phAssets[group.keeper.id] else { throw DeletionError.vanished }
            let keeperSignature = ResourceSignatures.canonical(try await catalog.completeDigests(keeper))
            guard let keeperSignature else { throw DeletionError.changedResource }
            for id in selected {
                guard let asset = phAssets[id],
                      let signature = ResourceSignatures.canonical(try await catalog.completeDigests(asset)),
                      signature == keeperSignature else { throw DeletionError.changedResource }
            }
        }

        // Revalidate after asynchronous hashes, too: favorites/edits may have changed in between.
        for id in involved {
            guard let current = catalog.fetchAsset(id),
                  catalog.snapshot(current, inspectAlbums: true).record.revision == expected[id],
                  catalog.snapshot(current, inspectAlbums: true).record.flags.isEmpty || id == group.keeper.id else {
                throw DeletionError.vanished
            }
        }
        guard [.authorized, .limited].contains(catalog.authorization) else { throw DeletionError.revoked }
        let deletables = selected.sorted().compactMap { catalog.fetchAsset($0) }
        guard deletables.count == selected.count else { throw DeletionError.vanished }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(deletables as NSArray)
        }

        let access = catalog.authorization
        var removed = 0
        var bytes: Int64 = 0
        for id in selected {
            // Absence with restricted/limited permissions cannot conclusively establish deletion.
            if access == .authorized && catalog.fetchAsset(id) == nil {
                removed += 1
                bytes += group.verifiedCandidateBytes[id] ?? 0
            }
        }
        return DeletionResult(requested: selected.count, verifiedRemoved: removed,
                              logicalBytesRemoved: bytes, uncertain: selected.count - removed)
    }
}
