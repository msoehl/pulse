import Foundation

public enum SleepAnalyzer {
    /// Merges overlapping samples from different sources into one timeline.
    /// For every slice of time the stage with the highest priority wins.
    public static func normalize(_ raw: [SleepSegment]) -> [SleepSegment] {
        let valid = raw.filter { $0.end > $0.start }
        guard !valid.isEmpty else { return [] }

        var bounds = Set<Date>()
        for segment in valid {
            bounds.insert(segment.start)
            bounds.insert(segment.end)
        }
        let points = bounds.sorted()

        var result: [SleepSegment] = []
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let covering = valid.filter { $0.start <= a && $0.end >= b }
            guard let best = covering.max(by: { $0.stage.priority < $1.stage.priority }) else { continue }

            if var last = result.last, last.stage == best.stage, last.end == a {
                last.end = b
                result[result.count - 1] = last
            } else {
                result.append(SleepSegment(start: a, end: b, stage: best.stage))
            }
        }
        return result
    }

    /// Splits a normalized timeline into sessions separated by gaps longer than `maxGap`.
    public static func sessions(_ segments: [SleepSegment], maxGap: TimeInterval = 2 * 3600) -> [[SleepSegment]] {
        var sessions: [[SleepSegment]] = []
        var current: [SleepSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = current.last, segment.start.timeIntervalSince(last.end) > maxGap {
                sessions.append(current)
                current = []
            }
            current.append(segment)
        }
        if !current.isEmpty { sessions.append(current) }
        return sessions
    }

    /// The longest sleep session among the samples, or nil if there is less than 30 minutes of sleep.
    public static func mainNight(from raw: [SleepSegment]) -> SleepNight? {
        let nights = sessions(normalize(raw)).map(SleepNight.init(segments:))
        guard let best = nights.max(by: { $0.asleep < $1.asleep }), best.asleep >= 30 * 60 else { return nil }
        return best
    }
}

public struct SleepNeedBreakdown: Hashable, Sendable {
    public let baseline: TimeInterval
    public let strain: TimeInterval
    public let debt: TimeInterval

    public var total: TimeInterval { baseline + strain + debt }
}

public struct SleepAnalysis: Hashable, Sendable {
    public let night: SleepNight
    public let need: SleepNeedBreakdown
    /// Hours slept relative to hours needed, capped at 1.
    public let performance: Double
    /// 0–100, how regular bed and wake times were over the last nights.
    public let consistency: Double?
    /// Combined sleep score 0–100.
    public let score: Int
}

public enum SleepEngine {
    /// Sleep need = personal baseline + extra for yesterday's strain + part of the recent sleep debt.
    /// `previousNights` is ordered most recent first.
    public static func need(profile: UserProfile, previousDayStrain: Double?, previousNights: [SleepNight?]) -> SleepNeedBreakdown {
        let baseline = profile.sleepNeedHours * 3600

        var strainExtra: TimeInterval = 0
        if let strain = previousDayStrain, strain > 10 {
            strainExtra = min((strain - 10) / 11, 1) * 45 * 60
        }

        let weights = [0.5, 0.3, 0.2]
        var debt: TimeInterval = 0
        for (index, night) in previousNights.prefix(weights.count).enumerated() {
            guard let night else { continue }
            debt += max(0, baseline - night.asleep) * weights[index]
        }
        debt = min(debt, 2 * 3600)

        return SleepNeedBreakdown(baseline: baseline, strain: strainExtra, debt: debt)
    }

    /// Regularity of bed and wake times. Needs at least two nights.
    public static func consistency(nights: [SleepNight], calendar: Calendar = .current) -> Double? {
        let starts = nights.compactMap(\.start)
        let ends = nights.compactMap(\.end)
        guard starts.count >= 2, ends.count >= 2 else { return nil }

        func minutes(_ date: Date) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        // Bedtimes are measured from noon so 23:00 and 01:00 stay close together.
        let bedtimes = starts.map { (minutes($0) + 720).truncatingRemainder(dividingBy: 1440) }
        let waketimes = ends.map(minutes)

        guard let sdBed = Stats.standardDeviation(bedtimes),
              let sdWake = Stats.standardDeviation(waketimes) else { return nil }
        let averageSD = (sdBed + sdWake) / 2
        // 0 min deviation → 100, 120 min → 0.
        return Stats.clamp(100 - averageSD * 100 / 120, 0, 100)
    }

    public static func analyze(
        night: SleepNight,
        profile: UserProfile,
        previousDayStrain: Double?,
        previousNights: [SleepNight?],
        consistencyNights: [SleepNight],
        calendar: Calendar = .current
    ) -> SleepAnalysis {
        let need = Self.need(profile: profile, previousDayStrain: previousDayStrain, previousNights: previousNights)
        let performance = need.total > 0 ? min(night.asleep / need.total, 1) : 0
        let consistency = Self.consistency(nights: consistencyNights, calendar: calendar)

        // Deep + REM around 40 % of sleep is treated as ideal.
        let restorativeShare = night.asleep > 0 ? night.restorative / night.asleep : 0
        let restorativeScore = night.hasStages ? min(restorativeShare / 0.4, 1) : 0.75
        let efficiencyScore = Stats.clamp((night.efficiency - 0.7) / 0.25, 0, 1)
        let consistencyScore = (consistency ?? 75) / 100

        let score = 0.6 * performance + 0.15 * efficiencyScore + 0.15 * consistencyScore + 0.1 * restorativeScore

        return SleepAnalysis(
            night: night,
            need: need,
            performance: performance,
            consistency: consistency,
            score: Int((score * 100).rounded())
        )
    }
}
