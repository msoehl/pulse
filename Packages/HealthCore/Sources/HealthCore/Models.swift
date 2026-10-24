import Foundation

// MARK: - Sleep

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleepUnspecified, core, deep, rem

    /// Higher priority wins when samples from several sources overlap
    /// (e.g. iPhone "in bed" vs. Apple Watch stage data).
    var priority: Int {
        switch self {
        case .deep, .rem, .core: return 5
        case .awake: return 4
        case .asleepUnspecified: return 3
        case .inBed: return 1
        }
    }

    public var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .asleepUnspecified: return true
        case .inBed, .awake: return false
        }
    }
}

public struct SleepSegment: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// One normalized sleep session: segments are sorted and do not overlap.
public struct SleepNight: Codable, Hashable, Sendable {
    public let segments: [SleepSegment]

    public init(segments: [SleepSegment]) {
        self.segments = segments.sorted { $0.start < $1.start }
    }

    public var start: Date? { segments.first?.start }
    public var end: Date? { segments.last?.end }

    public var timeInBed: TimeInterval {
        guard let start, let end else { return 0 }
        return end.timeIntervalSince(start)
    }

    public func duration(of stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    public var asleep: TimeInterval {
        segments.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.duration }
    }

    /// Everything inside the session that is not sleep, including gaps between samples.
    public var awake: TimeInterval { max(0, timeInBed - asleep) }

    public var efficiency: Double { timeInBed > 0 ? asleep / timeInBed : 0 }

    public var hasStages: Bool {
        segments.contains { $0.stage == .core || $0.stage == .deep || $0.stage == .rem }
    }

    public var restorative: TimeInterval { duration(of: .deep) + duration(of: .rem) }

    /// Number of awake phases of at least one minute.
    public var disturbances: Int {
        segments.filter { $0.stage == .awake && $0.duration >= 60 }.count
    }
}

// MARK: - Daily metrics

/// Raw per-day values as read from Apple Health. `date` is the start of the day.
/// The sleep night belongs to the day on which it ends.
public struct DayMetrics: Codable, Hashable, Identifiable, Sendable {
    public var date: Date
    /// Overnight HRV (SDNN) in ms.
    public var hrv: Double?
    public var restingHR: Double?
    public var respiratoryRate: Double?
    /// Blood oxygen in percent (0–100).
    public var oxygenSaturation: Double?
    /// Sleeping wrist temperature in °C.
    public var wristTemperature: Double?
    public var vo2Max: Double?
    public var bodyMass: Double?
    public var steps: Double?
    public var activeEnergy: Double?
    public var sleep: SleepNight?
    /// Banister TRIMP of the whole day, computed from heart rate samples.
    public var trimp: Double?
    /// Minutes in heart rate zones 1–5 (Karvonen / heart rate reserve).
    public var zoneMinutes: [Double]?

    public var id: Date { date }

    public init(
        date: Date,
        hrv: Double? = nil,
        restingHR: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        wristTemperature: Double? = nil,
        vo2Max: Double? = nil,
        bodyMass: Double? = nil,
        steps: Double? = nil,
        activeEnergy: Double? = nil,
        sleep: SleepNight? = nil,
        trimp: Double? = nil,
        zoneMinutes: [Double]? = nil
    ) {
        self.date = date
        self.hrv = hrv
        self.restingHR = restingHR
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.wristTemperature = wristTemperature
        self.vo2Max = vo2Max
        self.bodyMass = bodyMass
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.sleep = sleep
        self.trimp = trimp
        self.zoneMinutes = zoneMinutes
    }
}

// MARK: - Profile

public enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case male, female, unknown
}

public struct UserProfile: Codable, Hashable, Sendable {
    public var age: Int?
    public var sex: BiologicalSex
    public var maxHROverride: Double?
    public var sleepNeedHours: Double

    public init(age: Int? = nil, sex: BiologicalSex = .unknown, maxHROverride: Double? = nil, sleepNeedHours: Double = 8) {
        self.age = age
        self.sex = sex
        self.maxHROverride = maxHROverride
        self.sleepNeedHours = sleepNeedHours
    }

    /// Tanaka formula (208 − 0.7 × age) unless overridden.
    public var maxHR: Double {
        if let maxHROverride { return maxHROverride }
        if let age { return 208 - 0.7 * Double(age) }
        return 190
    }
}

public struct DatedValue: Hashable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}
