import Foundation

public enum TrendDirection: String, Sendable {
    case up, down, stable
}

public struct MetricTrend: Hashable, Sendable {
    public let latest: Double
    public let average7: Double?
    public let average30: Double?
    /// Change of the 7-day average against the 30-day average, in percent.
    public let changePercent: Double?
    /// Linear regression slope over the whole window, in units per week.
    public let slopePerWeek: Double?
    public let direction: TrendDirection
}

public enum TrendEngine {
    public static func trend(_ points: [DatedValue], asOf date: Date) -> MetricTrend? {
        let sorted = points.filter { $0.date <= date }.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }

        func average(lastDays days: Double) -> Double? {
            let cutoff = date.addingTimeInterval(-days * 86_400)
            return Stats.mean(sorted.filter { $0.date > cutoff }.map(\.value))
        }

        let avg7 = average(lastDays: 7)
        let avg30 = average(lastDays: 30)

        var change: Double?
        if let avg7, let avg30, avg30 != 0 {
            change = (avg7 / avg30 - 1) * 100
        }

        let origin = sorted.first?.date ?? date
        let x = sorted.map { $0.date.timeIntervalSince(origin) / 86_400 }
        let slope = Stats.linearSlope(x: x, y: sorted.map(\.value)).map { $0 * 7 }

        let direction: TrendDirection
        if let change, abs(change) >= 3 {
            direction = change > 0 ? .up : .down
        } else {
            direction = .stable
        }

        return MetricTrend(
            latest: latest.value,
            average7: avg7,
            average30: avg30,
            changePercent: change,
            slopePerWeek: slope,
            direction: direction
        )
    }
}
