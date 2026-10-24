import Foundation

public struct DayReport: Identifiable, Hashable, Sendable {
    public let metrics: DayMetrics
    public let recovery: RecoveryResult?
    public let sleep: SleepAnalysis?
    /// 0–21.
    public let strain: Double?
    public let load: LoadPoint?

    public var id: Date { metrics.date }
}

public enum HealthAnalyzer {
    /// Turns contiguous daily metrics into reports. Days must be one entry per calendar day.
    public static func analyze(days input: [DayMetrics], profile: UserProfile, calendar: Calendar = .current) -> [DayReport] {
        let days = input.sorted { $0.date < $1.date }
        let loads = TrainingLoadEngine.compute(daily: days.map { DatedValue(date: $0.date, value: $0.trimp ?? 0) })

        var reports: [DayReport] = []
        reports.reserveCapacity(days.count)

        for (i, day) in days.enumerated() {
            let history = Array(days[max(0, i - RecoveryEngine.baselineDays)..<i])
            // Last night's need depends on the strain of the previous day.
            let previousStrain = i > 0 ? days[i - 1].trimp.map(StrainEngine.strain(fromTrimp:)) : nil
            let previousNights: [SleepNight?] = (1...3).map { i - $0 >= 0 ? days[i - $0].sleep : nil }
            let consistencyNights = days[max(0, i - 3)...i].compactMap(\.sleep)

            let sleep = day.sleep.map {
                SleepEngine.analyze(
                    night: $0,
                    profile: profile,
                    previousDayStrain: previousStrain,
                    previousNights: previousNights,
                    consistencyNights: consistencyNights,
                    calendar: calendar
                )
            }
            let recovery = RecoveryEngine.compute(today: day, history: history, sleepPerformance: sleep?.performance)

            reports.append(DayReport(
                metrics: day,
                recovery: recovery,
                sleep: sleep,
                strain: day.trimp.map(StrainEngine.strain(fromTrimp:)),
                load: loads[i]
            ))
        }
        return reports
    }
}
