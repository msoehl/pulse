import XCTest
@testable import HealthCore

final class SleepTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testNormalizePrefersWatchStagesOverInBed() {
        let raw = [
            SleepSegment(start: at(0), end: at(480), stage: .inBed),
            SleepSegment(start: at(30), end: at(120), stage: .core),
            SleepSegment(start: at(120), end: at(180), stage: .deep),
        ]
        let result = SleepAnalyzer.normalize(raw)
        XCTAssertEqual(result.map(\.stage), [.inBed, .core, .deep, .inBed])
        XCTAssertEqual(result.first?.end, at(30))
        XCTAssertEqual(result.last?.start, at(180))
    }

    func testMainNightPicksLongestSession() {
        let raw = [
            SleepSegment(start: at(0), end: at(40), stage: .asleepUnspecified),       // nap
            SleepSegment(start: at(600), end: at(1050), stage: .core),                // night
        ]
        let night = SleepAnalyzer.mainNight(from: raw)
        XCTAssertEqual(night?.asleep, 450 * 60)
    }

    func testEfficiencyCountsGapsAsAwake() {
        let night = SleepNight(segments: [
            SleepSegment(start: at(0), end: at(200), stage: .core),
            SleepSegment(start: at(250), end: at(450), stage: .rem),
        ])
        XCTAssertEqual(night.timeInBed, 450 * 60)
        XCTAssertEqual(night.asleep, 400 * 60)
        XCTAssertEqual(night.efficiency, 400.0 / 450.0, accuracy: 1e-9)
    }

    func testSleepNeedGrowsWithStrainAndDebt() {
        let profile = UserProfile(sleepNeedHours: 8)
        let rested = SleepEngine.need(profile: profile, previousDayStrain: 5, previousNights: [])
        XCTAssertEqual(rested.total, 8 * 3600)

        let short = SleepNight(segments: [SleepSegment(start: at(0), end: at(300), stage: .core)])
        let tired = SleepEngine.need(profile: profile, previousDayStrain: 18, previousNights: [short, short, short])
        XCTAssertGreaterThan(tired.strain, 0)
        XCTAssertGreaterThan(tired.debt, 0)
        XCTAssertLessThanOrEqual(tired.debt, 2 * 3600)
    }

    func testConsistencyHandlesMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.startOfDay(for: t0)
        func night(bed: Double, wake: Double) -> SleepNight {
            SleepNight(segments: [SleepSegment(start: day.addingTimeInterval(bed * 3600),
                                               end: day.addingTimeInterval(wake * 3600),
                                               stage: .core)])
        }
        // 23:30 vs 00:30 next day: one hour apart, not 23 hours.
        let score = SleepEngine.consistency(nights: [night(bed: 23.5, wake: 31), night(bed: 24.5, wake: 31)], calendar: calendar)
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score ?? 0, 50)
    }
}

