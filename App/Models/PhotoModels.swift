import Foundation
import CleanSlateCore

enum GroupKind: String {
    case exact = "Verified identical files"
    case similar = "Similar captures · review required"
}

struct PhotoSnapshot: Identifiable {
    let id: String
    let record: AssetRecord
    let capturedAt: Date?
    let burstID: String?
    let width: Int
    let height: Int

    var pixelCount: Int64 { Int64(width) * Int64(height) }
}

struct PhotoReviewGroup: Identifiable {
    let id: String
    let kind: GroupKind
    let keeper: PhotoSnapshot
    let candidates: [PhotoSnapshot]
    let evidence: [PairEvidence]
    let verifiedCandidateBytes: [String: Int64]

    var all: [PhotoSnapshot] { [keeper] + candidates }
    var estimatedVerifiedBytes: Int64 { verifiedCandidateBytes.values.reduce(0, +) }

    var coreCluster: ReviewCluster {
        ReviewCluster(id: id, assets: all.map(\.record), keeperIDs: [keeper.id],
                      suggestedRemovalIDs: Set(candidates.map(\.id)), evidence: evidence)
    }
}

enum ScanPhase: String {
    case idle = "Ready"
    case inventory = "Discovering library"
    case thumbnails = "Analyzing local thumbnails"
    case candidates = "Finding possible matches"
    case fullResources = "Checking original file bytes"
    case vision = "Reviewing similar captures"
    case finished = "Review ready"
    case cancelled = "Scan paused"
}

struct ScanStatistics {
    var photosEnumerated = 0
    var thumbnailsAnalyzed = 0
    var cloudOnlyOrUnavailable = 0
    var exactAssetsVerified = 0
    var candidatePairsConsidered = 0
    var truncated = false
    /// Candidate pairs that could not be compared because Vision failed (e.g. simulator).
    var visionFailures = 0
    var lastError: String?
}

extension Int64 {
    var friendlyBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
