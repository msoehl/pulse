import SwiftUI
import HealthCore

// MARK: - Theme

extension Color {
    static let recoveryGreen = Color(red: 0.09, green: 0.85, blue: 0.40)
    static let recoveryYellow = Color(red: 1.0, green: 0.80, blue: 0.0)
    static let recoveryRed = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let strainBlue = Color(red: 0.0, green: 0.58, blue: 0.95)
    static let sleepPurple = Color(red: 0.58, green: 0.47, blue: 1.0)
    static let cardBackground = Color(white: 0.11)
}

extension RecoveryZone {
    var color: Color {
        switch self {
        case .green: return .recoveryGreen
        case .yellow: return .recoveryYellow
        case .red: return .recoveryRed
        }
    }
}

extension SleepStage {
    var label: String {
        switch self {
        case .inBed: return "Im Bett"
        case .awake: return "Wach"
        case .asleepUnspecified: return "Schlaf"
        case .core: return "Kern"
        case .deep: return "Tief"
        case .rem: return "REM"
        }
    }

    var color: Color {
        switch self {
        case .inBed: return Color(white: 0.3)
        case .awake: return .orange
        case .asleepUnspecified: return .sleepPurple.opacity(0.6)
        case .core: return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .deep: return Color(red: 0.35, green: 0.25, blue: 0.85)
        case .rem: return Color(red: 0.4, green: 0.85, blue: 1.0)
        }
    }
}

extension InsightKind {
    var color: Color {
        switch self {
        case .positive: return .recoveryGreen
        case .neutral: return .strainBlue
        case .warning: return .recoveryYellow
        }
    }

    var symbol: String {
        switch self {
        case .positive: return "checkmark.circle.fill"
        case .neutral: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Formatting

enum Format {
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func time(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .shortened) ?? "–"
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ScoreRing: View {
    let progress: Double
    let color: Color
    let value: String
    let label: String
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(lineWidth)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var detail: String?
    var detailColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(detailColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A value compared with its baseline; `higherIsBetter` decides the color of the delta.
struct BaselineRow: View {
    let name: String
    let value: Double?
    let baseline: Double?
    let unit: String
    var digits: Int = 0
    var higherIsBetter = true

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if let value, let baseline {
                let delta = value - baseline
                let good = higherIsBetter ? delta >= 0 : delta <= 0
                Text((delta >= 0 ? "+" : "") + Format.number(delta, digits: digits))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(abs(delta) < 0.0001 ? Color.secondary : (good ? Color.recoveryGreen : Color.recoveryRed))
            }
            Text(Format.number(value, digits: digits) + " " + unit)
                .monospacedDigit()
                .frame(minWidth: 90, alignment: .trailing)
        }
        .font(.subheadline)
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.kind.symbol)
                .foregroundStyle(insight.kind.color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct DateSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button { model.shiftDate(by: -1) } label: {
                Image(systemName: "chevron.left").padding(8)
            }
            .disabled(!model.canShift(by: -1))
            Spacer()
            Text(Format.dayTitle(model.selectedDate)).font(.headline)
            Spacer()
            Button { model.shiftDate(by: 1) } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .disabled(!model.canShift(by: 1))
        }
    }
}

/// Shared scaffold for all tabs: navigation, date switcher, loading and error states.
struct Screen<Content: View>: View {
    let title: String
    @ViewBuilder let content: (DayReport) -> Content

    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DateSwitcher()
                    if let report = model.selectedReport {
                        content(report)
                    } else {
                        placeholder
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if model.state == .loading { ProgressView() }
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Lese Apple-Health-Daten …").padding(.top, 80)
        case .failed(let message):
            Card(title: "Fehler") {
                Text(message)
                Button("Erneut versuchen") { Task { await model.refresh() } }
            }
        case .loaded:
            Card {
                Text("Keine Daten für diesen Tag. Prüfe unter Einstellungen › Health › Datenzugriff, ob Pulse Lesezugriff hat.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
