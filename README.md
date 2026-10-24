# Pulse

Persönliche iOS-App, die Apple-Health-Daten auswertet – ähnlich WHOOP/Bevel, aber ohne Abo und ohne eigene Hardware.
Grundlage sind die Daten, die Apple Watch und iPhone ohnehin in Apple Health schreiben.

## Funktionen

| Bereich | Inhalt |
|---|---|
| **Übersicht** | Recovery (0–100 %), Belastung (0–21), Schlaf-Performance, Tagesziel Belastung, Vitalwerte vs. 30-Tage-Schnitt, Insights, 7-Tage-Recovery |
| **Schlaf** | Hypnogramm (Wach/REM/Kern/Tief), Phasenverteilung, Effizienz, Konsistenz, Schlafbedarf (Basis + Belastung + Schlafschuld), 14-Nächte-Verlauf |
| **Belastung** | Strain aus Herzfrequenz (Banister-TRIMP), Zeit in HF-Zonen, Workouts, akute/chronische Trainingslast + ACWR, 14-Tage-Verlauf |
| **Trends** | 11 Metriken (HRV, Ruhepuls, VO₂max, Atemfrequenz, SpO₂, Hauttemperatur, Gewicht, Schritte, …) über 14–120 Tage mit 7-Tage-Schnitt, Baseline-Band, Steigung und Korrelationen zur Recovery |

## Datenquelle

Mit einer kostenlosen Apple-ID entfernt das Signieren beim Sideloading die HealthKit-Berechtigung. Pulse liest dann den **Health-Export**:

1. Health-App › Profilbild › „Alle Gesundheitsdaten exportieren“.
2. Im Teilen-Menü „Pulse“ wählen, oder „In Dateien sichern“ und in Pulse über „Export-Datei wählen“ öffnen.
3. Pulse liest die letzten 120 Tage und speichert das Ergebnis auf dem Gerät.

Laufend aktuell hält es der Kurzbefehl **Pulse Sync**: Die Kurzbefehle-App darf Apple Health lesen, sammelt die Werte der letzten 4 Tage und übergibt sie über die Pulse-Aktion „Health-Daten an Pulse übergeben“. Eine Automation („Pulse wird geöffnet“) startet ihn automatisch. Anleitung in der App unter Einstellungen › Automatisch synchronisieren.

Mit bezahltem Developer-Account (HealthKit-Berechtigung bleibt erhalten) liest Pulse automatisch live aus Apple Health.

## Aufbau

```
Packages/HealthCore/   Reine Swift-Logik (Scores, Baselines, Trends) + Unit-Tests
App/                   SwiftUI-App + HealthKit-Anbindung
project.yml            XcodeGen-Projektdefinition (das .xcodeproj wird in CI generiert)
.github/workflows/     macOS-Build → unsignierte Pulse.ipa
```

### Algorithmen (Kurzfassung)

- **Recovery**: z-Scores gegen die eigene 30-Tage-Baseline – ln(HRV) 45 %, Ruhepuls 25 %, Schlaf-Performance 20 %, Atemfrequenz 10 % – logistisch auf 1–99 % abgebildet. Braucht ≥ 4 Nächte mit HRV.
- **Belastung**: Banister-TRIMP über alle Herzfrequenz-Samples des Tages (Herzfrequenzreserve ≥ 30 %), skaliert `21 · (1 − e^(−TRIMP/120))`.
- **Schlafbedarf**: Basis (Einstellung) + bis 45 min bei Belastung > 10 am Vortag + gewichtete Schlafschuld der letzten 3 Nächte (max. 2 h).
- **Trainingslast**: exponentiell gewichtete TRIMP über 7 Tage (akut) und 42 Tage (chronisch).

Alle Konstanten stehen in `Packages/HealthCore/Sources/HealthCore/`.

## Bauen ohne Mac

1. Repo auf GitHub pushen (privat ist ok; macOS-Minuten zählen bei privaten Repos 10-fach gegen das Freikontingent).
2. Der Workflow **Build IPA** läuft bei jedem Push auf `main` (oder manuell unter *Actions › Build IPA › Run workflow*).
3. Unter dem Workflow-Lauf das Artefakt **Pulse-ipa** herunterladen und entpacken → `Pulse.ipa`.

## Installieren und aktualisieren ohne PC (SideStore)

Jeder Push auf `main` erzeugt ein GitHub-Release mit `Pulse.ipa` und einer SideStore-Quelle:

```
https://github.com/msoehl/pulse/releases/latest/download/source.json
```

1. SideStore einmalig nach https://docs.sidestore.io einrichten (dafür einmal ein PC für die Pairing-Datei).
2. In SideStore › *Sources* › **+** die URL oben hinzufügen und Pulse installieren.
3. Neue Versionen erscheinen in SideStore unter *Updates*.
4. Die 7-Tage-Signatur erneuert SideStore auf dem iPhone selbst; automatisch per Kurzbefehle-Automation „SideStore › Alle Apps aktualisieren“ (z. B. täglich).

## Installieren (Sideload)

Mit **Sideloadly** (Windows):

1. iTunes und iCloud in der Variante von apple.com installieren (nicht Microsoft Store), iPhone per USB verbinden und vertrauen.
2. Sideloadly öffnen, `Pulse.ipa` hineinziehen, Apple-ID eintragen, *Start*.
3. Auf dem iPhone: *Einstellungen › Allgemein › VPN & Geräteverwaltung* → Entwickler-Profil vertrauen.
4. Ab iOS 16: *Einstellungen › Datenschutz & Sicherheit › Entwicklermodus* aktivieren.
5. App öffnen und Health-Zugriff erlauben.

Mit kostenloser Apple-ID läuft die Signatur nach **7 Tagen** ab. Dann erneut signieren (Sideloadly-Autorefresh oder SideStore/AltStore).

Mit kostenloser Apple-ID fehlt danach die HealthKit-Berechtigung – das ist erwartet, Pulse nutzt dann den Health-Export (siehe oben).

## Tests lokal

Die Logik in `HealthCore` ist plattformunabhängig. Mit installiertem Swift-Toolchain (auch Windows):

```bash
swift test --package-path Packages/HealthCore
```

## Hinweis

Keine Medizinprodukt-Software. Werte sind Schätzungen und ersetzen keine ärztliche Diagnose.
