import Foundation

public enum SafetyStatistics {
    /// Exact one-sided Clopper-Pearson upper bound: Pr(X <= failures | p=upper) = alpha.
    /// Numerically targeted to small observed failures (the relevant safety gate).
    public static func oneSidedUpperBound(failures: Int, trials: Int,
                                          confidence: Double = 0.95) -> Double? {
        guard trials > 0, failures >= 0, failures <= trials,
              confidence > 0, confidence < 1 else { return nil }
        if failures == trials { return 1 }
        let alpha = 1 - confidence
        if failures == 0 { return 1 - pow(alpha, 1.0 / Double(trials)) }
        var low = 0.0
        var high = 1.0
        for _ in 0..<75 {
            let mid = (low + high) / 2
            if binomialCDF(failures, trials, mid) > alpha { low = mid }
            else { high = mid }
        }
        return high
    }

    private static func binomialCDF(_ k: Int, _ n: Int, _ p: Double) -> Double {
        if p <= 0 { return 1 }
        if p >= 1 { return k == n ? 1 : 0 }
        var probability = exp(Double(n) * log1p(-p))
        var sum = probability
        if k == 0 { return min(1, sum) }
        for j in 1...k {
            probability *= Double(n - j + 1) / Double(j) * p / (1 - p)
            sum += probability
        }
        return min(1, max(0, sum))
    }
}
