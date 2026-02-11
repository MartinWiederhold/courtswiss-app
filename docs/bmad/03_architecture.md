# Architektur & Datenmodell – CourtSwiss

## 1. Systemarchitektur (High Level)
CourtSwiss besteht aus einer Flutter Mobile App (iOS & Android) und einem bestehenden Supabase Backend, das um neue, klar abgegrenzte App-Tabellen erweitert wird.

Bestehende Supabase-Strukturen (Landingpage, Website, evtl. Analytics) bleiben vollständig unverändert.

## 2. Technologiestack
- Frontend: Flutter
- Backend: Supabase (Postgres, Auth, Storage, Realtime)
- Authentifizierung: Supabase Auth
- Push Notifications: Firebase Cloud Messaging (FCM)
- Entwicklungsumgebung: VS Code + Cursor

## 3. Datenbank-Strategie (Supabase-safe)
### Grundsatz
- Keine bestehenden Tabellen werden verändert
- Alle App-Tabellen erhalten das Prefix `ic_`
- Row Level Security (RLS) ist für alle App-Tabellen aktiv

### Trennung
- Website-Daten: unverändert
- App-Daten: ausschließlich `ic_*` Tabellen

## 4. Zentrale Entitäten (konzeptionell)

### ic_profiles
- Referenziert auth.users.id
- Anzeigename, optional Telefon
- Wird ausschließlich von der App genutzt

### ic_teams
- Teamname (z. B. Herren 3. Liga)
- Saison
- Kategorie
- captain_user_id

### ic_team_members
- team_id
- user_id
- Rolle (captain | member)
- Klassierung (R9–N1)
- Ranking-Wert (optional)

### ic_fixtures
- team_id
- Gegner
- Datum / Uhrzeit
- Ort
- Status

### ic_availability
- fixture_id
- user_id
- Status (yes | no | maybe)

### ic_lineups
- fixture_id
- Typ (singles | doubles)
- Finalisiert (boolean)

### ic_lineup_slots
- lineup_id
- Position (1..n)
- user_id (nullable)
- is_reserve
- reserve_order

### ic_carpools
- fixture_id
- driver_user_id
- seats_total
- meeting_point
- meeting_time

### ic_carpool_members
- carpool_id
- user_id
- Status

### ic_expenses
- fixture_id
- created_by
- total_amount
- receipt_url

### ic_expense_participants
- expense_id
- user_id
- share_amount
- paid

## 5. Zugriff & Sicherheit (RLS-Prinzip)
- Team-Mitglieder dürfen nur Daten ihres Teams sehen
- Nur Captains dürfen:
  - Aufstellungen finalisieren
  - Spesen erstellen
- Storage-Zugriffe (Belege) nur für Team-Mitglieder

## 6. Business-Logik-Verteilung
### Client (Flutter)
- UI
- Verfügbarkeiten
- Auto-Aufstellung
- Manuelle Anpassungen
- Offline-Lesezustand

### Server (Supabase / später Edge Functions)
- Ersatzspieler-Ketten
- Push-Trigger
- Kritische Statuswechsel

## 7. Erweiterbarkeit
- Doppel-Aufstellungen
- Swiss Tennis Sync
- Statistiken
- Mehrere Saisons pro Team
