import Foundation

public struct QualitySignals: Sendable, Equatable {
    public let id: String
    public let sharpness: Double? // normalized 0...1
    public let faceQuality: Double? // normalized 0...1
    public let aesthetics: Double? // normalized 0...1
    public let exposure: Double? // normalized 0...1
    public let pixelCount: Int64
    public let isFavorite: Bool
    public init(id: String, sharpness: Double? = nil, faceQuality: Double? = nil,
                aesthetics: Double? = nil, exposure: Double? = nil,
                pixelCount: Int64, isFavorite: Bool = false) {
        self.id = id; self.sharpness = sharpness; self.faceQuality = faceQuality
        self.aesthetics = aesthetics; self.exposure = exposure
        self.pixelCount = pixelCount; self.isFavorite = isFavorite
    }
}

public enum KeeperRanker {
    /// Ranking is only for display. Never prove equivalence or authorize deletion with this score.
    /// Missing values get neutral scores, not fabricated confidence.
    public static func sorted(_ signals: [QualitySignals]) -> [QualitySignals] {
        signals.sorted { a,b in
            let sa = score(a), sb = score(b)
            return sa == sb ? a.id < b.id : sa > sb
        }
    }
    public static func score(_ s: QualitySignals) -> Double {
        func clamped(_ v: Double?) -> Double { min(1, max(0, v ?? 0.5)) }
        let pixels = min(1, log2(Double(max(1, s.pixelCount))) / 26.0)
        return 0.26 * clamped(s.sharpness)
             + 0.27 * clamped(s.faceQuality)
             + 0.18 * clamped(s.aesthetics)
             + 0.09 * clamped(s.exposure)
             + 0.10 * pixels
             + (s.isFavorite ? 0.10 : 0.0)
    }
}
