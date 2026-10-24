import SwiftUI
import Charts
import HealthCore

struct SleepView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Schlaf") { report in
            if let sleep = report.sleep {
                SleepContent(sleep: sleep, recent: model.reports(endingAt: report.id, days: 14))
            } else {
                Card {
                    Text("Für diese Nacht liegen keine Schlafdaten vor. Für Schlafphasen die Apple Watch nachts tragen und den Schlaffokus aktivieren.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SleepContent: View {
    let sleep: SleepAnalysis
    let recent: [DayReport]

    private var night: SleepNight { sleep.night }

    var body: some View {
        VStack(spacing: 16) {
            summary
            hypnogram
            stages
            need
            history
        }
    }

    private var summary: some View {
        Card {
            HStack(spacing: 20) {
                ScoreRing(progress: sleep.performance, color: .sleepPurple,
                          value: "\(Int((sleep.performance * 100).rounded()))%", label: "Bedarf")
                    .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 10) {
                    StatTile(title: "Geschlafen", value: Format.duration(night.asleep),
                             detail: "von \(Format.duration(sleep.need.total)) Bedarf")
                    StatTile(title: "Schlafscore", value: "\(sleep.score)")
                }
            }
            HStack {
                StatTile(title: "Im Bett", value: "\(Format.time(night.start)) – \(Format.time(night.end))")
                StatTile(title: "Effizienz", value: "\(Int((night.efficiency * 100).rounded()))", unit: "%")
            }
            HStack {
                StatTile(title: "Konsistenz", value: Format.number(sleep.consistency), unit: sleep.consistency == nil ? "" : "%")
                StatTile(title: "Wachphasen", value: "\(night.disturbances)")
            }
        }
    }

    private var hypnogram: some View {
        let order: [SleepStage] = [.awake, .rem, .core, .deep]
        let segments = night.segments.filter { $0.stage != .inBed }
        return Card(title: "Schlafphasen") {
            if night.hasStages {
                Chart(segments, id: \.start) { segment in
                    RectangleMark(
                        xStart: .value("Start", segment.start),
                        xEnd: .value("Ende", segment.end),
                        y: .value("Phase", segment.stage.label),
                        height: .ratio(0.8)
                    )
                    .foregroundStyle(segment.stage.color)
                }
                .chartYScale(domain: order.map(\.label))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 160)
            } else {
                Text("Keine Phasendaten – nur Gesamtschlaf verfügbar (z. B. iPhone-Schlafenszeit).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stages: some View {
        let asleep = max(night.asleep, 1)
        let rows: [SleepStage] = night.hasStages ? [.deep, .rem, .core, .awake] : [.asleepUnspecified, .awake]
        return Card(title: "Verteilung") {
            ForEach(rows, id: \.self) { stage in
                let duration = stage == .awake ? night.awake : night.duration(of: stage)
                let share = duration / (stage == .awake ? max(night.timeInBed, 1) : asleep)
                HStack {
                    Circle().fill(stage.color).frame(width: 10, height: 10)
                    Text(stage.label)
                    Spacer()
                    Text(Format.duration(duration)).monospacedDigit()
                    Text("\(Int((share * 100).rounded())) %")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .font(.subheadline)
            }
            if night.hasStages {
                Text("Erholsam (Tief + REM): \(Format.duration(night.restorative)) · Ziel ca. 40 %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var need: some View {
        Card(title: "Schlafbedarf") {
            needRow("Basis", sleep.need.baseline)
            needRow("+ Belastung gestern", sleep.need.strain)
            needRow("+ Schlafschuld", sleep.need.debt)
            Divider().overlay(Color.white.opacity(0.1))
            needRow("Gesamt", sleep.need.total).fontWeight(.semibold)
        }
    }

    private func needRow(_ title: String, _ value: TimeInterval) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Format.duration(value)).monospacedDigit()
        }
        .font(.subheadline)
    }

    private var history: some View {
        Card(title: "Letzte 14 Nächte") {
            Chart {
                ForEach(recent) { day in
                    if let s = day.sleep {
                        BarMark(
                            x: .value("Nacht", day.id, unit: .day),
                            y: .value("Stunden", s.night.asleep / 3600)
                        )
                        .foregroundStyle(Color.sleepPurple.gradient)
                        .cornerRadius(3)
                        LineMark(
                            x: .value("Nacht", day.id, unit: .day),
                            y: .value("Bedarf", s.need.total / 3600)
                        )
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
            }
            .chartYAxisLabel("h")
            .frame(height: 160)
            Text("Balken: Schlaf · Linie: Bedarf")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
