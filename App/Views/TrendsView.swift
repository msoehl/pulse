import SwiftUI
import Charts
import HealthCore

enum TrendMetric: String, CaseIterable, Identifiable {
    case recovery, hrv, restingHR, sleep, strain, respiratoryRate, oxygen, temperature, vo2Max, weight, steps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: return "Recovery"
        case .hrv: return "HRV"
        case .restingHR: return "Ruhepuls"
        case .sleep: return "Schlafdauer"
        case .strain: return "Belastung"
        case .respiratoryRate: return "Atemfrequenz"
        case .oxygen: return "Blutsauerstoff"
        case .temperature: return "Hauttemperatur"
        case .vo2Max: return "VO₂max"
        case .weight: return "Gewicht"
        case .steps: return "Schritte"
        }
    }

    var unit: String {
        switch self {
        case .recovery, .oxygen: return "%"
        case .hrv: return "ms"
        case .restingHR: return "bpm"
        case .sleep: return "h"
        case .strain: return ""
        case .respiratoryRate: return "/min"
        case .temperature: return "°C"
        case .vo2Max: return "ml/kg·min"
        case .weight: return "kg"
        case .steps: return ""
        }
    }

    var digits: Int {
        switch self {
        case .sleep, .strain, .respiratoryRate, .oxygen, .vo2Max, .weight: return 1
        case .temperature: return 2
        default: return 0
        }
    }

    var higherIsBetter: Bool? {
        switch self {
        case .recovery, .hrv, .sleep, .oxygen, .vo2Max, .steps: return true
        case .restingHR, .respiratoryRate: return false
        case .strain, .temperature, .weight: return nil
        }
    }

    var color: Color {
        switch self {
        case .recovery: return .recoveryGreen
        case .sleep: return .sleepPurple
        case .strain, .steps: return .strainBlue
        case .restingHR, .temperature: return .recoveryRed
        default: return .cyan
        }
    }

    func value(_ report: DayReport) -> Double? {
        let m = report.metrics
        switch self {
        case .recovery: return report.recovery.map { Double($0.score) }
        case .hrv: return m.hrv
        case .restingHR: return m.restingHR
        case .sleep: return m.sleep.map { $0.asleep / 3600 }
        case .strain: return report.strain
        case .respiratoryRate: return m.respiratoryRate
        case .oxygen: return m.oxygenSaturation
        case .temperature: return m.wristTemperature
        case .vo2Max: return m.vo2Max
        case .weight: return m.bodyMass
        case .steps: return m.steps
        }
    }
}

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var metric: TrendMetric = .hrv
    @State private var range = 30

    var body: some View {
        Screen(title: "Trends") { report in
            let window = model.reports(endingAt: report.id, days: range)
            let points = window.compactMap { r in metric.value(r).map { DatedValue(date: r.id, value: $0) } }

            Picker("Metrik", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Zeitraum", selection: $range) {
                Text("14 T").tag(14)
                Text("30 T").tag(30)
                Text("90 T").tag(90)
                Text("120 T").tag(120)
            }
            .pickerStyle(.segmented)

            TrendChart(metric: metric, points: points)
            TrendStats(metric: metric, trend: TrendEngine.trend(points, asOf: report.id))
            CorrelationCard(reports: window)
        }
    }
}

private struct TrendChart: View {
    let metric: TrendMetric
    let points: [DatedValue]

