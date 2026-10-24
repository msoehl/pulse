import Foundation

// Text sent by the "Pulse Sync" shortcut. The Shortcuts app may read Apple Health without
// the HealthKit entitlement, so it collects samples and hands them to Pulse as plain text:
//
//   @hrv.dates            ← one ISO 8601 date per line
//   2026-10-24T03:12:00+02:00
//   @hrv.values           ← one value per line, same order
//   48
//
// Sleep uses @sleep.start, @sleep.end and @sleep.values.

public struct ShortcutPayloadResult: Sendable {
    public var data = RawHealthData()
    /// Samples read per section, e.g. ["hrv": 4, "hr": 2310].
    public var counts: [String: Int] = [:]
    public var warnings: [String] = []
}

public enum ShortcutPayloadError: LocalizedError {
    case empty

    public var errorDescription: String? {
        "Der Kurzbefehl hat keine Pulse-Daten übergeben. Prüfe, ob der Text mit den @-Zeilen an die Pulse-Aktion übergeben wird."
    }
}

public enum ShortcutPayload {
    /// Section key → quantity. Large daily totals may contain thousands separators.
    static let quantityKeys: [(key: String, kind: QuantityKind)] = [
        ("hrv", .hrv),
        ("rhr", .restingHR),
        ("resp", .respiratoryRate),
        ("spo2", .oxygen),
        ("temp", .wristTemperature),
        ("vo2", .vo2Max),
        ("weight", .bodyMass),
        ("steps", .steps),
        ("energy", .activeEnergy),
    ]

    /// Every header the shortcut's Text action should contain, in order.
    public static let template: String = {
        var lines: [String] = []
        for key in ["hrv", "rhr", "hr", "resp", "spo2", "temp", "vo2", "weight", "steps", "energy"] {
            lines.append("@\(key).dates")
            lines.append("@\(key).values")
        }
        lines.append(contentsOf: ["@sleep.start", "@sleep.end", "@sleep.values"])
        return lines.joined(separator: "\n")
    }()

    public static func parse(_ text: String) throws -> ShortcutPayloadResult {
        var sections: [String: [String]] = [:]
        var current: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("@") {
                let key = String(line.dropFirst()).lowercased()
                if sections[key] == nil { sections[key] = [] }
                current = key
            } else if let current {
                sections[current, default: []].append(line)
            }
        }
        guard !sections.isEmpty else { throw ShortcutPayloadError.empty }

        var result = ShortcutPayloadResult()

        for (key, kind) in quantityKeys {
            guard let pairs = pairs(key, in: sections, result: &result) else { continue }
            let grouping = kind == .steps || kind == .activeEnergy
            var samples: [QuantitySample] = []
            for (dateText, valueText) in pairs {
                guard let date = date(dateText), let value = number(valueText, allowGrouping: grouping) else { continue }
                samples.append(QuantitySample(start: date, value: HealthExportParser.normalize(kind, value: value, unit: nil), source: "Kurzbefehl"))
            }
            result.data.quantities[kind] = samples
            result.counts[key] = samples.count
        }

        if let pairs = pairs("hr", in: sections, result: &result) {
            result.data.heartRate = pairs.compactMap { dateText, valueText in
                guard let date = date(dateText), let bpm = number(valueText, allowGrouping: false) else { return nil }
                return HeartRateSample(date: date, bpm: bpm)
            }
            result.counts["hr"] = result.data.heartRate.count
        }

        let starts = sections["sleep.start"] ?? []
        let ends = sections["sleep.end"] ?? []
        let stages = sections["sleep.values"] ?? []
        if starts.count == ends.count && ends.count == stages.count {
            for i in starts.indices {
                guard let start = date(starts[i]), let end = date(ends[i]), let stage = sleepStage(stages[i]) else { continue }
                result.data.sleep.append(SleepSegment(start: start, end: end, stage: stage))
            }
            if !starts.isEmpty { result.counts["sleep"] = result.data.sleep.count }
        } else {
            result.warnings.append("Schlaf: unterschiedlich viele Start-, End- und Phasenzeilen (\(starts.count)/\(ends.count)/\(stages.count)).")
        }

