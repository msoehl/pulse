import Foundation

public enum RecoveryZone: String, Sendable {
    case green, yellow, red

    public init(score: Int) {
        switch score {
        case 67...: self = .green
        case 34..<67: self = .yellow
        default: self = .red
        }
    }
}

public enum RecoveryFactor: String, Sendable {
    case hrv, restingHR, sleep, respiratoryRate
}

public enum RecoveryFlag: String, Sendable {
    case elevatedTemperature, lowOxygen, elevatedRespiration
}

public struct RecoveryComponent: Hashable, Sendable {
    public let factor: RecoveryFactor
    public let value: Double
    public let baseline: Double?
    /// Positive means "better than usual", regardless of the metric's direction.
    public let contribution: Double
    public let weight: Double
}

public struct RecoveryResult: Hashable, Sendable {
    public let score: Int
    public let zone: RecoveryZone
    public let components: [RecoveryComponent]
    public let flags: [RecoveryFlag]

    public func component(_ factor: RecoveryFactor) -> RecoveryComponent? {
        components.first { $0.factor == factor }
    }
}

public enum RecoveryEngine {
    public static let baselineDays = 30
    public static let minimumBaselineNights = 4

    /// Recovery from overnight HRV, resting heart rate, sleep and respiratory rate,
    /// each compared with the personal baseline of the previous 30 days.
    /// Returns nil while there is no HRV or not enough history (calibration).
    public static func compute(today: DayMetrics, history: [DayMetrics], sleepPerformance: Double?) -> RecoveryResult? {
        guard let hrv = today.hrv, hrv > 0 else { return nil }
        let recent = Array(history.suffix(baselineDays))

        // HRV is roughly log-normal, so the baseline is built on ln(HRV).
        let hrvHistory = recent.compactMap(\.hrv).filter { $0 > 0 }.map { log($0) }
        guard let hrvBaseline = Stats.baseline(hrvHistory, minimumCount: minimumBaselineNights) else { return nil }

        var components: [RecoveryComponent] = []
        components.append(RecoveryComponent(
            factor: .hrv,
            value: hrv,
            baseline: exp(hrvBaseline.mean),
            contribution: Stats.clamp(Stats.zScore(log(hrv), baseline: hrvBaseline), -3, 3),
            weight: 0.45
        ))

        if let rhr = today.restingHR,
           let base = Stats.baseline(recent.compactMap(\.restingHR), minimumCount: minimumBaselineNights) {
            components.append(RecoveryComponent(
                factor: .restingHR,
                value: rhr,
                baseline: base.mean,
                contribution: Stats.clamp(-Stats.zScore(rhr, baseline: base), -3, 3),
                weight: 0.25
            ))
        }

        if let performance = sleepPerformance {
            components.append(RecoveryComponent(
                factor: .sleep,
                value: performance,
                baseline: 0.85,
                contribution: Stats.clamp((performance - 0.85) / 0.1, -3, 1.5),
                weight: 0.2
            ))
        }

        var respiratoryZ: Double?
        if let resp = today.respiratoryRate,
           let base = Stats.baseline(recent.compactMap(\.respiratoryRate), minimumCount: minimumBaselineNights) {
            let z = Stats.zScore(resp, baseline: base)
            respiratoryZ = z
            components.append(RecoveryComponent(
                factor: .respiratoryRate,
                value: resp,
                baseline: base.mean,
                contribution: Stats.clamp(-z, -3, 3),
                weight: 0.1
            ))
        }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let composite = components.reduce(0) { $0 + $1.contribution * $1.weight } / totalWeight

        // Logistic mapping: an average day lands around 57 %.
        let raw = 100 / (1 + exp(-1.2 * (composite + 0.2)))
        let score = Stats.clamp(Int(raw.rounded()), 1, 99)

        var flags: [RecoveryFlag] = []
        if let temp = today.wristTemperature,
           let base = Stats.mean(recent.compactMap(\.wristTemperature)),
           temp - base >= 0.5 {
            flags.append(.elevatedTemperature)
        }
        if let spo2 = today.oxygenSaturation, spo2 < 94 {
            flags.append(.lowOxygen)
        }
        if let z = respiratoryZ, z >= 2 {
            flags.append(.elevatedRespiration)
        }

        return RecoveryResult(score: score, zone: RecoveryZone(score: score), components: components, flags: flags)
    }
}
