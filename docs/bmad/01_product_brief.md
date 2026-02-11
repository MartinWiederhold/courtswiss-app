# Product Brief – CourtSwiss (Interclub Tennis)

## 1. Produktvision
CourtSwiss ist eine mobile App für Tennis-Interclub-Teams in der Schweiz, die Captains und Spieler:innen den gesamten Matchday-Workflow abnimmt: Verfügbarkeit, Aufstellung, Ersatzspieler, Fahrgemeinschaften und gemeinsame Ausgaben – alles an einem Ort, einfach und reglement-konform.

Ziel ist es, den administrativen Aufwand für Captains massiv zu reduzieren und gleichzeitig die Kommunikation im Team transparenter und stressfreier zu machen.

## 2. Zielgruppe
### Primäre Zielgruppe
- Interclub-Captains (Herren, Damen, Senioren)
- Ligen: Aktive, 35+, 45+, 55+, regionale Ligen

### Sekundäre Zielgruppe
- Interclub-Spieler:innen
- Vereinsverantwortliche (optional später)

## 3. Problemstellung (Pain Points)
- Verfügbarkeiten werden über WhatsApp, Doodle oder Excel gesammelt
- Aufstellungen werden manuell erstellt und sind fehleranfällig
- Ersatzspieler müssen einzeln angeschrieben werden
- Fahrgemeinschaften und Treffpunkte sind unübersichtlich
- Essens- und Spesenabrechnungen laufen chaotisch über Chat oder Twint
- Keine zentrale, nachvollziehbare Übersicht pro Begegnung

## 4. Kernlösung
CourtSwiss bietet pro Begegnung einen strukturierten Matchday-Bereich mit:
- Team-Verfügbarkeiten
- Automatischer Aufstellung nach Klassierung
- Dynamischer Ersatzspieler-Kette
- Fahrgemeinschafts-Organisation
- Essen-Zusage (ja/nein)
- Spesen-Split mit Beleg-Upload

## 5. Hauptfeatures (MVP)
### Team & Rollen
- Team erstellen (z. B. „Herren 3. Liga")
- Captain-Rolle mit erweiterten Rechten
- Spieler mit Klassierung (R9–N1)

### Begegnung (Fixture)
- Gegner, Datum, Ort
- Verfügbarkeit: Ja / Nein / Vielleicht
- Übersicht wer Zeit hat

### Aufstellung
- Automatische Einzel-Aufstellung nach Klassierung
- Ersatzspieler-Liste automatisch generiert
- Manuelle Anpassung durch Captain möglich
- Warnhinweis bei Regelverstössen (z. B. falsche Reihenfolge)

### Ersatzspieler-Logik
- Absage → nächster Ersatz wird automatisch angefragt
- Push-Benachrichtigung für Zusage / Absage
- Automatisches Nachrücken

### Fahrgemeinschaften
- Fahrer definiert Auto, Sitzplätze, Treffpunkt
- Spieler können beitreten oder absagen
- Status „voll"

### Essen & Spesen
- Essen-Zusage (ja/nein)
- Captain lädt Beleg hoch
- Automatische Aufteilung der Kosten
- Status „bezahlt / offen"

## 6. Nicht-Ziele (bewusst ausgeschlossen im MVP)
- Kein offizieller Spielbericht / Resultatmeldung an Swiss Tennis
- Keine automatische Synchronisation mit myTennis
- Keine Turnier- oder Trainingsplanung
- Keine Zahlungsabwicklung (nur Tracking)

## 7. Erfolgskriterien (MVP)
- Captain kann eine Begegnung in < 3 Minuten planen
- 90 % der Teamkommunikation läuft über die App
- Aufstellung ohne manuelle Rechnerei
- Positive Rückmeldung von mind. 3 Interclub-Teams

## 8. Plattform & Tech (High-Level)
- Flutter (iOS & Android)
- Supabase (Auth, DB, Storage, Realtime)
- Push Notifications (FCM)
- Bestehende Supabase-Instanz wird **nicht verändert**, nur erweitert

## 9. Nächster Schritt
Detailliertes PRD mit User Flows, Datenmodell und Edge Cases.
