# Testplan – CourtSwiss

> Letzte Aktualisierung: 12. Februar 2026

---

## 1. Teststrategie

### 1.1 Unit Tests (Pure Dart)
- Reine Logik-Tests ohne Flutter-Widget-Abhängigkeit
- Laufen mit `flutter test` (oder `dart test`)
- Fokus: Parsing, Berechnungen, Zustandstransformationen

### 1.2 Widget Tests (Flutter UI)
- Rendern einzelner Widgets/Screens im Test-Harness
- **Status: Placeholder** – nur Default-Counter-Test vorhanden (`widget_test.dart`)
- **TODO**: Echte Widget-Tests für kritische Screens (MatchDetail, TeamDetail, EventInbox)

### 1.3 Integration Tests (E2E, manuell)
- Vollständige Flows manuell auf Gerät/Simulator
- Kein automatisiertes E2E-Framework eingerichtet
- **TODO**: Flutter Integration Tests oder Patrol für kritische Flows

### 1.4 Manual QA
- Gerätespezifische Tests (Android / iOS Simulator)
- Push-Empfang auf Android verifizieren
- iOS: App-Start ohne Crash (kein Push konfiguriert)

---

## 2. Vorhandene automatisierte Tests

### Ausführung

```bash
# Alle Tests
flutter test

# Einzelne Suite
flutter test test/lineup_reorder_test.dart

# Statische Analyse
flutter analyze
```

### Test-Suites (test/)

| Datei | Zweck | Tests |
|-------|-------|-------|
| `lineup_reorder_test.dart` | `applyReorder`, `computeMoveSteps`, `moveStepToRpcParams` – Off-by-one, Drag Up/Down, No-op, Cross-Boundary, Immutability, End-to-End Pipeline | ~25 |
| `lineup_rules_test.dart` | `detectLineupViolations` – Missing Starter, Duplicate Player, Ranking Order, Combined Violations, Missing Ranking Data, Edge Cases | ~12 |
| `sub_request_timeout_test.dart` | `parseExpiresAt`, `isRequestExpired`, `isRequestActionable`, `expiresInLabel` – Parsing, Expiry-Status, Countdown-Labels | ~24 |
| `carpool_passenger_test.dart` | `CarpoolPassenger.fromMap` – DB Column Names, Legacy Alias, Edge Cases | ~6 |
| `dinner_rsvp_test.dart` | `DinnerRsvp.fromMap` – Alle Felder, optionale Felder, Defaults | ~6 |
| `expense_split_test.dart` | `ExpenseShare.fromMap` + Expense-Split-Logik – is_paid, paid_at, Split-Berechnung | ~8 |
| `widget_test.dart` | Default Flutter Counter Widget-Test (**Placeholder**, nicht aussagekräftig) | 1 |

**Gesamt: ~82 echte Unit-Tests** über 6 Suites.

### widget_test.dart

Der Default-Widget-Test (`widget_test.dart`) ist der automatisch generierte Counter-Test von `flutter create`. Er testet nicht die App-Funktionalität und dient nur als Platzhalter. Geplant: Ersetzen durch echte Widget-Tests für kritische Screens (MatchDetail, TeamDetail, EventInbox).

---

## 3. Test-Scope pro Domain

### 3.1 Auth & Profile

| Art | Status | Details |
|-----|--------|---------|
| Unit | – | Keine testbare Logik extrahiert |
| Widget | ❌ TODO | AuthScreen, AuthGate |
| Manual | ✅ | Anonymous Login, Magic Link, Session Restore |

### 3.2 Teams & Invites

| Art | Status | Details |
|-----|--------|---------|
| Unit | ❌ TODO | Team-Erstellung, Invite-Token-Parsing |
| Widget | ❌ TODO | TeamsScreen, TeamDetailScreen |
| Manual | ✅ | CRUD, Invite-Link, Swipe-to-Delete, sport_key, "Ich spiele selbst" Toggle |

### 3.3 Matches & Availability

| Art | Status | Details |
|-----|--------|---------|
| Unit | ❌ TODO | – |
| Widget | ❌ TODO | CreateMatchScreen, Availability Buttons |
| Manual | ✅ | Erstellen, yes/no/maybe, Captain-Übersicht |

### 3.4 Lineup

