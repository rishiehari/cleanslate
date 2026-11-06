import Foundation
import CryptoKit

/// A label a tester gave one photo in Label mode.
public struct RawLabel: Sendable, Equatable {
    public enum Verdict: String, Sendable, Codable, CaseIterable {
        case redundant, uniquePeople = "unique:people", uniqueExpression = "unique:expression"
        case uniqueText = "unique:text", uniqueMoment = "unique:moment", unsure
    }
    public let assetID: String
    public let groupID: String
    public let verdict: Verdict
    public let isBestShot: Bool
    public let flags: [String]
    public let hammingToKeeper: Int?
    public let visionDistance: Double?
    public let sharpness: Double?, faceQuality: Double?, aesthetics: Double?, exposure: Double?
    public let pixelCount: Int64
    public init(assetID: String, groupID: String, verdict: Verdict, isBestShot: Bool, flags: [String] = [],
                hammingToKeeper: Int? = nil, visionDistance: Double? = nil, sharpness: Double? = nil,
                faceQuality: Double? = nil, aesthetics: Double? = nil, exposure: Double? = nil, pixelCount: Int64 = 0) {
        self.assetID = assetID; self.groupID = groupID; self.verdict = verdict; self.isBestShot = isBestShot; self.flags = flags
        self.hammingToKeeper = hammingToKeeper; self.visionDistance = visionDistance; self.sharpness = sharpness
        self.faceQuality = faceQuality; self.aesthetics = aesthetics; self.exposure = exposure; self.pixelCount = pixelCount
    }
}

/// What leaves the device when a tester exports their labels: derived numbers only.
/// No images, no photo identifiers (IDs are replaced by per-export salted hashes), no dates, no locations, no filenames.
public struct EvaluationExport: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let photo: String          // salted hash of the asset id (cannot be matched to the library)
        public let group: String          // salted hash of the group id
        public let verdict: String
        public let bestShot: Bool
        public let flags: [String]
        public let hammingToKeeper: Int?
        public let visionDistance: Double?
        public let sharpness: Double?, faceQuality: Double?, aesthetics: Double?, exposure: Double?
        public let pixelCount: Int64
    }
    public let schemaVersion: Int
    public let records: [Record]
    public static let currentSchemaVersion = 1

    /// A fresh random salt per export, discarded afterwards: two exports of the same photo can't be linked.
    public static func make(from labels: [RawLabel], salt: Data = Data((0..<16).map { _ in UInt8.random(in: 0...255) })) -> EvaluationExport {
        func token(_ text: String) -> String {
            var input = salt; input.append(Data(text.utf8))
            return SHA256.hash(data: input).prefix(10).map { String(format: "%02x", $0) }.joined()
        }
        return EvaluationExport(schemaVersion: currentSchemaVersion, records: labels.map {
            Record(photo: token($0.assetID), group: token($0.groupID), verdict: $0.verdict.rawValue, bestShot: $0.isBestShot, flags: $0.flags,
                   hammingToKeeper: $0.hammingToKeeper, visionDistance: $0.visionDistance, sharpness: $0.sharpness,
                   faceQuality: $0.faceQuality, aesthetics: $0.aesthetics, exposure: $0.exposure, pixelCount: $0.pixelCount)
        })
    }
}
