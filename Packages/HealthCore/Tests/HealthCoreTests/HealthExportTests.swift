import XCTest
@testable import HealthCore

final class HealthExportTests: XCTestCase {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE HealthData [
    <!ELEMENT HealthData (ExportDate,Me,(Record|Workout)*)>
    ]>
    <HealthData locale="de_DE">
     <ExportDate value="2026-10-21 12:00:00 +0000"/>
     <Me HKCharacteristicTypeIdentifierDateOfBirth="1990-05-01" HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexMale" HKCharacteristicTypeIdentifierBloodType="HKBloodTypeNotSet"/>
     <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" startDate="2020-01-01 10:00:00 +0000" endDate="2020-01-01 10:00:00 +0000" value="150"/>
     <Record type="HKQuantityTypeIdentifierRestingHeartRate" sourceName="Watch" unit="count/min" startDate="2026-10-20 08:00:00 +0000" endDate="2026-10-20 08:00:00 +0000" value="52"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count" startDate="2026-10-20 10:00:00 +0000" endDate="2026-10-20 10:10:00 +0000" value="1000"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Watch" unit="count" startDate="2026-10-20 10:00:00 +0000" endDate="2026-10-20 10:10:00 +0000" value="800"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Watch" unit="count" startDate="2026-10-20 15:00:00 +0000" endDate="2026-10-20 15:10:00 +0000" value="500"/>
     <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Waage" unit="lb" startDate="2026-10-20 07:00:00 +0000" endDate="2026-10-20 07:00:00 +0000" value="176.37"/>
     <Record type="HKQuantityTypeIdentifierOxygenSaturation" sourceName="Watch" unit="%" startDate="2026-10-20 03:00:00 +0000" endDate="2026-10-20 03:00:00 +0000" value="0.97"/>
     <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Watch" unit="ms" startDate="2026-10-20 02:00:00 +0000" endDate="2026-10-20 02:01:00 +0000" value="64">
      <HeartRateVariabilityMetadataList>
       <InstantaneousBeatsPerMinute bpm="55" time="2:00:01,00 AM"/>
      </HeartRateVariabilityMetadataList>
     </Record>
     <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Watch" startDate="2026-10-19 23:00:00 +0000" endDate="2026-10-20 03:00:00 +0000" value="HKCategoryValueSleepAnalysisAsleepCore"/>
     <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="30" durationUnit="min" sourceName="Watch" startDate="2026-10-20 17:00:00 +0000" endDate="2026-10-20 17:30:00 +0000">
      <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" startDate="2026-10-20 17:00:00 +0000" endDate="2026-10-20 17:30:00 +0000" average="150" minimum="100" maximum="170" unit="count/min"/>
      <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" startDate="2026-10-20 17:00:00 +0000" endDate="2026-10-20 17:30:00 +0000" sum="300" unit="kcal"/>
     </Workout>
    </HealthData>
    """

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testDateParsing() {
        XCTAssertEqual(HealthExportParser.date("1970-01-01 00:00:00 +0000")?.timeIntervalSince1970, 0)
        let local = HealthExportParser.date("2026-10-20 08:00:00 +0200")
        let zulu = HealthExportParser.date("2026-10-20 06:00:00 +0000")
        XCTAssertNotNil(local)
        XCTAssertEqual(local, zulu)
        XCTAssertNil(HealthExportParser.date("kaputt"))
    }

    func testParseAndBuild() throws {
        let cutoff = HealthExportParser.date("2026-10-15 00:00:00 +0000")!
        let raw = try HealthExportParser(since: cutoff).parse(data: Data(xml.utf8))

        XCTAssertEqual(raw.recordCount, 9)
        XCTAssertTrue(raw.heartRate.isEmpty, "old samples are skipped")
        XCTAssertEqual(raw.sex, .male)
        XCTAssertNotNil(raw.dateOfBirth)
        XCTAssertEqual(raw.workouts.count, 1)
        XCTAssertEqual(raw.workouts.first?.activityType, "Running")
        XCTAssertEqual(raw.workouts.first?.averageHR, 150)
        XCTAssertEqual(raw.workouts.first?.energy, 300)

        let now = HealthExportParser.date("2026-10-21 12:00:00 +0000")!
        let days = HealthExportBuilder.days(from: raw, count: 3, profile: UserProfile(), now: now, calendar: utc)
        XCTAssertEqual(days.count, 3)

        let day = try XCTUnwrap(days.first { $0.date == HealthExportParser.date("2026-10-20 00:00:00 +0000") })
        XCTAssertEqual(day.restingHR, 52)
        XCTAssertEqual(day.steps, 1300)
        XCTAssertEqual(day.bodyMass ?? 0, 80, accuracy: 0.01)
        XCTAssertEqual(day.oxygenSaturation ?? 0, 97, accuracy: 0.001)
        XCTAssertEqual(day.hrv, 64)
        XCTAssertEqual(day.sleep?.asleep, 4 * 3600)
    }
}
