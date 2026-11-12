import Foundation
import CleanSlateCore

/// Rechecks ONE review group after the library changed underneath it (Step 6).
/// A group is kept only if it is still demonstrably what it claims to be.
@MainActor
struct GroupRechecker {
    enum Outcome {
        case unchanged
        case updated(PhotoReviewGroup)
        case dissolved(reason: String)
    }

    let library: PhotoLibraryClient
    let networkPolicy: NetworkPolicy
    let albums: Set<String>

    func recheck(_ group: PhotoReviewGroup) async -> Outcome {
        var fresh: [String: PhotoSnapshot] = [:]
        for member in group.all {
            if let photo = library.snapshot(id: member.id, inspectAlbums: false) { fresh[member.id] = ScanEngine.markAlbum(photo, albums) }
        }
        guard let keeper = fresh[group.keeper.id] else { return .dissolved(reason: "The photo you were keeping is gone") }
        let candidates = group.candidates.compactMap { fresh[$0.id] }
        guard !candidates.isEmpty else { return .dissolved(reason: "The other photos are gone") }

        let sameMembers = candidates.count == group.candidates.count
        let sameRevisions = group.all.allSatisfy { fresh[$0.id]?.record.revision == $0.record.revision }
        if sameMembers && sameRevisions { return .unchanged }

        switch group.kind {
        case .similar:
            // Similarity was a one-off visual judgement; if either photo changed, ask for a fresh scan.
            return .dissolved(reason: "These photos changed. Scan again to compare them")
        case .exact:
            // Rehash the survivors: the group stays only if every file is still byte-identical.
            let fetcher = DigestFetcher(library: library, policy: networkPolicy)
            var digests: [String: [ResourceDigest]] = [:]
            for photo in [keeper] + candidates {
                do { digests[photo.id] = try await fetcher.fetch(id: photo.id).digests }
                catch { return .dissolved(reason: "Couldn't re-check these files") }
            }
            let signatures = Set(digests.values.compactMap(ResourceSignatures.canonical))
            guard signatures.count == 1, digests.count == candidates.count + 1 else {
                return .dissolved(reason: "These files are no longer identical")
            }
            // A photo that became a favorite should be the one kept.
            let all = [keeper] + candidates
            let newKeeper = ScanEngine.preferredKeeper(all)
            let rest = all.filter { $0.id != newKeeper.id }
            let bytes = Dictionary(uniqueKeysWithValues: rest.compactMap { photo -> (String, Int64)? in
                digests[photo.id].flatMap(ResourceSignatures.logicalBytes).map { (photo.id, $0) }
            })
            return .updated(PhotoReviewGroup(
                id: group.id, kind: .exact, keeper: newKeeper, candidates: rest,
                evidence: rest.map { PairEvidence(first: newKeeper.id, second: $0.id, relation: .exactResources, completeResourceEquality: true) },
                verifiedCandidateBytes: bytes))
        }
    }
}

/// Decides whether an approved tray entry is still safe to delete, in plain words (Step 6.5).
@MainActor
struct TrayChecker {
    let library: PhotoLibraryClient
    /// Shown for an approved photo that a protection rule now covers.
    static let protectedByRuleReason = "Protected by your rule — always kept"

    /// nil = still fine. Otherwise the reason the user needs to take another look.
    func reasonNeedingAnotherLook(_ entry: TrayEntry) -> String? {
        let involved = entry.group.all.filter { entry.involvedIDs.contains($0.id) }
        var fresh: [String: AssetRecord] = [:]
        for member in involved {
            guard let current = library.snapshot(id: member.id, inspectAlbums: true) else { return "A photo was already deleted" }
            fresh[member.id] = current.record
            if current.record.revision != member.record.revision {
                if current.record.flags.contains(.favorite) && !member.record.flags.contains(.favorite) { return "You favorited one of these photos" }
                return "A photo changed since you approved it"
            }
        }
        let plan = ApprovedDeletionPlan(
            selectedIDs: entry.selectedIDs, keeperIDs: entry.effectiveKeeperIDs,
            expectedRevisions: Dictionary(uniqueKeysWithValues: involved.map { ($0.id, $0.record.revision) }),
            wasExplicitlyConfirmedByUser: true, evidence: entry.group.evidence, manuallyReviewedIDs: entry.manuallyReviewedIDs)
        return SafetyPolicy.validateCommit(plan, currentByID: fresh).map(Self.words)
    }

    func reasonNeedingAnotherLook(_ entry: StandaloneTrayEntry) -> String? {
        var fresh: [String: AssetRecord] = [:]
        for item in entry.items {
            guard let current = library.snapshot(id: item.id, inspectAlbums: true) else { return "A photo was already deleted" }
            fresh[item.id] = current.record
            if current.record.revision != item.snapshot.record.revision {
                if current.record.flags.contains(.favorite) && !item.snapshot.record.flags.contains(.favorite) { return "You favorited one of these photos" }
                return "A photo changed since you approved it"
            }
        }
        let ids = Set(entry.items.map(\.id))
        let plan = StandaloneDeletionPlan(selectedIDs: ids,
                                          expectedRevisions: Dictionary(uniqueKeysWithValues: entry.items.map { ($0.id, $0.snapshot.record.revision) }),
                                          individuallyConfirmedIDs: ids, wasExplicitlyConfirmedByUser: true)
        return SafetyPolicy.validateStandalone(plan, currentByID: fresh).map(Self.words)
    }

    static func words(_ reason: ReviewReason) -> String {
        switch reason {
        case .protected: "One of these photos is now protected, for example a favorite or in an album"
        case .staleRevision: "A photo changed since you approved it"
        case .missingAsset, .missingKeeper: "A photo is no longer in your library"
        default: "This group needs another look"
        }
    }
}
