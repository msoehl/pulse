import Foundation
import Observation
import HealthCore

@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle, loading, importing(Int), needsImport, loaded, failed(String)
    }

    enum DataSource: Equatable {
        case healthKit
        /// Health export and/or "Pulse Sync" shortcut, last updated at the given date.
        case imported(Date)
    }

    static let historyDays = HealthExportImporter.historyDays

    var state: LoadState = .idle
    var reports: [DayReport] = []
    var workouts: [WorkoutSummary] = []
    var selectedDate: Date
    var lastUpdated: Date?
    var dataSource: DataSource?
    var showImporter = false
    var profile: UserProfile {
        didSet { ProfileStore.save(profile) }
    }

    private let calendar = Calendar.current
    private let service = HealthKitService()
    private let cache = TrimpCache()
    private var imported: ImportedHealthData?

    init() {
        selectedDate = Calendar.current.startOfDay(for: .now)
        profile = ProfileStore.load()
    }

    /// Uses HealthKit when the app was signed with the HealthKit entitlement,
    /// otherwise the last imported Health export.
    func refresh() async {
        state = .loading
        do {
            try await service.requestAuthorization()
        } catch {
            showImportedData()
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

        dataSource = .healthKit
        lastUpdated = .now
        selectLatestIfNeeded()
        state = .loaded
    }

    /// Recomputes everything, e.g. after changing max heart rate.
    func reloadFromScratch() async {
        cache.clear()
        await refresh()
    }

    func importExport(from url: URL) async {
        state = .importing(0)
        let days = Self.historyDays
        let profile = self.profile
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try HealthExportImporter.run(url: url, days: days, profile: profile) { count in
                    Task { @MainActor [weak self] in self?.state = .importing(count) }
                }
            }.value
            HealthExportImporter.save(data)
            imported = data
            apply(data)
        } catch {
            state = .failed(error.localizedDescription)
        }
        // Files shared into the app land in Documents/Inbox; they are no longer needed.
        if url.path.contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Re-runs the analysis on the stored import, e.g. after the sleep need changed.
    func reapplyImport() {
        if let imported { apply(imported) }
    }

    private func showImportedData() {
        // Always read from disk: the shortcut may have written new data in the meantime.
        imported = HealthExportImporter.load()
        if let imported {
            apply(imported)
        } else {
            state = .needsImport
        }
    }

    private func apply(_ data: ImportedHealthData) {
        var updated = profile
        if updated.age == nil, let birth = data.dateOfBirth {
            updated.age = calendar.dateComponents([.year], from: birth, to: .now).year
        }
        if updated.sex == .unknown { updated.sex = data.sex }
        if updated != profile { profile = updated }

        reports = HealthAnalyzer.analyze(days: data.days, profile: profile, calendar: calendar)
        workouts = data.workouts.map(WorkoutSummary.init(exported:)).sorted { $0.start > $1.start }
        dataSource = .imported(data.importedAt)
        lastUpdated = data.importedAt
        selectLatestIfNeeded()
        state = .loaded
    }

    private func selectLatestIfNeeded() {
        guard !reports.contains(where: { $0.id == selectedDate }) else { return }
        let today = calendar.startOfDay(for: .now)
        selectedDate = reports.contains(where: { $0.id == today }) ? today : (reports.last?.id ?? today)
    }

    var isBusy: Bool {
        switch state {
        case .loading, .importing: return true
        default: return false
        }
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

}