| Art | Status | Details |
|-----|--------|---------|
| Unit | ✅ | `lineup_reorder_test.dart` – applyReorder, computeMoveSteps, moveStepToRpcParams |
| Unit | ✅ | `lineup_rules_test.dart` – detectLineupViolations (Ranking, Missing, Duplicate) |
| Widget | ❌ TODO | LineupReorderList, Violation Banner |
| Manual | ✅ | Generate, Publish, Drag & Drop, Reorder Persist + Rollback, Violation Banner |

### 3.5 Ersatzanfragen (Sub-Requests)

| Art | Status | Details |
|-----|--------|---------|
| Unit | ✅ | `sub_request_timeout_test.dart` – parseExpiresAt, isRequestExpired, isRequestActionable, expiresInLabel |
| Widget | ❌ TODO | Sub-Request UI Cards, Accept/Decline Buttons |
| Manual | ✅ | Create, Accept/Decline, Timeout-Anzeige, expireStale on-load |

### 3.6 Fahrgemeinschaften (Carpool)

| Art | Status | Details |
|-----|--------|---------|
| Unit | ✅ | `carpool_passenger_test.dart` – CarpoolPassenger.fromMap Parsing |
| Widget | ❌ TODO | Carpool Section in MatchDetail |
| Manual | ✅ | Create Offer, Join/Leave, Delete, Multi-Offer, Persistenz |

### 3.7 Essen (Dinner)

| Art | Status | Details |
|-----|--------|---------|
| Unit | ✅ | `dinner_rsvp_test.dart` – DinnerRsvp.fromMap Parsing |
| Widget | ❌ TODO | Dinner RSVP Buttons |
| Manual | ✅ | yes/no/maybe, Note, Upsert |

### 3.8 Spesen (Expenses)

| Art | Status | Details |
|-----|--------|---------|
| Unit | ✅ | `expense_split_test.dart` – ExpenseShare.fromMap, Split-Logik, is_paid/paid_at |
| Widget | ❌ TODO | Expense Section, Share-Paid-Toggle |
| Manual | ✅ | Create Expense, Equal Split, is_paid Toggle, Payer auto-paid, Delete |

### 3.9 Events & Inbox

| Art | Status | Details |
|-----|--------|---------|
| Unit | ❌ TODO | Event-Payload-Parsing |
| Widget | ❌ TODO | EventInboxScreen, Unread-Badge |
| Manual | ✅ | Events sichtbar, Read-Tracking, Badge, Team-Filter, Navigation zu Match |

### 3.10 Push-Pipeline

| Art | Status | Details |
|-----|--------|---------|
| Unit | ❌ TODO | – |
| Manual | ✅ | Token-Registration (Android) ✅, Delivery-Fanout (DB) ✅ |
| Offen | ❌ | Push-Send Worker nicht implementiert → Deliveries bleiben `pending` |
| Offen | ❌ | iOS Push deaktiviert (kein APNs Key / GoogleService-Info.plist) |

---

## 4. DB-Level Tests (manuell via SQL Editor)

### T-DB-01: Team Creation

**Steps:**
1. INSERT in cs_teams mit name, season_year, sport_key, created_by
2. Prüfe cs_team_members Eintrag

**Expected:**
- cs_teams-Row mit korrektem name, season_year, sport_key, created_by
- cs_team_members-Row mit team_id, user_id=auth.uid(), role='captain'
- RLS: Anderer User ohne Membership kann Team nicht sehen

### T-DB-02: Match + Availability

**Steps:**
1. INSERT in cs_matches mit team_id, opponent, match_at
2. UPSERT in cs_match_availability mit status='yes', dann status='no'

**Expected:**
- Availability: UNIQUE (match_id, user_id), Status wird überschrieben, updated_at aktualisiert

### T-DB-03: Lineup Publish + Event-Trigger

**Steps:**
1. `generate_lineup` RPC → Draft
2. `publish_lineup` RPC

**Expected:**
- cs_match_lineups.status = 'published'
- cs_events-Row: event_type='lineup_published'
- cs_event_deliveries-Rows für alle Team-Mitglieder (außer Captain)

### T-DB-04: Delivery Fanout

**Steps:**
1. INSERT in cs_events (direkt oder via Trigger)

**Expected:**
- cs_event_deliveries: 1 Row pro Empfänger, channel='push'
- status='pending' (Push-Prefs aktiv) oder 'skipped' (deaktiviert)
- Kein Delivery für created_by

### T-DB-05: Sub-Request Create + Expire

**Steps:**
1. `cs_create_sub_request` RPC → pending Request mit expires_at
2. Warte oder setze expires_at in die Vergangenheit
3. `cs_expire_sub_requests()` aufrufen

