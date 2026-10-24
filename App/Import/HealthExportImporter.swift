import Foundation
import ZIPFoundation
import HealthCore

/// Result of importing a Health export, persisted so the app works offline until the next import.
struct ImportedHealthData: Codable {
    var days: [DayMetrics]
    var workouts: [ExportedWorkout]
    var dateOfBirth: Date?
    var sex: BiologicalSex
    var importedAt: Date
}

enum HealthExportImporter {
    /// Reads `export.zip` (or an already unpacked `export.xml`). Runs for a while on big exports, so call it off the main actor.
    static func run(url: URL, days: Int, profile: UserProfile, progress: @escaping (Int) -> Void) throws -> ImportedHealthData {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var extracted: URL?
        defer { if let extracted { try? FileManager.default.removeItem(at: extracted) } }

        let xmlURL: URL
        if url.pathExtension.lowercased() == "zip" {
            guard let archive = try? Archive(url: url, accessMode: .read) else { throw HealthExportError.unreadable }
            guard let entry = archive.first(where: { $0.path.hasSuffix("/export.xml") || $0.path == "export.xml" }) else {
                throw HealthExportError.noData
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).xml")
            _ = try archive.extract(entry, to: destination)
            extracted = destination
            xmlURL = destination
        } else {
            xmlURL = url
        }

        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -(days + 1), to: Date()) ?? .distantPast
        let raw = try HealthExportParser(since: cutoff, progress: progress).parse(contentsOf: xmlURL)
        guard raw.recordCount > 0 else { throw HealthExportError.noData }

        var effectiveProfile = profile
        if effectiveProfile.age == nil, let birth = raw.dateOfBirth {
            effectiveProfile.age = calendar.dateComponents([.year], from: birth, to: Date()).year
        }
        if effectiveProfile.sex == .unknown { effectiveProfile.sex = raw.sex }

        return ImportedHealthData(
            days: HealthExportBuilder.days(from: raw, count: days, profile: effectiveProfile, calendar: calendar),
            workouts: raw.workouts,
            dateOfBirth: raw.dateOfBirth,
            sex: raw.sex,
            importedAt: Date()
        )
    }

    // MARK: - Storage

    private static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("health-import.json")
    }

    static func load() -> ImportedHealthData? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        return try? JSONDecoder().decode(ImportedHealthData.self, from: data)
    }

    static func save(_ imported: ImportedHealthData) {
        let url = storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(imported) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension WorkoutSummary {
    private static let catalog: [String: (String, String)] = [
        "Running": ("Laufen", "figure.run"),
        "Walking": ("Gehen", "figure.walk"),
        "Hiking": ("Wandern", "figure.hiking"),
        "Cycling": ("Radfahren", "figure.outdoor.cycle"),
        "Swimming": ("Schwimmen", "figure.pool.swim"),
        "TraditionalStrengthTraining": ("Krafttraining", "figure.strengthtraining.traditional"),
        "FunctionalStrengthTraining": ("Krafttraining", "figure.strengthtraining.traditional"),
        "HighIntensityIntervalTraining": ("HIIT", "figure.highintensity.intervaltraining"),
        "Yoga": ("Yoga", "figure.yoga"),
        "Rowing": ("Rudern", "figure.rower"),
        "Elliptical": ("Crosstrainer", "figure.elliptical"),
        "Soccer": ("Fußball", "figure.soccer"),
        "Tennis": ("Tennis", "figure.tennis"),
        "CoreTraining": ("Core", "figure.core.training"),
        "CrossTraining": ("Cross-Training", "figure.cross.training"),
    ]

    init(exported workout: ExportedWorkout) {
        let (name, symbol) = Self.catalog[workout.activityType] ?? ("Training", "figure.mixed.cardio")
        self.init(
            id: UUID(),
            name: name,
            symbol: symbol,
            start: workout.start,
            end: workout.end,
            energy: workout.energy,
            averageHR: workout.averageHR
        )
    }
}