        result.data.recordCount = result.counts.values.reduce(0, +)
        return result
    }

    /// Zips `<key>.dates` and `<key>.values`; nil if the section is missing or misaligned.
    private static func pairs(_ key: String, in sections: [String: [String]], result: inout ShortcutPayloadResult) -> [(String, String)]? {
        guard let dates = sections["\(key).dates"], let values = sections["\(key).values"] else { return nil }
        guard dates.count == values.count else {
            result.warnings.append("\(key): \(dates.count) Datumszeilen, aber \(values.count) Werte.")
            return nil
        }
        return Array(zip(dates, values))
    }

    // MARK: - Values

    /// Accepts "64", "64,5", "64.5", "1.234" / "1,234" (thousands, only with `allowGrouping`) and trailing units.
    static func number(_ raw: String, allowGrouping: Bool) -> Double? {
        let allowed = Set("0123456789.,-")
        let compact = raw.filter { !$0.isWhitespace && $0 != "'" }
        var text = String(compact.prefix { allowed.contains($0) })
        guard !text.isEmpty else { return nil }

        if allowGrouping, text.range(of: #"^\d{1,3}([.,]\d{3})+$"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        } else if text.contains(",") {
            text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Double(text)
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    /// Fallbacks for when the date format was left at the German default.
    private static let localFormatters: [DateFormatter] = {
        ["dd.MM.yyyy, HH:mm:ss", "dd.MM.yyyy, HH:mm", "dd.MM.yy, HH:mm", "d. MMM yyyy 'um' HH:mm", "d. MMMM yyyy 'um' HH:mm"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = $0
            return formatter
        }
    }()

    static func date(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        for formatter in isoFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        for formatter in localFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Sleep values arrive as display text, in German or English.
    static func sleepStage(_ raw: String) -> SleepStage? {
        let text = raw.lowercased()
        if text.contains("bett") || text.contains("bed") { return .inBed }
        if text.contains("wach") || text.contains("awake") { return .awake }
        if text.contains("rem") { return .rem }
        if text.contains("tief") || text.contains("deep") { return .deep }
        if text.contains("kern") || text.contains("core") { return .core }
        if text.contains("schlaf") || text.contains("asleep") || text.contains("sleep") { return .asleepUnspecified }
        return nil
    }
}

extension DayMetrics {
    /// Field-wise merge: values present in `newer` win, missing ones keep the stored value.
    public func merging(_ newer: DayMetrics) -> DayMetrics {
        var merged = self
        merged.hrv = newer.hrv ?? hrv
        merged.restingHR = newer.restingHR ?? restingHR
        merged.respiratoryRate = newer.respiratoryRate ?? respiratoryRate
        merged.oxygenSaturation = newer.oxygenSaturation ?? oxygenSaturation
        merged.wristTemperature = newer.wristTemperature ?? wristTemperature
        merged.vo2Max = newer.vo2Max ?? vo2Max
        merged.bodyMass = newer.bodyMass ?? bodyMass
        merged.steps = newer.steps ?? steps
        merged.activeEnergy = newer.activeEnergy ?? activeEnergy
        merged.sleep = newer.sleep ?? sleep
        merged.trimp = newer.trimp ?? trimp
        merged.zoneMinutes = newer.zoneMinutes ?? zoneMinutes
        return merged
    }
}

public enum DayMerger {
    /// Merges `updates` into `existing` and returns one entry per day for the last `keepDays` days up to `today`.
    public static func merge(existing: [DayMetrics], updates: [DayMetrics], keepDays: Int, today: Date, calendar: Calendar = .current) -> [DayMetrics] {
        var byDay: [Date: DayMetrics] = [:]
        for day in existing { byDay[day.date] = day }
        for update in updates {
            byDay[update.date] = byDay[update.date].map { $0.merging(update) } ?? update
        }

        let end = calendar.startOfDay(for: today)
        guard keepDays > 0, let start = calendar.date(byAdding: .day, value: -(keepDays - 1), to: end) else { return [] }
        return (0..<keepDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { byDay[$0] ?? DayMetrics(date: $0) }
        }
    }
}
