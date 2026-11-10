import Foundation

/// Per-device-tier scan bounds (docs/features/F03). Paging constants stay at the values the existing
/// tests pin (inventory 1,000 / features 200); governor batches chunk feature commits within a page.
struct ScanLimits: Sendable {
    let tier: DeviceTier
    /// Owner rule 4: strictly one asset in flight in this version, on every tier. The governor may
    /// still publish width 2; the engine clamps to this.
    let maxInFlight: Int
    let inventoryPage: Int
    let featurePage: Int
    /// Fingerprint thumbnail side (featureVersion 2; 128 px).
    let fingerprintSide: CGFloat
    /// Vision thumbnail side by tier.
    let visionSide: CGFloat
    /// Near-candidate pairs per pass (L 20k / M 40k / H 100k); the rest is reported, never silent.
    let candidatePairCap: Int
    /// Same-moment buckets larger than this are skipped (review sets still cover those photos).
    let momentBucketCap: Int

    init(tier: DeviceTier = .current) {
        self.tier = tier
        maxInFlight = 1
        inventoryPage = 1_000
        featurePage = 200
        fingerprintSide = 128
        switch tier {
        case .low: visionSide = 256; candidatePairCap = 20_000
        case .mid: visionSide = 320; candidatePairCap = 40_000
        case .high: visionSide = 384; candidatePairCap = 100_000
        }
        momentBucketCap = 30
    }

    /// Vision pairs this pass: at most 3 per photo in scope, and never more than 30,000.
    func visionPairCap(scopeCount: Int) -> Int { min(30_000, 3 * max(0, scopeCount)) }
}
