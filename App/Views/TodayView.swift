import SwiftUI
import Charts
import HealthCore

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Übersicht") { report in
            TodayContent(
                report: report,
                week: model.reports(endingAt: report.id, days: 7),
                month: model.reports(endingAt: report.id, days: 31)
            )
        }
    }
}

private struct TodayContent: View {
    let report: DayReport
    let week: [DayReport]
    let month: [DayReport]

    var body: some View {
        VStack(spacing: 16) {
            rings
            if let recovery = report.recovery {
                strainTarget(recovery)
            }
            vitals
            insights
            recoveryWeek
        }
    }

    private var rings: some View {
        HStack(spacing: 14) {
            ScoreRing(
                progress: Double(report.recovery?.score ?? 0) / 100,
                color: report.recovery?.zone.color ?? .gray,
                value: report.recovery.map { "\($0.score)%" } ?? "–",
                label: "Recovery"
            )
            ScoreRing(
                progress: (report.strain ?? 0) / 21,
                color: .strainBlue,
                value: Format.number(report.strain, digits: 1),
                label: "Belastung"
            )
            ScoreRing(
                progress: report.sleep?.performance ?? 0,
                color: .sleepPurple,
                value: report.sleep.map { "\(Int(($0.performance * 100).rounded()))%" } ?? "–",
                label: "Schlaf"
            )
        }
        .frame(height: 112)
        .padding(.vertical, 4)
    }

    private func strainTarget(_ recovery: RecoveryResult) -> some View {
        let range = StrainEngine.recommendedRange(for: recovery.zone)
        let strain = report.strain ?? 0
        return Card(title: "Tagesziel Belastung") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(range.lowerBound))–\(Int(range.upperBound))")
                    .font(.title2.weight(.bold))
                Text("optimal bei \(recovery.score) % Recovery")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(recovery.zone.color.opacity(0.35))
                        .frame(width: width * (range.upperBound - range.lowerBound) / 21)
                        .offset(x: width * range.lowerBound / 21)
                    Circle().fill(Color.strainBlue)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, width * min(strain, 21) / 21 - 7))
                }
            }
            .frame(height: 14)
        }
    }

    private var vitals: some View {
        let m = report.metrics
        let history = month.dropLast().map(\.metrics)
        func baseline(_ key: KeyPath<DayMetrics, Double?>) -> Double? {
            Stats.mean(history.compactMap { $0[keyPath: key] })
        }
        return Card(title: "Vitalwerte vs. 30-Tage-Schnitt") {
            BaselineRow(name: "HRV", value: m.hrv, baseline: report.recovery?.component(.hrv)?.baseline ?? baseline(\.hrv), unit: "ms")
            BaselineRow(name: "Ruhepuls", value: m.restingHR, baseline: baseline(\.restingHR), unit: "bpm", higherIsBetter: false)
            BaselineRow(name: "Atemfrequenz", value: m.respiratoryRate, baseline: baseline(\.respiratoryRate), unit: "/min", digits: 1, higherIsBetter: false)
            BaselineRow(name: "Blutsauerstoff", value: m.oxygenSaturation, baseline: baseline(\.oxygenSaturation), unit: "%", digits: 1)
            BaselineRow(name: "Hauttemperatur", value: m.wristTemperature, baseline: baseline(\.wristTemperature), unit: "°C", digits: 2, higherIsBetter: false)
            Divider().overlay(Color.white.opacity(0.1))
            HStack {
                StatTile(title: "Schritte", value: Format.number(m.steps))
                StatTile(title: "Aktivenergie", value: Format.number(m.activeEnergy), unit: "kcal")
                StatTile(title: "VO₂max", value: Format.number(month.last { $0.metrics.vo2Max != nil }?.metrics.vo2Max, digits: 1))
            }
        }
    }

    private var insights: some View {
        let items = InsightEngine.insights(for: report)
        return Card(title: "Insights") {
            if items.isEmpty {
                Text("Keine Auffälligkeiten.").foregroundStyle(.secondary)
            }
            ForEach(items) { InsightRow(insight: $0) }
        }
    }

    private var recoveryWeek: some View {
        Card(title: "Recovery – 7 Tage") {
            Chart(week) { day in
                if let recovery = day.recovery {
                    BarMark(
                        x: .value("Tag", day.id, unit: .day),
                        y: .value("Recovery", recovery.score)
                    )
                    .foregroundStyle(recovery.zone.color)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(recovery.score)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 140)
        }
    }
}