final class StrainTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func samples(bpm: Double, minutes: Int) -> [HeartRateSample] {
        (0..<minutes).map { HeartRateSample(date: t0.addingTimeInterval(Double($0) * 60), bpm: bpm) }
    }

    func testRestingHeartRateProducesNoStrain() {
        let result = StrainEngine.trimp(samples: samples(bpm: 60, minutes: 600), restingHR: 55, maxHR: 190, sex: .male)
        XCTAssertEqual(result.trimp, 0)
        XCTAssertEqual(result.zoneMinutes.reduce(0, +), 0)
    }

    func testHarderEffortGivesMoreStrain() {
        let easy = StrainEngine.trimp(samples: samples(bpm: 130, minutes: 60), restingHR: 55, maxHR: 190, sex: .male)
        let hard = StrainEngine.trimp(samples: samples(bpm: 170, minutes: 60), restingHR: 55, maxHR: 190, sex: .male)
        XCTAssertGreaterThan(hard.trimp, easy.trimp)
        XCTAssertGreaterThan(hard.zoneMinutes[3] + hard.zoneMinutes[4], 0)
    }

    func testStrainIsBounded() {
        XCTAssertEqual(StrainEngine.strain(fromTrimp: 0), 0)
        XCTAssertLessThan(StrainEngine.strain(fromTrimp: 10_000), 21.0001)
        XCTAssertLessThan(StrainEngine.strain(fromTrimp: 50), StrainEngine.strain(fromTrimp: 150))
    }

    func testGapsAreCapped() {
        let sparse = [
            HeartRateSample(date: t0, bpm: 160),
            HeartRateSample(date: t0.addingTimeInterval(3 * 3600), bpm: 160),
        ]
        let result = StrainEngine.trimp(samples: sparse, restingHR: 55, maxHR: 190, sex: .male)
        // At most 10 min + 1 min counted, not three hours.
        XCTAssertLessThanOrEqual(result.zoneMinutes.reduce(0, +), 11.0001)
    }

    func testTrainingLoadConverges() {
        let start = t0
        let daily = (0..<200).map { DatedValue(date: start.addingTimeInterval(Double($0) * 86_400), value: 100) }
        let points = TrainingLoadEngine.compute(daily: daily)
        XCTAssertEqual(points.last?.acute ?? 0, 100, accuracy: 0.5)
        XCTAssertEqual(points.last?.chronic ?? 0, 100, accuracy: 2)
        XCTAssertEqual(points.last?.ratio ?? 0, 1, accuracy: 0.03)
    }
}

final class RecoveryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func history(count: Int) -> [DayMetrics] {
        (0..<count).map { (i: Int) -> DayMetrics in
            let date = t0.addingTimeInterval(Double(i) * 86_400)
            let hrv: Double = 58 + Double(i % 5)
            let restingHR: Double = 51 + Double(i % 3)
            let respiratoryRate: Double = 14 + 0.4 * Double(i % 2)
            return DayMetrics(date: date, hrv: hrv, restingHR: restingHR, respiratoryRate: respiratoryRate)
        }
    }

    func testCalibrationNeedsHistory() {
        let today = DayMetrics(date: t0, hrv: 60, restingHR: 52)
        XCTAssertNil(RecoveryEngine.compute(today: today, history: history(count: 2), sleepPerformance: 1))
        XCTAssertNotNil(RecoveryEngine.compute(today: today, history: history(count: 10), sleepPerformance: 1))
    }

    func testHigherHRVMeansBetterRecovery() {
        let base = history(count: 30)
        let good = RecoveryEngine.compute(today: DayMetrics(date: t0, hrv: 75, restingHR: 50, respiratoryRate: 14), history: base, sleepPerformance: 1)
        let bad = RecoveryEngine.compute(today: DayMetrics(date: t0, hrv: 40, restingHR: 60, respiratoryRate: 16), history: base, sleepPerformance: 0.6)
        XCTAssertNotNil(good)
        XCTAssertNotNil(bad)
        XCTAssertGreaterThan(good!.score, bad!.score)
        XCTAssertEqual(good!.zone, .green)
        XCTAssertEqual(bad!.zone, .red)
        XCTAssertTrue(bad!.flags.contains(.elevatedRespiration))
    }

    func testAnalyzerProducesReportPerDay() {
        let days = history(count: 20)
        let reports = HealthAnalyzer.analyze(days: days, profile: UserProfile())
        XCTAssertEqual(reports.count, 20)
        XCTAssertNil(reports.first?.recovery)
        XCTAssertNotNil(reports.last?.recovery)
    }
}

final class TrendTests: XCTestCase {
    func testRisingSeriesTrendsUp() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<60).map { (i: Int) -> DatedValue in
            let value: Double = 40 + 0.5 * Double(i)
            return DatedValue(date: t0.addingTimeInterval(Double(i) * 86_400), value: value)
        }
        let trend = TrendEngine.trend(points, asOf: points.last!.date)
        XCTAssertEqual(trend?.direction, .up)
        XCTAssertEqual(trend?.slopePerWeek ?? 0, 3.5, accuracy: 0.01)
    }
}
