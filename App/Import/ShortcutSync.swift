import AppIntents
import Foundation
import HealthCore

extension Notification.Name {
    /// Posted after a shortcut delivered new data while the app is running.
    static let pulseDataDidChange = Notification.Name("pulseDataDidChange")
}

enum ProfileStore {
    private static let key = "userProfile"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return UserProfile() }
        return profile
    }

    static func save(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum ShortcutSync {
    /// Calendar days the shortcut is expected to cover completely. It fetches one day more,
    /// because the oldest day of "the last 4 days" is cut off in the middle.
    static let completeDays = 3

    /// Merges the shortcut's samples into the stored data and returns a short summary for the shortcut.
    static func apply(payload: String) throws -> String {
        let parsed = try ShortcutPayload.parse(payload)
        let calendar = Calendar.current
        let now = Date()
        let fresh = HealthExportBuilder.days(from: parsed.data, count: completeDays, profile: ProfileStore.load(), now: now, calendar: calendar)

        var stored = HealthExportImporter.load()
            ?? ImportedHealthData(days: [], workouts: [], dateOfBirth: nil, sex: .unknown, importedAt: now)
        stored.days = DayMerger.merge(existing: stored.days, updates: fresh,
                                      keepDays: HealthExportImporter.historyDays, today: now, calendar: calendar)
        stored.importedAt = now
        HealthExportImporter.save(stored)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pulseDataDidChange, object: nil)
        }

        let labels: [(String, String)] = [
            ("hrv", "HRV"), ("rhr", "Ruhepuls"), ("hr", "Herzfrequenz"), ("sleep", "Schlaf"),
            ("resp", "Atemfrequenz"), ("spo2", "SpO₂"), ("temp", "Temperatur"), ("vo2", "VO₂max"),
            ("weight", "Gewicht"), ("steps", "Schritte"), ("energy", "Energie"),
        ]
        var lines = labels.compactMap { key, label in parsed.counts[key].map { "\(label): \($0)" } }
        lines.append(contentsOf: parsed.warnings)
        return "Pulse aktualisiert\n" + lines.joined(separator: "\n")
    }
}

/// Shortcuts action "Health-Daten an Pulse übergeben".
struct SendHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Health-Daten an Pulse übergeben"
    static var description = IntentDescription("Übernimmt die Health-Werte aus dem Kurzbefehl „Pulse Sync“.")
    static var openAppWhenRun = false

    @Parameter(title: "Daten")
    var payload: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = try ShortcutSync.apply(payload: payload)
        return .result(value: summary)
    }
}
