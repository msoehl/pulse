import Foundation

public enum InsightKind: String, Sendable {
    case positive, neutral, warning
}

public struct Insight: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let kind: InsightKind
}

public enum InsightEngine {
    public static func insights(for report: DayReport) -> [Insight] {
        var out: [Insight] = []

        if let recovery = report.recovery {
            let range = StrainEngine.recommendedRange(for: recovery.zone)
            let target = "\(Int(range.lowerBound))–\(Int(range.upperBound))"
            switch recovery.zone {
            case .green:
                out.append(Insight(id: "zone", title: "Bereit für Belastung",
                                   message: "Recovery \(recovery.score) % – gut erholt. Zielbelastung heute: \(target).",
                                   kind: .positive))
            case .yellow:
                out.append(Insight(id: "zone", title: "Moderat belasten",
                                   message: "Recovery \(recovery.score) % – normale Belastung möglich. Zielbelastung: \(target).",
                                   kind: .neutral))
            case .red:
                out.append(Insight(id: "zone", title: "Erholung priorisieren",
                                   message: "Recovery \(recovery.score) % – leichte Aktivität, früh schlafen. Zielbelastung: \(target).",
                                   kind: .warning))
            }

            if let hrv = recovery.component(.hrv), let base = hrv.baseline, base > 0 {
                let pct = (hrv.value / base - 1) * 100
                if pct <= -10 {
                    out.append(Insight(id: "hrv", title: "HRV unter Baseline",
                                       message: "HRV \(Int(hrv.value.rounded())) ms liegt \(Int(abs(pct).rounded())) % unter deinem Schnitt (\(Int(base.rounded())) ms).",
                                       kind: .warning))
                } else if pct >= 10 {
                    out.append(Insight(id: "hrv", title: "HRV über Baseline",
                                       message: "HRV \(Int(hrv.value.rounded())) ms liegt \(Int(pct.rounded())) % über deinem Schnitt.",
                                       kind: .positive))
                }
            }

            if let rhr = recovery.component(.restingHR), let base = rhr.baseline, rhr.value - base >= 3 {
                out.append(Insight(id: "rhr", title: "Ruhepuls erhöht",
                                   message: "Ruhepuls \(Int(rhr.value.rounded())) bpm, \(Int((rhr.value - base).rounded())) bpm über Baseline. Mögliche Ursachen: Alkohol, spätes Essen, Infekt, Stress.",
                                   kind: .warning))
            }

            for flag in recovery.flags {
                switch flag {
                case .elevatedTemperature:
                    out.append(Insight(id: "temp", title: "Hauttemperatur erhöht",
                                       message: "Nächtliche Handgelenktemperatur liegt ≥ 0,5 °C über deinem Schnitt.",
                                       kind: .warning))
                case .lowOxygen:
                    out.append(Insight(id: "spo2", title: "Niedriger Blutsauerstoff",
                                       message: "Blutsauerstoff unter 94 %. Bei wiederholten Werten ärztlich abklären.",
                                       kind: .warning))
                case .elevatedRespiration:
                    out.append(Insight(id: "resp", title: "Atemfrequenz erhöht",
                                       message: "Atemfrequenz deutlich über Baseline – oft ein frühes Zeichen für Infekt oder Überlastung.",
                                       kind: .warning))
                }
            }
        } else if report.metrics.hrv == nil {
            out.append(Insight(id: "nohrv", title: "Keine HRV-Daten",
                               message: "Trage die Apple Watch nachts, damit Recovery berechnet werden kann.",
                               kind: .neutral))
        } else {
            out.append(Insight(id: "calibrating", title: "Kalibrierung",
                               message: "Recovery braucht mindestens \(RecoveryEngine.minimumBaselineNights) Nächte mit HRV-Daten als Baseline.",
                               kind: .neutral))
        }

        if let sleep = report.sleep {
            if sleep.need.debt >= 3600 {
                out.append(Insight(id: "debt", title: "Schlafschuld",
                                   message: "Etwa \(Int((sleep.need.debt / 60).rounded())) min Schlafschuld aus den letzten Nächten.",
                                   kind: .warning))
            }
            if let consistency = sleep.consistency, consistency < 50 {
                out.append(Insight(id: "consistency", title: "Unregelmäßiger Rhythmus",
                                   message: "Bett- und Aufstehzeiten schwanken stark. Feste Zeiten verbessern Schlafqualität und HRV.",
                                   kind: .warning))
            }
            if sleep.performance >= 0.95 {
                out.append(Insight(id: "sleepgood", title: "Schlafbedarf gedeckt",
                                   message: "Du hast \(Int((sleep.performance * 100).rounded())) % deines Schlafbedarfs erreicht.",
                                   kind: .positive))
            }
        }

        if let load = report.load, let ratio = load.ratio {
            if ratio > 1.5 {
                out.append(Insight(id: "acwr", title: "Belastungsspitze",
                                   message: String(format: "Akute Last ist %.1f× deiner chronischen Last – erhöhtes Überlastungsrisiko.", ratio),
                                   kind: .warning))
            } else if ratio < 0.8 && load.chronic > 20 {
                out.append(Insight(id: "acwr", title: "Belastung rückläufig",
                                   message: "Deine Trainingslast sinkt unter dein gewohntes Niveau.",
                                   kind: .neutral))
            }
        }

        return out
    }
}