**Expected:**
- Request status='expired', responded_at gesetzt
- `cs_expire_sub_requests()` ist idempotent (mehrfacher Aufruf ändert nichts)

### T-DB-06: Device Token Upsert + Reassignment

**Steps:**
1. `cs_upsert_device_token` mit platform='android', token, device_id
2. Erneuter Aufruf mit neuem token, gleichem device_id → Update
3. Anderer User mit gleichem token → ALTER Row gelöscht, neuer Row erstellt

**Expected:**
- UNIQUE (user_id, device_id)
- Stale Tokens (gleicher token, anderer user) werden bereinigt

---

## 5. Integration Tests (Manual QA Flows)

### T-INT-01: Vollständiger Team-Flow
1. Team erstellen (Name, Saison, Sportart, "Ich spiele selbst" Toggle)
2. Invite-Link generieren + öffnen → Team beitreten
3. ClaimScreen → Spieler-Profil claimen

### T-INT-02: Match + Lineup + Reorder
1. Captain: Match erstellen
2. Spieler: Availability = 'yes'
3. Captain: Lineup generieren (Draft)
4. Captain: Drag & Drop Reorder → prüfe Persist + Rollback bei Fehler
5. Captain: Lineup publishen → Event in Inbox

### T-INT-03: Absage + Auto-Promotion + Sub-Request
1. Starter: Availability = 'no' → Auto-Promotion
2. Captain: Sub-Request erstellen → pending mit expires_at
3. Ersatz: Accept → Lineup-Slot aktualisiert
4. Oder: Decline → Captain kann erneut anfragen
5. Oder: Timeout → Request expired, nächster Kandidat

### T-INT-04: Carpool + Dinner + Expenses
1. Driver: Carpool-Angebot erstellen
2. Spieler: Join/Leave
3. Spieler: Dinner RSVP = 'yes'
4. Captain: Expense erstellen → Split nur unter Dinner-"yes"
5. Spieler: Share als bezahlt markieren

### T-INT-05: Event Inbox + Push
1. Event erzeugen (via Lineup Publish)
2. EventInboxScreen: Event sichtbar, Unread-Badge korrekt
3. Tap → cs_event_reads erzeugt
4. Android: Push-Empfang prüfen (Firebase Console Test-Nachricht)

### T-INT-06: Token Re-Assignment
1. User A: App starten → Token registriert
2. User A: Magic-Link-Login → neue user_id
3. PushService.onAuthStateChange → Token unter neuer user_id

---

## 6. Testdaten (Seed)

Es existieren keine separaten Seed-Dateien. Testdaten werden manuell über die App-UI oder SQL Editor erstellt.

### Minimaler Seed (SQL)

```sql
-- 1. Team
INSERT INTO cs_teams (id, name, season_year, sport_key, created_by)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'TC Muster Herren 3. Liga',
  2026,
  'tennis',
  '<captain_user_id>'  -- ersetzen mit echter UUID aus auth.users
);

-- 2. Captain als Team-Member
INSERT INTO cs_team_members (team_id, user_id, role)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  '<captain_user_id>',
  'captain'
);

-- 3. Zweites Team-Mitglied
INSERT INTO cs_team_members (team_id, user_id, role)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  '<member_user_id>',
  'member'
);

-- 4. Spieler-Slots (für Lineup)
INSERT INTO cs_team_players (team_id, first_name, last_name, ranking, user_id)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Max',   'Muster',  3, '<captain_user_id>'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Anna',  'Beispiel', 5, '<member_user_id>');

-- 5. Match
INSERT INTO cs_matches (id, team_id, opponent, match_at, is_home, created_by)
VALUES (
  'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'TC Gegner',
  now() + interval '7 days',
  true,
  '<captain_user_id>'
);
```

> **Hinweis:** `<captain_user_id>` und `<member_user_id>` durch echte UUIDs aus `auth.users` ersetzen. Am einfachsten: App starten → Anonymous Login → UUID aus Supabase Dashboard ablesen.

---

## 7. Regression Checklist (vor Release)

### Infrastruktur
- [ ] Bestehende Supabase-Website unverändert (keine fremden Tabellen geändert)
- [ ] App-Tabellen ausschließlich `cs_*`
- [ ] RLS aktiv auf allen cs_*-Tabellen
- [ ] Storage (Avatare) geschützt

### Auth
- [ ] Anonymous Auth funktioniert (App-Start ohne Login)
- [ ] Magic Link Login funktioniert

