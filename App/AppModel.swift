import Foundation
import Observation
import HealthCore

@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    static let historyDays = 120

    var state: LoadState = .idle
    var reports: [DayReport] = []
    var workouts: [WorkoutSummary] = []
    var selectedDate: Date
    var lastUpdated: Date?
    var profile: UserProfile {
        didSet { Self.saveProfile(profile) }
    }

    private let calendar = Calendar.current
    private let service = HealthKitService()
    private let cache = TrimpCache()

    init() {
        selectedDate = Calendar.current.startOfDay(for: .now)
        profile = Self.loadProfile()
    }

    func refresh() async {
        state = .loading
        do {
            try await service.requestAuthorization()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let characteristics = service.characteristics()
        var updated = profile
        if updated.age == nil { updated.age = characteristics.age }
        if updated.sex == .unknown { updated.sex = characteristics.sex }
        if updated != profile { profile = updated }

        let days = await service.loadDays(count: Self.historyDays, profile: profile, cache: cache)
        reports = HealthAnalyzer.analyze(days: days, profile: profile, calendar: calendar)
        if let since = calendar.date(byAdding: .day, value: -60, to: .now) {
            workouts = await service.workouts(since: since)
        }

        let today = calendar.startOfDay(for: .now)
        if !reports.contains(where: { $0.id == selectedDate }) { selectedDate = today }
        lastUpdated = .now
        state = .loaded
    }

    /// Recomputes everything, e.g. after changing max heart rate.
    func reloadFromScratch() async {
        cache.clear()
        await refresh()
    }

    // MARK: - Selection

    var selectedReport: DayReport? {
        reports.first { $0.id == selectedDate }
    }

    func canShift(by days: Int) -> Bool {
        guard let target = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return false }
        return reports.contains { $0.id == target }
    }

    func shiftDate(by days: Int) {
        guard canShift(by: days), let target = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = target
    }

    /// The last `days` reports up to and including `date`.
    func reports(endingAt date: Date, days: Int) -> [DayReport] {
        Array(reports.filter { $0.id <= date }.suffix(days))
    }

    func workouts(on date: Date) -> [WorkoutSummary] {
        workouts.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    // MARK: - Persistence

    private static let profileKey = "userProfile"

    private static func loadProfile() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return UserProfile() }
        return profile
    }

    private static func saveProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
}
