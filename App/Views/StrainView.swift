import SwiftUI
import Charts
import HealthCore

struct StrainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Belastung") { report in
            StrainContent(
                report: report,
                recent: model.reports(endingAt: report.id, days: 14),
                loadWindow: model.reports(endingAt: report.id, days: 60),
                workouts: model.workouts(on: report.id)
            )
        }
    }
}

private struct StrainContent: View {
    let report: DayReport
    let recent: [DayReport]
    let loadWindow: [DayReport]
    let workouts: [WorkoutSummary]

    private static let zoneNames = ["Z1 50–60 %", "Z2 60–70 %", "Z3 70–80 %", "Z4 80–90 %", "Z5 90–100 %"]
    private static let zoneColors: [Color] = [.gray, .strainBlue, .green, .orange, .red]

    var body: some View {
        VStack(spacing: 16) {
            summary
            zones
            workoutList
            load
            history
        }
    }

    private var summary: some View {
        Card {
            HStack(spacing: 20) {
                ScoreRing(progress: (report.strain ?? 0) / 21, color: .strainBlue,
                          value: Format.number(report.strain, digits: 1), label: "von 21")
                    .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 10) {
                    if let recovery = report.recovery {
                        let range = StrainEngine.recommendedRange(for: recovery.zone)
                        StatTile(title: "Optimal heute", value: "\(Int(range.lowerBound))–\(Int(range.upperBound))",
                                 detail: "bei \(recovery.score) % Recovery", detailColor: recovery.zone.color)
                    }
                    StatTile(title: "TRIMP", value: Format.number(report.metrics.trimp))
                }
            }
        }
    }

    private var zones: some View {
        let minutes = report.metrics.zoneMinutes ?? Array(repeating: 0, count: 5)
        let total = max(minutes.reduce(0, +), 1)
        return Card(title: "Herzfrequenzzonen") {
            ForEach(0..<5, id: \.self) { index in
                HStack {
                    Text(Self.zoneNames[index]).font(.caption).frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Self.zoneColors[index])
                            .frame(width: max(4, geo.size.width * minutes[index] / total))
                    }
                    .frame(height: 10)
                    Text("\(Int(minutes[index].rounded())) min")
                        .font(.caption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
            }
            Text("Zonen nach Herzfrequenzreserve (Karvonen)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var workoutList: some View {
        if !workouts.isEmpty {
            Card(title: "Workouts") {
                ForEach(workouts) { workout in
                    HStack(spacing: 12) {
                        Image(systemName: workout.symbol)
                            .font(.title3)
                            .foregroundStyle(Color.strainBlue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name).font(.subheadline.weight(.semibold))
                            Text("\(Format.time(workout.start)) · \(Format.duration(workout.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let hr = workout.averageHR {
                                Text("Ø \(Int(hr.rounded())) bpm").font(.caption.monospacedDigit())
                            }
                            if let kcal = workout.energy {
                                Text("\(Int(kcal.rounded())) kcal").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var load: some View {
        let points = loadWindow.compactMap(\.load)
        return Card(title: "Trainingslast") {
            if let current = report.load {
                HStack {
                    StatTile(title: "Akut (7 T)", value: Format.number(current.acute))
                    StatTile(title: "Chronisch (42 T)", value: Format.number(current.chronic))
                    StatTile(title: "Verhältnis", value: Format.number(current.ratio, digits: 2),
                             detail: ratioLabel(current.ratio), detailColor: ratioColor(current.ratio))
                }
            }
            Chart {
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Tag", point.date, unit: .day), y: .value("Last", point.chronic),
                             series: .value("Art", "Chronisch"))
                        .foregroundStyle(Color.strainBlue)
                    LineMark(x: .value("Tag", point.date, unit: .day), y: .value("Last", point.acute),
                             series: .value("Art", "Akut"))
                        .foregroundStyle(Color.orange)
                }
            }
            .frame(height: 150)
            Text("Orange: akute Last (Ermüdung) · Blau: chronische Last (Fitness)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func ratioLabel(_ ratio: Double?) -> String? {
        guard let ratio else { return nil }
        switch ratio {
        case ..<0.8: return "Unterbelastung"
        case ..<1.3: return "Optimal"
        case ..<1.5: return "Erhöht"
        default: return "Überlastungsrisiko"
        }
    }

    private func ratioColor(_ ratio: Double?) -> Color {
        guard let ratio else { return .secondary }
        switch ratio {
        case ..<0.8: return .strainBlue
        case ..<1.3: return .recoveryGreen
        case ..<1.5: return .recoveryYellow
        default: return .recoveryRed
        }
    }

    private var history: some View {
        Card(title: "Letzte 14 Tage") {
            Chart(recent) { day in
                if let strain = day.strain {
                    BarMark(x: .value("Tag", day.id, unit: .day), y: .value("Belastung", strain))
                        .foregroundStyle(Color.strainBlue.gradient)
                        .cornerRadius(3)
                }
            }
            .chartYScale(domain: 0...21)
            .frame(height: 140)
        }
    }
}
