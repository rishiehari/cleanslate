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
    /// The weights of the display-only best-shot score. `v1` is hand-set; a fitted set ships only if it beats v1
    /// on held-out human labels by at least 5 points of top-1 agreement (see docs/ML_GATE.md).
    public struct Weights: Sendable, Equatable, Codable {
        public var sharpness, face, aesthetics, exposure, pixels, favorite: Double
        public init(sharpness: Double, face: Double, aesthetics: Double, exposure: Double, pixels: Double, favorite: Double) {
            self.sharpness = sharpness; self.face = face; self.aesthetics = aesthetics
            self.exposure = exposure; self.pixels = pixels; self.favorite = favorite
        }
        public static let v1 = Weights(sharpness: 0.26, face: 0.27, aesthetics: 0.18, exposure: 0.09, pixels: 0.10, favorite: 0.10)
    }

    /// Ranking is only for display. Never prove equivalence or authorize deletion with this score.
    /// Missing values get neutral scores, not fabricated confidence.
    public static func sorted(_ signals: [QualitySignals], weights: Weights = .v1) -> [QualitySignals] {
        signals.sorted { a, b in
            let sa = score(a, weights: weights), sb = score(b, weights: weights)
            return sa == sb ? a.id < b.id : sa > sb
        }
    }

    /// The normalized features the score is built from (each 0...1, missing = 0.5).
    public static func features(_ s: QualitySignals) -> [Double] {
        func clamped(_ v: Double?) -> Double { min(1, max(0, v ?? 0.5)) }
        let pixels = min(1, log2(Double(max(1, s.pixelCount))) / 26.0)
        return [clamped(s.sharpness), clamped(s.faceQuality), clamped(s.aesthetics), clamped(s.exposure), pixels, s.isFavorite ? 1 : 0]
    }

    public static func score(_ s: QualitySignals, weights: Weights = .v1) -> Double {
        let f = features(s)
        return weights.sharpness * f[0] + weights.face * f[1] + weights.aesthetics * f[2]
             + weights.exposure * f[3] + weights.pixels * f[4] + weights.favorite * f[5]
    }
}

/// Fits ranker weights from human "best shot" labels with pairwise logistic regression (no dependencies).
public enum RankerFitter {
    public struct LabeledGroup: Sendable {
        public let photos: [QualitySignals]
        public let bestID: String
        public init(photos: [QualitySignals], bestID: String) { self.photos = photos; self.bestID = bestID }
    }

    /// Fraction of groups where the top-ranked photo is the human's pick.
    public static func top1Agreement(_ groups: [LabeledGroup], weights: KeeperRanker.Weights) -> Double {
        let usable = groups.filter { group in group.photos.count >= 2 && group.photos.contains { $0.id == group.bestID } }
        guard !usable.isEmpty else { return 0 }
        let hits = usable.filter { KeeperRanker.sorted($0.photos, weights: weights).first?.id == $0.bestID }.count
        return Double(hits) / Double(usable.count)
    }

    public static func fit(_ groups: [LabeledGroup], epochs: Int = 400, learningRate: Double = 0.5, l2: Double = 0.001) -> KeeperRanker.Weights {
        // Each pair (best, other) gives a feature difference d with target 1 (and -d with target 0).
        var pairs: [[Double]] = []
        for group in groups {
            guard let best = group.photos.first(where: { $0.id == group.bestID }) else { continue }
            let fb = KeeperRanker.features(best)
            for other in group.photos where other.id != best.id {
                pairs.append(zip(fb, KeeperRanker.features(other)).map { $0 - $1 })
            }
        }
        guard !pairs.isEmpty else { return .v1 }
        var w = [Double](repeating: 0, count: 6)
        for _ in 0..<epochs {
            var gradient = [Double](repeating: 0, count: 6)
            for d in pairs {
                let z = zip(w, d).map(*).reduce(0, +)
                let p = 1 / (1 + exp(-z))                    // P(best ranks above other)
                for i in 0..<6 { gradient[i] += (1 - p) * d[i] }
            }
            for i in 0..<6 { w[i] += learningRate * (gradient[i] / Double(pairs.count) - l2 * w[i]) }
        }
        // Scores only need a consistent ORDER; scale so the weights sum like v1 (readable and comparable).
        let negatives = w.map { max(0, $0) }
        let total = negatives.reduce(0, +)
        guard total > 0 else { return .v1 }
        let scale = 1.0 / total
        return KeeperRanker.Weights(sharpness: negatives[0] * scale, face: negatives[1] * scale, aesthetics: negatives[2] * scale,
                                    exposure: negatives[3] * scale, pixels: negatives[4] * scale, favorite: negatives[5] * scale)
    }
}
