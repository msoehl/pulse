import Foundation

public struct BaselineStats: Hashable, Sendable {
    public let mean: Double
    public let standardDeviation: Double
    public let count: Int
}

public enum Stats {
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation.
    public static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let squares = values.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (squares / Double(values.count - 1)).squareRoot()
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    public static func baseline(_ values: [Double], minimumCount: Int = 4) -> BaselineStats? {
        guard values.count >= minimumCount,
              let m = mean(values),
              let sd = standardDeviation(values) else { return nil }
        return BaselineStats(mean: m, standardDeviation: sd, count: values.count)
    }

    /// z-score with a floor on the standard deviation so a very stable
    /// baseline does not turn tiny deviations into extreme scores.
    public static func zScore(_ value: Double, baseline: BaselineStats, minimumRelativeSD: Double = 0.03) -> Double {
        let sd = max(baseline.standardDeviation, abs(baseline.mean) * minimumRelativeSD, 1e-9)
        return (value - baseline.mean) / sd
    }

    /// Least-squares slope of y over x.
    public static func linearSlope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3, let mx = mean(x), let my = mean(y) else { return nil }
        var numerator = 0.0
        var denominator = 0.0
        for i in x.indices {
            numerator += (x[i] - mx) * (y[i] - my)
            denominator += (x[i] - mx) * (x[i] - mx)
        }
        return denominator > 0 ? numerator / denominator : nil
    }

    public static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
