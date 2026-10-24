import Foundation

/// Rules shared by every data source when raw samples are turned into `DayMetrics`.
public enum DayAssembly {
    /// A night belongs to the day it ends on; anything ending after 15:00 counts towards the next day.
    public static func nightDay(forEnd end: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: end.addingTimeInterval(9 * 3600))
    }

    /// Mean of the readings taken during the main sleep, falling back to all readings of the day.
    public static func overnightMean(_ samples: [DatedValue], night: SleepNight?, dayStart: Date, dayEnd: Date) -> Double? {
        if let start = night?.start, let end = night?.end {
            let values = samples.filter { $0.date >= start && $0.date <= end }.map(\.value)
            if let mean = Stats.mean(values) { return mean }
        }
        let values = samples.filter { $0.date >= dayStart && $0.date < dayEnd }.map(\.value)
        return Stats.mean(values)
    }
}
