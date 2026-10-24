import Foundation
import HealthKit
import HealthCore

enum HealthDataError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health ist auf diesem Gerät nicht verfügbar."
        }
    }
}

struct WorkoutSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let end: Date
    let energy: Double?
    let averageHR: Double?

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Reads everything the app needs from HealthKit and turns it into `DayMetrics`.
final class HealthKitService {
    private let store = HKHealthStore()
    private let calendar: Calendar

    private let bpm = HKUnit.count().unitDivided(by: .minute())

    private static let readQuantities: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate,
        .oxygenSaturation, .vo2Max, .bodyMass, .stepCount, .activeEnergyBurned,
        .appleSleepingWristTemperature,
    ]

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthDataError.unavailable }
        var read: Set<HKObjectType> = Set(Self.readQuantities.map { HKQuantityType($0) })
        read.insert(HKCategoryType(.sleepAnalysis))
        read.insert(HKObjectType.workoutType())
        read.insert(HKCharacteristicType(.dateOfBirth))
        read.insert(HKCharacteristicType(.biologicalSex))
        try await store.requestAuthorization(toShare: [], read: read)
    }

    func characteristics() -> (age: Int?, sex: BiologicalSex) {
        var age: Int?
        if let components = try? store.dateOfBirthComponents(),
           let birth = calendar.date(from: components) {
            age = calendar.dateComponents([.year], from: birth, to: Date()).year
        }
        var sex = BiologicalSex.unknown
        if let value = try? store.biologicalSex().biologicalSex {
            switch value {
            case .male: sex = .male
            case .female: sex = .female
            default: break
            }
        }
        return (age, sex)
    }

    // MARK: - Days

    func loadDays(count: Int, profile: UserProfile, cache: TrimpCache) async -> [DayMetrics] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today),
              let sleepStart = calendar.date(byAdding: .hour, value: -12, to: start) else { return [] }

        async let restingHR = dailyStatistics(.restingHeartRate, unit: bpm, options: .discreteAverage, start: start, end: now)
        async let respiratory = dailyStatistics(.respiratoryRate, unit: bpm, options: .discreteAverage, start: start, end: now)
        async let oxygen = dailyStatistics(.oxygenSaturation, unit: .percent(), options: .discreteAverage, start: start, end: now)
        async let wristTemp = dailyStatistics(.appleSleepingWristTemperature, unit: .degreeCelsius(), options: .discreteAverage, start: start, end: now)
        async let vo2 = dailyStatistics(.vo2Max, unit: HKUnit(from: "ml/kg*min"), options: .discreteAverage, start: start, end: now)
        async let mass = dailyStatistics(.bodyMass, unit: .gramUnit(with: .kilo), options: .discreteAverage, start: start, end: now)
        async let steps = dailyStatistics(.stepCount, unit: .count(), options: .cumulativeSum, start: start, end: now)
        async let energy = dailyStatistics(.activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, start: start, end: now)
        async let hrvSamples = quantitySamples(.heartRateVariabilitySDNN, start: sleepStart, end: now)
        async let sleepSamples = sleepSegments(start: sleepStart, end: now)

        let rhrByDay = await restingHR
        let respByDay = await respiratory
        let spo2ByDay = await oxygen
        let tempByDay = await wristTemp
        let vo2ByDay = await vo2
        let massByDay = await mass
        let stepsByDay = await steps
        let energyByDay = await energy
        let ms = HKUnit.secondUnit(with: .milli)
        let hrv = await hrvSamples.map { DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: ms)) }
        let segments = await sleepSamples

        var segmentsByDay: [Date: [SleepSegment]] = [:]
        for segment in segments {
            segmentsByDay[DayAssembly.nightDay(forEnd: segment.end, calendar: calendar), default: []].append(segment)
        }

        let fallbackRHR = Stats.median(Array(rhrByDay.values)) ?? 60
        cache.prepare(signature: "v1-\(Int(profile.maxHR))-\(profile.sex.rawValue)")

        var result: [DayMetrics] = []
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }

            var metrics = DayMetrics(date: day)
            metrics.restingHR = rhrByDay[day]
            metrics.respiratoryRate = respByDay[day]
            metrics.oxygenSaturation = spo2ByDay[day].map { $0 * 100 }
            metrics.wristTemperature = tempByDay[day]
            metrics.vo2Max = vo2ByDay[day]
            metrics.bodyMass = massByDay[day]
            metrics.steps = stepsByDay[day]
            metrics.activeEnergy = energyByDay[day]
            metrics.sleep = segmentsByDay[day].flatMap(SleepAnalyzer.mainNight(from:))
            metrics.hrv = DayAssembly.overnightMean(hrv, night: metrics.sleep, dayStart: day, dayEnd: next)

            let key = Self.dayKeyFormatter.string(from: day)
            let isToday = day == today
            if !isToday, let cached = cache.value(for: key) {
                metrics.trimp = cached.trimp
                metrics.zoneMinutes = cached.zoneMinutes
            } else {
                let samples = await quantitySamples(.heartRate, start: day, end: next)
                if !samples.isEmpty {
                    let hr = samples.map { HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: bpm)) }
                    let trimp = StrainEngine.trimp(samples: hr,
                                                   restingHR: metrics.restingHR ?? fallbackRHR,
                                                   maxHR: profile.maxHR,
                                                   sex: profile.sex)
                    metrics.trimp = trimp.trimp
                    metrics.zoneMinutes = trimp.zoneMinutes
                    if !isToday { cache.set(trimp, for: key) }
                }
            }
            result.append(metrics)
        }
        cache.save()
        return result
    }

    func workouts(since start: Date) async -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        return workouts.map { workout in
            let (name, symbol) = Self.describe(workout.workoutActivityType)
            return WorkoutSummary(
                id: workout.uuid,
                name: name,
                symbol: symbol,
                start: workout.startDate,
                end: workout.endDate,
                energy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                averageHR: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm)
            )
        }
    }

    // MARK: - Queries

    private func dailyStatistics(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        start: Date,
        end: Date
    ) async -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: options,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }

        var values: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let quantity = options.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                values[self.calendar.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return values
    }

    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, start: Date, end: Date) async -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func sleepSegments(start: Date, end: Date) async -> [SleepSegment] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            default: stage = .asleepUnspecified
            }
            return SleepSegment(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    private static func describe(_ type: HKWorkoutActivityType) -> (String, String) {
        switch type {
        case .running: return ("Laufen", "figure.run")
        case .walking: return ("Gehen", "figure.walk")
        case .hiking: return ("Wandern", "figure.hiking")
        case .cycling: return ("Radfahren", "figure.outdoor.cycle")
        case .swimming: return ("Schwimmen", "figure.pool.swim")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return ("Krafttraining", "figure.strengthtraining.traditional")
        case .highIntensityIntervalTraining: return ("HIIT", "figure.highintensity.intervaltraining")
        case .yoga: return ("Yoga", "figure.yoga")
        case .rowing: return ("Rudern", "figure.rower")
        case .elliptical: return ("Crosstrainer", "figure.elliptical")
        case .soccer: return ("Fußball", "figure.soccer")
        case .tennis: return ("Tennis", "figure.tennis")
        case .coreTraining: return ("Core", "figure.core.training")
        case .crossTraining: return ("Cross-Training", "figure.cross.training")
        default: return ("Training", "figure.mixed.cardio")
        }
    }
}

/// Persists TRIMP for past days so heart rate samples are only read once per day.
final class TrimpCache {
    private struct Storage: Codable {
        var signature: String
        var entries: [String: TrimpResult]
    }

    private var storage: Storage
    private let url: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("trimp-cache.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Storage.self, from: data) {
            storage = decoded
        } else {
            storage = Storage(signature: "", entries: [:])
        }
    }

    /// Drops all entries when the parameters they were computed with changed.
    func prepare(signature: String) {
        if storage.signature != signature {
            storage = Storage(signature: signature, entries: [:])
        }
    }

    func value(for key: String) -> TrimpResult? { storage.entries[key] }

    func set(_ value: TrimpResult, for key: String) { storage.entries[key] = value }

    func save() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        storage = Storage(signature: "", entries: [:])
        try? FileManager.default.removeItem(at: url)
    }
}