### Team
- [ ] Team erstellen (mit Sportart + "Ich spiele selbst" Toggle)
- [ ] Invite-Link generieren + akzeptieren
- [ ] Team löschen (Swipe-to-Delete + Confirm)

### Match & Lineup
- [ ] Match erstellen + Availability setzen
- [ ] Lineup generieren + publishen
- [ ] Drag & Drop Reorder (Captain only, draft only)
- [ ] Regelverstoss-Warnung (Ranking, Missing, Duplicate)
- [ ] Auto-Promotion bei Absage

### Ersatzanfragen
- [ ] Sub-Request erstellen → pending mit expires_at
- [ ] Accept/Decline funktioniert
- [ ] Timeout (30 min) → expired, kein Accept mehr möglich
- [ ] expireStale on-load funktioniert

### Carpool, Dinner, Expenses
- [ ] Carpool: Create/Join/Leave/Delete
- [ ] Dinner: yes/no/maybe RSVP
- [ ] Expense: Create, Equal Split (nur Dinner "yes"), is_paid Toggle

### Events & Push
- [ ] Events werden in cs_events erzeugt (Trigger)
- [ ] Deliveries werden in cs_event_deliveries erzeugt (Fanout)
- [ ] EventInboxScreen zeigt Events, Unread-Badge korrekt
- [ ] Android: FCM Token registriert
- [ ] iOS: App startet ohne Crash

### Tests
- [ ] `flutter test` – alle Tests grün
- [ ] `flutter analyze` – keine Errors

---

## 8. Test Coverage Status (Feb 2026)

| Bereich | Unit Tests | Manual QA | Abdeckung |
|---------|:---:|:---:|:---:|
| Auth (Anonymous + Magic Link) | – | ✅ | ~70% |
| Teams + Invites + sport_key | – | ✅ | ~80% |
| Matches + Availability | – | ✅ | ~80% |
| Lineup (Generate, Publish) | – | ✅ | ~80% |
| Lineup Reorder (Drag & Drop) | ✅ ~25 Tests | ✅ | ~90% |
| Lineup Rules (Violations) | ✅ ~12 Tests | ✅ | ~90% |
| Sub-Request Timeout | ✅ ~24 Tests | ✅ | ~85% |
| Ersatzkette (Auto-Promotion) | – | ✅ | ~70% |
| Carpool (Parsing) | ✅ ~6 Tests | ✅ | ~75% |
| Dinner (Parsing) | ✅ ~6 Tests | ✅ | ~75% |
| Expenses (Parsing + Split) | ✅ ~8 Tests | ✅ | ~80% |
| Event-System (cs_events) | – | ✅ | ~60% |
| Push-Pipeline (Token) | – | ✅ | ~60% |
| Push-Send (Edge Worker) | – | ❌ | 0% (nicht impl.) |
| iOS Push | – | ❌ | 0% (out of scope) |
| Player Claim | – | ✅ | ~70% |
| Avatar Upload | – | ✅ | ~60% |
| **Gesamt** | **~82 Tests** | **~75%** | **~70%** |

---

## 9. Offene Lücken & TODOs

| # | Bereich | Status | Nächster Schritt |
|---|---------|--------|------------------|
| 1 | Widget Tests | ❌ Nicht vorhanden | Echte Widget-Tests für MatchDetailScreen, TeamDetailScreen, EventInboxScreen |
| 2 | Integration Tests (automatisiert) | ❌ Nicht vorhanden | Flutter Integration Tests oder Patrol für kritische E2E Flows |
| 3 | CI/CD Pipeline | ❌ Nicht eingerichtet | GitHub Actions: `flutter test` + `flutter analyze` auf PR |
| 4 | Service-Tests | ❌ TODO | Unit-Tests für TeamService, MatchService, LineupService (mit Mock Supabase Client) |
| 5 | DB-Trigger-Tests | ❌ TODO | pgTAP oder SQL-Skripte für Event-Trigger, Fanout, Auto-Promotion |
| 6 | Push-Send Worker | ❌ Nicht implementiert | Edge Function + Tests für Delivery Processing |
| 7 | iOS Push | ❌ Out of Scope | APNs Key + GoogleService-Info.plist konfigurieren |
| 8 | Offline Support | ❌ Nicht implementiert | Kein lokaler Cache, kein Test nötig |
| 9 | Load / Performance | ❌ Nicht geplant | Keine Benchmarks |
