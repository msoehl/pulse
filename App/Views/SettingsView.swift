import SwiftUI
import HealthCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = UserProfile()
    @State private var overrideMaxHR = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    Stepper("Alter: \(draft.age.map { "\($0)" } ?? "–")", value: Binding(
                        get: { draft.age ?? 30 },
                        set: { draft.age = $0 }
                    ), in: 12...99)
                    Picker("Geschlecht", selection: $draft.sex) {
                        Text("Männlich").tag(BiologicalSex.male)
                        Text("Weiblich").tag(BiologicalSex.female)
                        Text("Keine Angabe").tag(BiologicalSex.unknown)
                    }
                }

                Section {
                    Toggle("Max. Herzfrequenz manuell", isOn: $overrideMaxHR)
                    if overrideMaxHR {
                        Stepper("Max. HF: \(Int(draft.maxHROverride ?? 190)) bpm", value: Binding(
                            get: { draft.maxHROverride ?? 190 },
                            set: { draft.maxHROverride = $0 }
                        ), in: 140...220)
                    } else {
                        LabeledContent("Max. HF (geschätzt)", value: "\(Int(draft.maxHR)) bpm")
                    }
                } header: {
                    Text("Herzfrequenz")
                } footer: {
                    Text("Ohne Angabe: 208 − 0,7 × Alter (Tanaka). Ein gemessener Wert aus einem Belastungstest ist genauer.")
                }

                Section {
                    Stepper(String(format: "Basis-Schlafbedarf: %.1f h", draft.sleepNeedHours),
                            value: $draft.sleepNeedHours, in: 6...10, step: 0.25)
                } header: {
                    Text("Schlaf")
                }

                Section("So wird gerechnet") {
                    explanation("Recovery", "HRV (45 %), Ruhepuls (25 %), Schlaf (20 %) und Atemfrequenz (10 %) im Vergleich zu deiner 30-Tage-Baseline. Grün ≥ 67 %, Gelb ≥ 34 %.")
                    explanation("Belastung", "Banister-TRIMP aus allen Herzfrequenz-Messungen des Tages, logarithmisch auf 0–21 skaliert.")
                    explanation("Schlafbedarf", "Basisbedarf + Zuschlag für hohe Belastung am Vortag + Anteil der Schlafschuld der letzten 3 Nächte.")
                    explanation("Trainingslast", "Exponentiell gewichtete Last über 7 Tage (akut) und 42 Tage (chronisch).")
                }

                Section {
                    Button("Alle Werte neu berechnen") {
                        Task { await model.reloadFromScratch() }
                        dismiss()
                    }
                    if let updated = model.lastUpdated {
                        LabeledContent("Zuletzt aktualisiert", value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                } footer: {
                    Text("Pulse liest nur aus Apple Health und speichert nichts außerhalb des Geräts. Keine medizinische Diagnose.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                draft = model.profile
                overrideMaxHR = model.profile.maxHROverride != nil
                loaded = true
            }
        }
    }

    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func save() {
        var profile = draft
        if !overrideMaxHR { profile.maxHROverride = nil }
        let changed = profile != model.profile
        model.profile = profile
        dismiss()
        if changed {
            // Strain depends on max HR and sex, so cached TRIMP values must be rebuilt.
            Task { await model.reloadFromScratch() }
        }
    }
}
