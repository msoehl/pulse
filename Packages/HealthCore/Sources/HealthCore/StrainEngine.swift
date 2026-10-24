import Foundation

public struct HeartRateSample: Hashable, Sendable {
    public let date: Date
    public let bpm: Double

    public init(date: Date, bpm: Double) {
        self.date = date
        self.bpm = bpm
    }
}

public struct TrimpResult: Codable, Hashable, Sendable {
    public let trimp: Double
    public let zoneMinutes: [Double]

    public init(trimp: Double, zoneMinutes: [Double]) {
        self.trimp = trimp
        self.zoneMinutes = zoneMinutes
    }
}

public enum StrainEngine {
    /// Samples further apart than this are treated as a data gap (watch off, etc.).
    public static let maxSampleGap: TimeInterval = 600
    /// Heart rate reserve below this fraction does not count as strain.
    public static let activityThreshold = 0.3
    /// TRIMP at which strain reaches ~63 % of the 21-point scale.
    public static let strainScale = 120.0

    /// Zone index 0–4 for a heart-rate-reserve fraction (50/60/70/80/90 %), nil below zone 1.
    public static func zone(forHRR hrr: Double) -> Int? {
        switch hrr {
        case ..<0.5: return nil
        case ..<0.6: return 0
        case ..<0.7: return 1
        case ..<0.8: return 2
        case ..<0.9: return 3
        default: return 4
        }
    }

    /// Banister TRIMP: minutes × HRR × a·e^(b·HRR), summed over all samples.
    public static func trimp(samples: [HeartRateSample], restingHR: Double, maxHR: Double, sex: BiologicalSex) -> TrimpResult {
        var zones = [Double](repeating: 0, count: 5)
        guard maxHR > restingHR + 10, !samples.isEmpty else { return TrimpResult(trimp: 0, zoneMinutes: zones) }

        let a: Double
        let b: Double
        switch sex {
        case .male: a = 0.64; b = 1.92
        case .female: a = 0.86; b = 1.67
        case .unknown: a = 0.75; b = 1.8
        }

        let sorted = samples.sorted { $0.date < $1.date }
        var total = 0.0
        for (i, sample) in sorted.enumerated() {
            let dt: TimeInterval = i + 1 < sorted.count
                ? min(sorted[i + 1].date.timeIntervalSince(sample.date), maxSampleGap)
                : 60
            guard dt > 0 else { continue }

            let minutes = dt / 60
            let hrr = (sample.bpm - restingHR) / (maxHR - restingHR)
            if let z = zone(forHRR: hrr) { zones[z] += minutes }
            guard hrr >= activityThreshold else { continue }

            let h = min(hrr, 1)
            total += minutes * h * a * exp(b * h)
        }
        return TrimpResult(trimp: total, zoneMinutes: zones)
    }

    /// Maps TRIMP onto a 0–21 scale with diminishing returns.
    public static func strain(fromTrimp trimp: Double) -> Double {
        21 * (1 - exp(-max(trimp, 0) / strainScale))
    }

    /// Suggested strain target for the day depending on recovery.
    public static func recommendedRange(for zone: RecoveryZone) -> ClosedRange<Double> {
        switch zone {
        case .green: return 14...18
        case .yellow: return 10...14
        case .red: return 4...10
        }
    }
}

public struct LoadPoint: Hashable, Sendable {
    public let date: Date
    /// 7-day exponentially weighted load (fatigue).
    public let acute: Double
    /// 42-day exponentially weighted load (fitness).
    public let chronic: Double

    /// Acute:chronic workload ratio; 0.8–1.3 is the usual "sweet spot".
    public var ratio: Double? { chronic >= 1 ? acute / chronic : nil }
    public var form: Double { chronic - acute }
}

public enum TrainingLoadEngine {
    public static func compute(daily: [DatedValue], acuteDays: Double = 7, chronicDays: Double = 42) -> [LoadPoint] {
        let acuteFactor = 1 - exp(-1 / acuteDays)
        let chronicFactor = 1 - exp(-1 / chronicDays)
        var acute = 0.0
        var chronic = 0.0
        return daily.sorted { $0.date < $1.date }.map { day in
            acute += (day.value - acute) * acuteFactor
            chronic += (day.value - chronic) * chronicFactor
            return LoadPoint(date: day.date, acute: acute, chronic: chronic)
        }
    }
}
