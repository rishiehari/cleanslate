import Foundation

public enum SafetyPolicy {
    /// Pure recommendation decisions. No PhotoKit mutation can happen in this package.
    public static func evaluate(_ cluster: ReviewCluster,
                                configuration: PreselectionConfiguration = .init()) -> ReviewDecision {
        let ids = cluster.assets.map(\.id)
        let known = Set(ids)
        let duplicates = Set(ids.filter { id in ids.filter { $0 == id }.count > 1 })
        var preselected: Set<String> = []
        var reviewOnly: Set<String> = []
        var blocked: [String: ReviewReason] = [:]

        for targetID in cluster.suggestedRemovalIDs.sorted() {
            guard !duplicates.contains(targetID) else { blocked[targetID] = .duplicateAssetID; continue }
            guard let target = cluster.assets.first(where: { $0.id == targetID }) else {
                blocked[targetID] = .missingAsset; continue
            }
            guard !target.revision.isEmpty else { blocked[targetID] = .staleRevision; continue }
            guard target.flags.isDisjoint(with: PreservationFlag.hard) else { blocked[targetID] = .protected; continue }
            guard !cluster.keeperIDs.isEmpty else { blocked[targetID] = .missingKeeper; continue }
            guard cluster.keeperIDs.isDisjoint(with: cluster.suggestedRemovalIDs) else {
                blocked[targetID] = .keeperAlsoRemoved; continue
            }
            guard cluster.keeperIDs.isSubset(of: known) else { blocked[targetID] = .missingKeeper; continue }
            guard !cluster.keeperIDs.contains(targetID) else { blocked[targetID] = .keeperAlsoRemoved; continue }
            // For a deletion to be recommended, there must be DIRECT evidence to a live keeper;
            // transitive graph paths do not count.
            let links = cluster.evidence.filter { item in
                cluster.keeperIDs.contains(where: { item.joins(targetID, $0) })
            }
            guard !links.isEmpty else { blocked[targetID] = .missingProof; continue }
            if links.contains(where: { $0.uniqueContentDetected || $0.relation == .distinct }) {
                blocked[targetID] = .uniqueDifference; continue
            }
            if links.contains(where: { $0.calibratedRedundancyProbability.map { !$0.isFinite || $0 < 0 || $0 > 1 } ?? false }) {
                blocked[targetID] = .invalidConfidence; continue
            }
            // Live / edited / RAW targets: only a byte-identical keeper with the same flags may stand in.
            let conditionalFlags = target.flags.intersection(PreservationFlag.conditional)
            if !conditionalFlags.isEmpty {
                let covered = cluster.keeperIDs.contains { keeperID in
                    guard let keeper = cluster.assets.first(where: { $0.id == keeperID }),
                          conditionalFlags.isSubset(of: keeper.flags) else { return false }
                    return links.contains { $0.joins(targetID, keeperID) && $0.relation == .exactResources && $0.completeResourceEquality }
                }
                guard covered else { blocked[targetID] = .protected; continue }
            }
            if links.contains(where: { $0.relation == .exactResources && $0.completeResourceEquality }) {
                preselected.insert(targetID)
                continue
            }
            let trustedNear = links.contains { item in
                guard item.relation == .verifiedNearDuplicate,
                      let p = item.calibratedRedundancyProbability else { return false }
                return p >= configuration.minimumCalibratedProbability
            }
            if trustedNear && configuration.nearEnabled && configuration.independentSafetyGatePassed &&
                configuration.minimumCalibratedProbability >= 0 && configuration.minimumCalibratedProbability <= 1 {
                preselected.insert(targetID)
            } else {
                reviewOnly.insert(targetID)
            }
        }
        return ReviewDecision(preselected: preselected, reviewOnly: reviewOnly, blocked: blocked)
    }

    /// True if the record carries a flag that always blocks deletion. Single source of truth for
    /// the app's post-hash revalidation as well.
    public static func hardBlocked(_ record: AssetRecord) -> Bool {
        !record.flags.isDisjoint(with: PreservationFlag.hard)
    }

    /// Just-in-time defense before invoking a PhotoKit change request.
    /// Caller MUST freshly fetch all records at commit time, then pass them here.
    public static func validateCommit(_ plan: ApprovedDeletionPlan,
                                      currentByID: [String: AssetRecord]) -> ReviewReason? {
        guard plan.wasExplicitlyConfirmedByUser else { return .userConfirmationRequired }
        guard !plan.selectedIDs.isEmpty,
              !plan.keeperIDs.isEmpty,
              plan.selectedIDs.isDisjoint(with: plan.keeperIDs) else { return .invalidSelection }
        let involved = plan.selectedIDs.union(plan.keeperIDs)
        guard involved.allSatisfy({ currentByID[$0] != nil && plan.expectedRevisions[$0] != nil }) else {
            return .missingAsset
        }
        for id in involved {
            guard let current = currentByID[id], let expected = plan.expectedRevisions[id],
                  current.revision == expected, !expected.isEmpty else { return .staleRevision }
        }
        // Recommended removals cannot bypass preservation even when an old UI state was confirmed.
        // (Conditional flags are judged against the keeper by `evaluate` below.)
        for id in plan.selectedIDs {
            guard let record = currentByID[id], !hardBlocked(record) else { return .protected }
        }
        let freshCluster = ReviewCluster(
            id: "commit-validation", assets: involved.compactMap { currentByID[$0] },
            keeperIDs: plan.keeperIDs, suggestedRemovalIDs: plan.selectedIDs,
            evidence: plan.evidence
        )
        // Near-duplicate auto-preselection remains disabled here by default. A future release
        // may introduce a signed, independently validated policy configuration.
        let decision = evaluate(freshCluster)
        for id in plan.selectedIDs {
            if decision.preselected.contains(id) { continue }
            if decision.reviewOnly.contains(id) && plan.manuallyReviewedIDs.contains(id) { continue }
            return decision.blocked[id] ?? .invalidSelection
        }
        return nil
    }
}
