import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Reads `export.xml` from the Health app's "Export All Health Data" and builds `DayMetrics`
// from it. This works without the HealthKit entitlement, which free Apple IDs cannot sign.

public enum QuantityKind: String, Codable, CaseIterable, Sendable {
    case restingHR, hrv, respiratoryRate, oxygen, vo2Max, bodyMass, steps, activeEnergy, wristTemperature
}

public struct QuantitySample: Hashable, Sendable {
    public let start: Date
    public let value: Double
    public let source: String
}

public struct ExportedWorkout: Codable, Hashable, Sendable {
    /// Activity name without the `HKWorkoutActivityType` prefix, e.g. "Running".
    public let activityType: String
    public let start: Date
    public let end: Date
    public let energy: Double?
    public let averageHR: Double?
}

public struct RawHealthData: Sendable {
    public var quantities: [QuantityKind: [QuantitySample]] = [:]
    public var heartRate: [HeartRateSample] = []
    public var sleep: [SleepSegment] = []
    public var workouts: [ExportedWorkout] = []
    public var dateOfBirth: Date?
    public var sex: BiologicalSex = .unknown
    /// All records in the file, including the ones outside the import window.
    public var recordCount = 0
}

public enum HealthExportError: LocalizedError {
    case unreadable
    case parseFailed(String)
    case noData

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Die Datei konnte nicht geöffnet werden."
        case .parseFailed(let reason): return "Der Health-Export konnte nicht gelesen werden: \(reason)"
        case .noData: return "Die Datei enthält keinen Apple-Health-Export (export.xml)."
        }
    }
}

public final class HealthExportParser: NSObject, XMLParserDelegate {
    private struct WorkoutDraft {
        var activityType: String
        var start: Date
        var end: Date
        var energy: Double?
        var averageHR: Double?
    }

    private static let quantityTypes: [String: QuantityKind] = [
        "HKQuantityTypeIdentifierRestingHeartRate": .restingHR,
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": .hrv,
        "HKQuantityTypeIdentifierRespiratoryRate": .respiratoryRate,
        "HKQuantityTypeIdentifierOxygenSaturation": .oxygen,
        "HKQuantityTypeIdentifierVO2Max": .vo2Max,
        "HKQuantityTypeIdentifierBodyMass": .bodyMass,
        "HKQuantityTypeIdentifierStepCount": .steps,
        "HKQuantityTypeIdentifierActiveEnergyBurned": .activeEnergy,
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature": .wristTemperature,
    ]

    private let cutoff: Date
    private let progress: ((Int) -> Void)?
    private var result = RawHealthData()
    private var workout: WorkoutDraft?

    /// Samples starting before `cutoff` are skipped to keep memory small.
    public init(since cutoff: Date, progress: ((Int) -> Void)? = nil) {
        self.cutoff = cutoff
        self.progress = progress
    }

    public func parse(contentsOf url: URL) throws -> RawHealthData {
        guard let stream = InputStream(url: url) else { throw HealthExportError.unreadable }
        return try run(XMLParser(stream: stream))
    }

    public func parse(data: Data) throws -> RawHealthData {
        try run(XMLParser(data: data))
    }