    var body: some View {
        let values = points.map(\.value)
        let mean = Stats.mean(values)
        let sd = Stats.standardDeviation(values)
        let rolling = rollingAverage(points, window: 7)

        return Card(title: "\(metric.title) \(metric.unit.isEmpty ? "" : "(\(metric.unit))")") {
            if points.count < 2 {
                Text("Zu wenige Daten im Zeitraum.").foregroundStyle(.secondary)
            } else {
                Chart {
                    if let mean, let sd, let first = points.first?.date, let last = points.last?.date {
                        RectangleMark(
                            xStart: .value("Start", first),
                            xEnd: .value("Ende", last),
                            yStart: .value("Min", mean - sd),
                            yEnd: .value("Max", mean + sd)
                        )
                        .foregroundStyle(metric.color.opacity(0.08))
                        RuleMark(y: .value("Schnitt", mean))
                            .foregroundStyle(metric.color.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(points, id: \.date) { point in
                        PointMark(x: .value("Tag", point.date, unit: .day), y: .value(metric.title, point.value))
                            .foregroundStyle(metric.color.opacity(0.5))
                            .symbolSize(18)
                    }
                    ForEach(rolling, id: \.date) { point in
                        LineMark(x: .value("Tag", point.date, unit: .day), y: .value("7-Tage-Schnitt", point.value))
                            .foregroundStyle(metric.color)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
                Text("Punkte: Tageswerte · Linie: 7-Tage-Schnitt · Band: Mittelwert ± 1 SD")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rollingAverage(_ points: [DatedValue], window: Double) -> [DatedValue] {
        points.compactMap { point in
            let from = point.date.addingTimeInterval(-(window - 1) * 86_400)
            let slice = points.filter { $0.date >= from && $0.date <= point.date }.map(\.value)
            return Stats.mean(slice).map { DatedValue(date: point.date, value: $0) }
        }
    }
}

private struct TrendStats: View {
    let metric: TrendMetric
    let trend: MetricTrend?

    var body: some View {
        Card(title: "Statistik") {
            if let trend {
                HStack {
                    StatTile(title: "Aktuell", value: Format.number(trend.latest, digits: metric.digits), unit: metric.unit)
                    StatTile(title: "Ø 7 Tage", value: Format.number(trend.average7, digits: metric.digits))
                    StatTile(title: "Ø 30 Tage", value: Format.number(trend.average30, digits: metric.digits))
                }
                HStack {
                    StatTile(title: "7 vs. 30 Tage",
                             value: trend.changePercent.map { ($0 >= 0 ? "+" : "") + Format.number($0, digits: 1) } ?? "–",
                             unit: "%",
                             detail: directionLabel(trend.direction),
                             detailColor: directionColor(trend.direction))
                    StatTile(title: "Steigung", value: trend.slopePerWeek.map { ($0 >= 0 ? "+" : "") + Format.number($0, digits: 2) } ?? "–",
                             unit: "/Woche")
                }
            } else {
                Text("Keine Daten.").foregroundStyle(.secondary)
            }
        }
    }

    private func directionLabel(_ direction: TrendDirection) -> String {
        switch direction {
        case .up: return "steigend"
        case .down: return "fallend"
        case .stable: return "stabil"
        }
    }

    private func directionColor(_ direction: TrendDirection) -> Color {
        guard direction != .stable, let higherIsBetter = metric.higherIsBetter else { return .secondary }
        return (direction == .up) == higherIsBetter ? .recoveryGreen : .recoveryRed
    }
}

/// How the previous day's behaviour relates to the next morning's recovery.
private struct CorrelationCard: View {
    let reports: [DayReport]

    private struct Row: Identifiable {
        let id: String
        let title: String
        let r: Double
    }

    private var rows: [Row] {
        // Pairs (factor of day i-1 or night i, recovery of day i).
        var strain: [(Double, Double)] = []
        var sleepHours: [(Double, Double)] = []
        var consistency: [(Double, Double)] = []
        var steps: [(Double, Double)] = []
        for i in reports.indices.dropFirst() {
            guard let recovery = reports[i].recovery.map({ Double($0.score) }) else { continue }
            if let s = reports[i - 1].strain { strain.append((s, recovery)) }
            if let sleep = reports[i].sleep {
                sleepHours.append((sleep.night.asleep / 3600, recovery))
                if let c = sleep.consistency { consistency.append((c, recovery)) }
            }
            if let st = reports[i - 1].metrics.steps { steps.append((st, recovery)) }
        }
        return [
            ("sleep", "Schlafdauer", sleepHours),
            ("consistency", "Schlafkonsistenz", consistency),
            ("strain", "Belastung am Vortag", strain),
            ("steps", "Schritte am Vortag", steps),
        ].compactMap { id, title, pairs in
            pearson(pairs).map { Row(id: id, title: title, r: $0) }
        }
    }

    var body: some View {
        Card(title: "Was beeinflusst deine Recovery?") {
            let items = self.rows
            if items.isEmpty {
                Text("Braucht mindestens 10 Tage mit Recovery-Werten im Zeitraum.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { row in
                    HStack {
                        Text(row.title).font(.subheadline)
                        Spacer()
                        Text(label(row.r)).font(.caption).foregroundStyle(.secondary)
                        Text((row.r >= 0 ? "+" : "") + Format.number(row.r, digits: 2))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(row.r >= 0 ? Color.recoveryGreen : Color.recoveryRed)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Text("Pearson-Korrelation mit der Recovery am Folgetag. Korrelation ist keine Kausalität.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ r: Double) -> String {
        switch abs(r) {
        case ..<0.1: return "kein Zusammenhang"
        case ..<0.3: return "schwach"
        case ..<0.5: return "mittel"
        default: return "stark"
        }
    }

    private func pearson(_ pairs: [(Double, Double)]) -> Double? {
        guard pairs.count >= 10 else { return nil }
        let xs = pairs.map { $0.0 }
        let ys = pairs.map { $0.1 }
        guard let mx = Stats.mean(xs), let my = Stats.mean(ys) else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in pairs {
            sxy += (x - mx) * (y - my)
            sxx += (x - mx) * (x - mx)
            syy += (y - my) * (y - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }
}
