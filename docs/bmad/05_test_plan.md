# Testplan – CourtSwiss (MVP)

## 1. Ziel
Sicherstellen, dass die MVP-Kernflows stabil funktionieren:
- Auth & Profil
- Team & Einladungen
- Fixtures & Verfügbarkeit
- Auto-Aufstellung & manuelle Anpassungen
- Ersatzspieler-Kette
- Fahrgemeinschaften
- Essen & Spesen

## 2. Testarten
### 2.1 Unit Tests (Dart)
- Klassierungs-Sortierung (N1..R9)
- Auto-Lineup Auswahl (Top N + Ersatzliste)
- Kosten-Split (Betrag / Teilnehmer)
- Validierungen (Pflichtfelder, Kapazitäten)

### 2.2 Widget Tests (Flutter UI)
- Login Screen Rendering
- Teamliste / Fixtureliste korrekt
- Verfügbarkeit Buttons (Ja/Nein/Vielleicht)
- Lineup Drag & Drop UI (falls umgesetzt)
- Expense Screen: Upload UI + Split Anzeige

### 2.3 Integration / E2E (manuell oder später automated)
- Login → Team beitreten → Fixture öffnen → Verfügbarkeit setzen
- Captain erstellt Fixture → Team sieht es
- Auto-Lineup → Save → Members sehen Auswahl
- Ersatzkette: Spieler sagt ab → Ersatz wird angefragt → Zusage → Lineup aktualisiert
- Carpool erstellen → Beitreten bis voll
- Essen RSVP → Expense erstellen → Shares → Paid markieren

## 3. Testdaten / Seed
- Mindestens 1 Team mit 12 Mitgliedern:
  - Verschiedene Klassierungen (z. B. R1, R3, R5, R7, R9)
- 2 Fixtures (eins kommende Woche, eins in 2 Tagen)
- Verfügbarkeiten: gemischt (yes/no/maybe)
- 2 Carpools mit unterschiedlichen Sitzplätzen
- 1 Expense (100 CHF) mit 6 Dinner-Teilnehmern

## 4. Akzeptanztests (Definition of Done)
### Auth
- Nutzer kann sich einloggen und bleibt eingeloggt
- Profil wird angelegt, falls nicht vorhanden

### Team
- Captain kann Team erstellen
- Invite-Link Flow funktioniert:
  - User ohne Account kann über Link Account erstellen und beitreten
  - Existing User kann direkt beitreten

### Fixture
- Captain kann Fixture erstellen
- Mitglieder sehen Fixture und Details

### Availability
- Member kann yes/no/maybe setzen
- Captain sieht Live-Übersicht

### Lineup
- Auto-Lineup füllt Slots korrekt
- Ersatzliste korrekt sortiert
- Captain kann manuell ändern
- Finalisierung sperrt automatische Änderungen

### Ersatzkette
- Absage löst Ersatz-Request aus
- Nur ein aktiver Request zur gleichen Zeit
- Nächster Ersatz wird nach Absage angefragt
- Zusage führt zu Nachrücken und Benachrichtigung

### Carpool
- Fahrer kann Carpool anlegen
- Mitglieder können beitreten
- Bei Vollstand kein weiterer Beitritt möglich

### Essen & Spesen
- Dinner RSVP sichtbar
- Captain kann Expense erstellen und Beleg hochladen
- Split korrekt (Gesamtbetrag / Teilnehmer)
- Paid Status pro Teilnehmer speicherbar

## 5. Regression Checklist (vor Release)
- Bestehende Supabase-Website unverändert: keine Tabellen/Views/Functions geändert
- App-Tabellen sind ausschließlich `ic_*`
- RLS ist aktiv und verhindert Zugriff teamfremder User
- Storage (Belege) ist geschützt (Team-Mitglieder only)
