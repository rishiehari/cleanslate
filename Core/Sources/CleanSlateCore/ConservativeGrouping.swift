import Foundation

/// Safe and intentionally incomplete: groups are pairwise complete-link connected.
/// A~B and B~C must never imply A~C. Each asset occurs in at most one returned group.
public enum ConservativeGrouping {
    public static func groups(assetIDs: [String], edges: [PairEvidence], maximumGroupSize: Int = 16) -> [[String]] {
        // This reference implementation is ONLY for bounded candidate pools. A production
        // scanner must partition/index 250k+ assets before invoking grouping.
        guard maximumGroupSize >= 2, assetIDs.count <= 128 else { return [] }
        let uniqueIDs = Array(Set(assetIDs)).sorted()
        let strong = edges.filter {
            !$0.uniqueContentDetected && (
                ($0.relation == .exactResources && $0.completeResourceEquality) ||
                $0.relation == .verifiedNearDuplicate
            )
        }
        func areLinked(_ a: String, _ b: String) -> Bool {
            strong.contains { $0.joins(a, b) }
        }
        var used: Set<String> = []
        var result: [[String]] = []
        for seed in uniqueIDs where !used.contains(seed) {
            var group = [seed]
            for candidate in uniqueIDs where candidate != seed && !used.contains(candidate) {
                guard group.count < maximumGroupSize else { break }
                if group.allSatisfy({ areLinked($0, candidate) }) {
                    group.append(candidate)
                }
            }
            if group.count >= 2 {
                result.append(group)
                used.formUnion(group)
            }
        }
        return result
    }
}
