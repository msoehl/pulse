import SwiftUI
import UIKit
import HealthCore

/// Step-by-step setup of the "Pulse Sync" shortcut, which reads Apple Health on Pulse's behalf.
struct ShortcutGuideView: View {
    @State private var copied = false

    private struct Metric: Identifiable {
        let key: String
        let type: String
        var groupByDay = false
        var id: String { key }
    }

    private let metrics: [Metric] = [
        Metric(key: "hrv", type: "Herzfrequenzvariabilität"),
        Metric(key: "rhr", type: "Ruhepuls"),
        Metric(key: "hr", type: "Herzfrequenz"),
        Metric(key: "resp", type: "Atemfrequenz"),
        Metric(key: "spo2", type: "Blutsauerstoff"),
        Metric(key: "temp", type: "Handgelenktemperatur beim Schlafen"),
        Metric(key: "vo2", type: "VO₂ max"),
        Metric(key: "weight", type: "Gewicht"),
        Metric(key: "steps", type: "Schritte", groupByDay: true),
        Metric(key: "energy", type: "Aktive Energie", groupByDay: true),
    ]

    var body: some View {
        List {
            Section {
                Text("Pulse darf ohne Entwickler-Konto nicht selbst auf Apple Health zugreifen, die Kurzbefehle-App schon. Ein Kurzbefehl liest die Werte der letzten Tage und übergibt sie an Pulse – automatisch per Automation.")
                    .font(.subheadline)
            }

            Section("1 · Kurzbefehl anlegen") {
                step("Kurzbefehle-App › + › Name „Pulse Sync“.")
                step("Für jede Zeile unten die Aktion „Health-Beispiele suchen“ hinzufügen:")
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.type).font(.subheadline.weight(.semibold))
                        Text(metric.groupByDay
                             ? "Startdatum in den letzten 4 Tagen · Gruppieren nach: Tag"
                             : "Startdatum in den letzten 4 Tagen · Limit aus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schlafanalyse").font(.subheadline.weight(.semibold))
                    Text("Startdatum in den letzten 4 Tagen · Limit aus").font(.caption).foregroundStyle(.secondary)
                }
                step("Nicht benötigte Werte (z. B. VO₂ max, Gewicht) kannst du weglassen.")
            }

            Section("2 · Text-Aktion") {
                step("Aktion „Text“ hinzufügen und die Vorlage einfügen:")
                Button {
                    UIPasteboard.general.string = ShortcutPayload.template
                    copied = true
                } label: {
                    Label(copied ? "Vorlage kopiert" : "Vorlage kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                step("Unter jede Zeile „@….dates“ die passende Variable „Health-Beispiele“ setzen, antippen › Startdatum › Datumsformat „ISO 8601“ und „ISO 8601-Zeit einschließen“ aktivieren.")
                step("Unter jede Zeile „@….values“ dieselbe Variable › Wert.")
                step("Schlaf: @sleep.start = Startdatum, @sleep.end = Enddatum (beide ISO 8601), @sleep.values = Wert.")
                step("Zeilen für weggelassene Werte löschen.")
            }

            Section("3 · An Pulse übergeben") {
                step("Aktion „Health-Daten an Pulse übergeben“ (App Pulse) hinzufügen, Daten = Text.")
                step("Kurzbefehl einmal von Hand starten und den Health-Zugriff für Kurzbefehle erlauben. Pulse zeigt danach die übernommenen Werte.")
            }

            Section {
                step("Kurzbefehle › Automation › + › App › Pulse › „Wird geöffnet“ › Sofort ausführen › Pulse Sync.")
                step("Optional: zweite Automation „Tageszeit“, z. B. 9:00 täglich. Bei gesperrtem iPhone sind Health-Daten nicht lesbar – dann läuft sie erst beim nächsten Entsperren erfolgreich.")
            } header: {
                Text("4 · Automation")
            } footer: {
                Text("Die Werte erscheinen in der Health-Sprache deines iPhones; Pulse versteht deutsche und englische Bezeichnungen. Einheiten: kg, kcal, °C.")
            }
        }
        .navigationTitle("Kurzbefehl einrichten")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ text: String) -> some View {
        Text(text).font(.footnote)
    }
}
