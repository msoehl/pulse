import XCTest
@testable import HealthCore

final class ShortcutPayloadTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testNumbers() {
        XCTAssertEqual(ShortcutPayload.number("64", allowGrouping: false), 64)
        XCTAssertEqual(ShortcutPayload.number("64,5", allowGrouping: false), 64.5)
        XCTAssertEqual(ShortcutPayload.number("0.97", allowGrouping: false), 0.97)
        XCTAssertEqual(ShortcutPayload.number("12.345", allowGrouping: true), 12_345)
        XCTAssertEqual(ShortcutPayload.number("12,345", allowGrouping: true), 12_345)
        XCTAssertEqual(ShortcutPayload.number("36.123", allowGrouping: false), 36.123)
        XCTAssertEqual(ShortcutPayload.number("52 count/min", allowGrouping: false), 52)
        XCTAssertNil(ShortcutPayload.number("abc", allowGrouping: false))
    }

    func testDatesAndStages() {
        XCTAssertEqual(ShortcutPayload.date("2026-10-20T08:00:00+02:00"), HealthExportParser.date("2026-10-20 06:00:00 +0000"))
        XCTAssertNotNil(ShortcutPayload.date("2026-10-20T08:00:00.123Z"))
        XCTAssertEqual(ShortcutPayload.sleepStage("Kern"), .core)
        XCTAssertEqual(ShortcutPayload.sleepStage("REM"), .rem)
        XCTAssertEqual(ShortcutPayload.sleepStage("Tief"), .deep)
        XCTAssertEqual(ShortcutPayload.sleepStage("Im Bett"), .inBed)
        XCTAssertEqual(ShortcutPayload.sleepStage("Wach"), .awake)
        XCTAssertEqual(ShortcutPayload.sleepStage("Schlafend"), .asleepUnspecified)
    }

    func testParsePayload() throws {
        let text = """
        @hrv.dates
        2026-10-20T02:00:00Z
        @hrv.values
        64
        @rhr.dates
        2026-10-20T08:00:00Z
        @rhr.values
        52
        @hr.dates
        2026-10-20T17:00:00Z
        2026-10-20T17:01:00Z
        @hr.values
        150
        155
        @steps.dates
        2026-10-20T00:00:00Z
        @steps.values
        12.345
        @resp.dates
        2026-10-20T03:00:00Z
        @resp.values
        14
        15
        @sleep.start
        2026-10-19T23:00:00Z
        @sleep.end
        2026-10-20T03:00:00Z
        @sleep.values
        Kern
        """
        let result = try ShortcutPayload.parse(text)
        XCTAssertEqual(result.counts["hrv"], 1)
        XCTAssertEqual(result.counts["hr"], 2)
        XCTAssertEqual(result.counts["sleep"], 1)
        XCTAssertNil(result.counts["resp"], "misaligned section is skipped")
        XCTAssertEqual(result.warnings.count, 1)

        let now = HealthExportParser.date("2026-10-21 12:00:00 +0000")!
        let days = HealthExportBuilder.days(from: result.data, count: 2, profile: UserProfile(), now: now, calendar: utc)
        let day = try XCTUnwrap(days.first)
        XCTAssertEqual(day.hrv, 64)
        XCTAssertEqual(day.restingHR, 52)
        XCTAssertEqual(day.steps, 12_345)
        XCTAssertEqual(day.sleep?.asleep, 4 * 3600)
        XCTAssertNotNil(day.trimp)
    }

    func testEmptyPayloadThrows() {
        XCTAssertThrowsError(try ShortcutPayload.parse("hallo"))
    }

    func testMergeKeepsOldFieldsAndFillsGaps() {
        let calendar = utc
        let today = HealthExportParser.date("2026-10-21 00:00:00 +0000")!
        let yesterday = HealthExportParser.date("2026-10-20 00:00:00 +0000")!
        let old = DayMetrics(date: yesterday, hrv: 60, bodyMass: 80)
        let update = DayMetrics(date: yesterday, hrv: 65)

        let merged = DayMerger.merge(existing: [old], updates: [update], keepDays: 5, today: today, calendar: calendar)
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged.last?.date, today)
        let day = merged.first { $0.date == yesterday }
        XCTAssertEqual(day?.hrv, 65)
        XCTAssertEqual(day?.bodyMass, 80)
    }
}
