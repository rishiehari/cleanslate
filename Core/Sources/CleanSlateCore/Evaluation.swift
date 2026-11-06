import Foundation

/// One image in an evaluation manifest (the synthetic fixtures, or a labeled export).
public struct EvalRow: Sendable, Equatable {
    public let assetID: String
    public let sceneID: String
    public let variant: String
    /// Ground truth relative to the scene's base photo: reference, exact_file, visually_redundant_review, unique_*, unknown_review.
    public let label: String
    public let sha256: String
    public let hash: UInt64?
    public init(assetID: String, sceneID: String, variant: String, label: String, sha256: String, hash: UInt64?) {
        self.assetID = assetID; self.sceneID = sceneID; self.variant = variant
        self.label = label; self.sha256 = sha256; self.hash = hash
    }
}

public struct EvalReport: Codable, Equatable, Sendable {
    public struct NearRecall: Codable, Equatable, Sendable { public let maxHamming: Int; public let recall: Double; public let found: Int; public let total: Int }
    public let scenes: Int
    /// Exact copies found by byte equality / all labeled exact copies.
    public let exactRecall: Double
    /// Of everything placed in the Exact tier, the fraction that really is an exact copy.
    public let exactPrecision: Double
    /// Photos the app would PRE-SELECT (exact tier only) that a human labeled as containing something unique.
    public let harmfulPreselected: Int
    public let harmfulOpportunities: Int
    /// 95% one-sided Clopper–Pearson upper bound on the harmful-preselection rate.
    public let harmfulUpperBound95: Double?
    public let nearRecall: [NearRecall]
    /// Unique-content photos that would at least be SHOWN to the user as look-alike candidates (informational: the user decides).
    public let uniqueShownAsCandidates: Int
    public let uniqueTotal: Int
    public var meetsPreselectionGate: Bool { harmfulUpperBound95.map { $0 < 0.001 } ?? false }
}

public enum Evaluation {
    public static func evaluate(_ rows: [EvalRow], hammingThresholds: [Int] = [6, 8, 10, 12]) -> EvalReport {
        let byScene = Dictionary(grouping: rows, by: \.sceneID)
        var exactTotal = 0, exactFound = 0, exactTier = 0, exactTierCorrect = 0
        var harmful = 0, opportunities = 0, uniqueShown = 0
        var redundantTotal = 0
        var nearFound = Dictionary(uniqueKeysWithValues: hammingThresholds.map { ($0, 0) })

        for (_, group) in byScene {
            guard let base = group.first(where: { $0.label == "reference" }) else { continue }
            for row in group where row.assetID != base.assetID {
                let sameBytes = row.sha256 == base.sha256
                if sameBytes { exactTier += 1; if row.label == "exact_file" { exactTierCorrect += 1 } }
                if row.label == "exact_file" { exactTotal += 1; if sameBytes { exactFound += 1 } }
                if row.label.hasPrefix("unique_") {
                    opportunities += 1
                    if sameBytes { harmful += 1 }
                    if let a = base.hash, let b = row.hash, DifferenceHash.distance(a, b) <= 10 { uniqueShown += 1 }
                }
                if row.label == "visually_redundant_review" {
                    redundantTotal += 1
                    if let a = base.hash, let b = row.hash {
                        for t in hammingThresholds where DifferenceHash.distance(a, b) <= t { nearFound[t, default: 0] += 1 }
                    }
                }
            }
        }
        return EvalReport(
            scenes: byScene.count,
            exactRecall: exactTotal == 0 ? 1 : Double(exactFound) / Double(exactTotal),
            exactPrecision: exactTier == 0 ? 1 : Double(exactTierCorrect) / Double(exactTier),
            harmfulPreselected: harmful, harmfulOpportunities: opportunities,
            harmfulUpperBound95: SafetyStatistics.oneSidedUpperBound(failures: harmful, trials: opportunities),
            nearRecall: hammingThresholds.sorted().map { t in
                EvalReport.NearRecall(maxHamming: t, recall: redundantTotal == 0 ? 1 : Double(nearFound[t] ?? 0) / Double(redundantTotal),
                                      found: nearFound[t] ?? 0, total: redundantTotal)
            },
            uniqueShownAsCandidates: uniqueShown, uniqueTotal: opportunities)
    }

    /// Minimal CSV reader for the fixture manifest (`asset_id,scene_id,variant,relation_to_base,...,sha256`).
    public static func parseManifest(_ csv: String) -> [(assetID: String, sceneID: String, variant: String, label: String, sha256: String)] {
        let lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) else { return [] }
        func index(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let a = index("asset_id"), let s = index("scene_id"), let v = index("variant"), let l = index("relation_to_base"), let h = index("sha256") else { return [] }
        return lines.dropFirst().compactMap { line in
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cells.count > max(a, s, v, l, h) else { return nil }
            return (cells[a], cells[s], cells[v], cells[l], cells[h])
        }
    }
}
