import Foundation
import Photos
import CleanSlateCore

enum GroupKind: String, Codable {
    case exact = "Verified identical files"
    case similar = "Similar captures · review required"
}

struct PhotoSnapshot: Identifiable, Codable, Equatable {
    let id: String
    let record: AssetRecord
    let capturedAt: Date?
    let burstID: String?
    let width: Int
    let height: Int
    /// Original filename of the primary resource (used only to find hash candidates).
    var originalFilename: String? = nil
    var isVideo: Bool = false
    var durationSeconds: Double = 0
    /// Raw `PHAssetMediaSubtype` bits.
    var subtypes: UInt = 0

    var isScreenshot: Bool { PHAssetMediaSubtype(rawValue: subtypes).contains(.photoScreenshot) }
    var isScreenRecording: Bool { PHAssetMediaSubtype(rawValue: subtypes).contains(.videoScreenRecording) }

    var pixelCount: Int64 { Int64(width) * Int64(height) }
}

struct PhotoReviewGroup: Identifiable, Codable {
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
    case sizing = "Measuring files"
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
    /// Exact-copy coverage (Step 3.5).
    var exactBucketsFound = 0
    var exactAssetsHashed = 0
    var exactAssetsUnverifiable = 0      // not local (iCloud), incomplete or failed
    var exactSkippedByLimit = 0          // past the per-scan hashing cap
    var originalsDownloaded = 0          // only with the opt-in iCloud verification
    var bucketsOversized = 0
    var lastError: String?
}

extension Int64 {
    var friendlyBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