    private func run(_ parser: XMLParser) throws -> RawHealthData {
        result = RawHealthData()
        workout = nil
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw HealthExportError.parseFailed(parser.parserError?.localizedDescription ?? "unbekannter Fehler")
        }
        return result
    }

    // MARK: XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "Record": handleRecord(attributeDict)
        case "Workout": startWorkout(attributeDict)
        case "WorkoutStatistics": handleWorkoutStatistics(attributeDict)
        case "Me": handleMe(attributeDict)
        default: break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "Workout", let draft = workout else { return }
        result.workouts.append(ExportedWorkout(
            activityType: draft.activityType,
            start: draft.start,
            end: draft.end,
            energy: draft.energy,
            averageHR: draft.averageHR
        ))
        workout = nil
    }

    // MARK: Elements

    private func handleRecord(_ a: [String: String]) {
        result.recordCount += 1
        if result.recordCount % 100_000 == 0 { progress?(result.recordCount) }

        guard let type = a["type"] else { return }
        switch type {
        case "HKQuantityTypeIdentifierHeartRate":
            guard let start = Self.date(a["startDate"]), start >= cutoff,
                  let bpm = Self.number(a["value"]) else { return }
            result.heartRate.append(HeartRateSample(date: start, bpm: bpm))

        case "HKCategoryTypeIdentifierSleepAnalysis":
            guard let start = Self.date(a["startDate"]), let end = Self.date(a["endDate"]), end >= cutoff,
                  let stage = Self.sleepStage(a["value"]) else { return }
            result.sleep.append(SleepSegment(start: start, end: end, stage: stage))

        default:
            guard let kind = Self.quantityTypes[type],
                  let start = Self.date(a["startDate"]), start >= cutoff,
                  let value = Self.number(a["value"]) else { return }
            let normalized = Self.normalize(kind, value: value, unit: a["unit"])
            result.quantities[kind, default: []].append(QuantitySample(start: start, value: normalized, source: a["sourceName"] ?? ""))
        }
    }

    private func startWorkout(_ a: [String: String]) {
        workout = nil
        guard let start = Self.date(a["startDate"]), let end = Self.date(a["endDate"]), end >= cutoff else { return }
        let type = (a["workoutActivityType"] ?? "").replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        // Older exports carry the energy as an attribute, newer ones as WorkoutStatistics.
        let energy = Self.number(a["totalEnergyBurned"]).map {
            Self.normalize(.activeEnergy, value: $0, unit: a["totalEnergyBurnedUnit"])
        }
        workout = WorkoutDraft(activityType: type, start: start, end: end, energy: energy, averageHR: nil)
    }

    private func handleWorkoutStatistics(_ a: [String: String]) {
        guard workout != nil else { return }
        switch a["type"] ?? "" {
        case "HKQuantityTypeIdentifierHeartRate":
            workout?.averageHR = Self.number(a["average"])
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            if let sum = Self.number(a["sum"]) {
                workout?.energy = Self.normalize(.activeEnergy, value: sum, unit: a["unit"])
            }
        default:
            break
        }
    }

    private func handleMe(_ a: [String: String]) {
        if let birth = a["HKCharacteristicTypeIdentifierDateOfBirth"], let date = Self.date(birth + " 12:00:00 +0000") {
            result.dateOfBirth = date
        }
        switch a["HKCharacteristicTypeIdentifierBiologicalSex"] ?? "" {
        case "HKBiologicalSexMale": result.sex = .male
        case "HKBiologicalSexFemale": result.sex = .female
        default: break
        }
    }

    // MARK: Values

    private static func number(_ string: String?) -> Double? {
        string.flatMap { Double($0) }
    }

    private static func sleepStage(_ value: String?) -> SleepStage? {
        switch value ?? "" {
        case "HKCategoryValueSleepAnalysisInBed": return .inBed
        case "HKCategoryValueSleepAnalysisAwake": return .awake
        case "HKCategoryValueSleepAnalysisAsleepCore": return .core
        case "HKCategoryValueSleepAnalysisAsleepDeep": return .deep
        case "HKCategoryValueSleepAnalysisAsleepREM": return .rem
        case "HKCategoryValueSleepAnalysisAsleep", "HKCategoryValueSleepAnalysisAsleepUnspecified": return .asleepUnspecified
        default: return nil
        }
    }

    /// Converts to the units used throughout the app: kg, kcal, %, °C, ms.
    static func normalize(_ kind: QuantityKind, value: Double, unit: String?) -> Double {
        switch kind {
        case .bodyMass:
            if unit == "lb" { return value * 0.45359237 }
            if unit == "g" { return value / 1000 }
            return value
        case .activeEnergy:
            return unit == "kJ" ? value / 4.184 : value
        case .oxygen:
            return value <= 1 ? value * 100 : value
        case .wristTemperature:
            return unit == "degF" ? (value - 32) * 5 / 9 : value
        case .hrv:
            return unit == "s" ? value * 1000 : value
        default:
            return value
        }
    }

    /// Fast parser for "yyyy-MM-dd HH:mm:ss ±HHMM"; DateFormatter is too slow for millions of records.
    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let u = Array(string.utf8)
        guard u.count >= 25 else { return nil }

        func digits(_ from: Int, _ length: Int) -> Int? {
            var value = 0
            for i in from..<(from + length) {
                let digit = Int(u[i]) - 48
                guard digit >= 0 && digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        guard let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
              let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2),
              let tzHours = digits(21, 2), let tzMinutes = digits(23, 2) else { return nil }

        let sign = u[20] == UInt8(ascii: "-") ? -1 : 1
        let offset = sign * (tzHours * 3600 + tzMinutes * 60)
        let seconds = daysFromCivil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

public enum HealthExportBuilder {
    /// One `DayMetrics` per calendar day for the last `count` days up to `now`.
    public static func days(
        from raw: RawHealthData,
        count: Int,
        profile: UserProfile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayMetrics] {
        let today = calendar.startOfDay(for: now)
        guard count > 0, let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) else { return [] }

        func dailyMean(_ kind: QuantityKind) -> [Date: Double] {
            var groups: [Date: [Double]] = [:]
            for sample in raw.quantities[kind] ?? [] {
                groups[calendar.startOfDay(for: sample.start), default: []].append(sample.value)
            }
            return groups.compactMapValues(Stats.mean)
        }

        // iPhone and Watch both record steps and energy; take the source with the highest total per day.
        func dailyTotal(_ kind: QuantityKind) -> [Date: Double] {
            var totals: [Date: [String: Double]] = [:]
            for sample in raw.quantities[kind] ?? [] {
                totals[calendar.startOfDay(for: sample.start), default: [:]][sample.source, default: 0] += sample.value
            }
            return totals.compactMapValues { $0.values.max() }
        }

        let restingHR = dailyMean(.restingHR)
        let respiratory = dailyMean(.respiratoryRate)
        let oxygen = dailyMean(.oxygen)
        let temperature = dailyMean(.wristTemperature)
        let vo2 = dailyMean(.vo2Max)
        let mass = dailyMean(.bodyMass)
        let steps = dailyTotal(.steps)
        let energy = dailyTotal(.activeEnergy)
        let hrv = (raw.quantities[.hrv] ?? []).map { DatedValue(date: $0.start, value: $0.value) }

        var sleepByDay: [Date: [SleepSegment]] = [:]
        for segment in raw.sleep {
            sleepByDay[DayAssembly.nightDay(forEnd: segment.end, calendar: calendar), default: []].append(segment)
        }

        var heartRateByDay: [Date: [HeartRateSample]] = [:]
        for sample in raw.heartRate {
            heartRateByDay[calendar.startOfDay(for: sample.date), default: []].append(sample)
        }

        let fallbackRHR = Stats.median(Array(restingHR.values)) ?? 60

        var result: [DayMetrics] = []
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }

            var metrics = DayMetrics(date: day)
            metrics.restingHR = restingHR[day]
            metrics.respiratoryRate = respiratory[day]
            metrics.oxygenSaturation = oxygen[day]
            metrics.wristTemperature = temperature[day]
            metrics.vo2Max = vo2[day]
            metrics.bodyMass = mass[day]
            metrics.steps = steps[day]
            metrics.activeEnergy = energy[day]
            metrics.sleep = sleepByDay[day].flatMap(SleepAnalyzer.mainNight(from:))
            metrics.hrv = DayAssembly.overnightMean(hrv, night: metrics.sleep, dayStart: day, dayEnd: next)

            if let samples = heartRateByDay[day], !samples.isEmpty {
                let trimp = StrainEngine.trimp(samples: samples,
                                               restingHR: metrics.restingHR ?? fallbackRHR,
                                               maxHR: profile.maxHR,
                                               sex: profile.sex)
                metrics.trimp = trimp.trimp
                metrics.zoneMinutes = trimp.zoneMinutes
            }
            result.append(metrics)
        }
        return result
    }
}
