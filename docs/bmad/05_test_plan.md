# Testplan – CourtSwiss

> Letzte Aktualisierung: Februar 2026

---

## 1. Test Strategy

### 1.1 Unit Tests (Dart)
- Klassierungs-Sortierung (N1..R9)
- Auto-Lineup Auswahl (Top N + Ersatzliste)
- Validierungen (Pflichtfelder)
- Event-Payload-Parsing (getMatchId, formatTitle, formatBody)

### 1.2 Widget Tests (Flutter UI)
- Login Screen Rendering
- Teamliste korrekt
- Match-Liste korrekt
- Verfügbarkeit Buttons (Ja / Nein / Vielleicht)
- EventInboxScreen: Event-Liste, Unread-Badge, Team-Filter
- NotificationSettingsScreen: Switches korrekt

### 1.3 Integration Tests (E2E, manuell)
- Login → Team erstellen → Spieler einladen → Match erstellen → Availability → Lineup publishen → Event in Inbox → Push auf Android
- Ersatzkette: Absage → Auto-Promotion → Event erzeugt → Delivery erzeugt

### 1.4 Manual QA
- Gerätespezifische Tests (Android / iOS)
- Push-Empfang auf Android verifizieren
- iOS: App-Start ohne Crash verifizieren (kein Push)

---

## 2. DB-Level Tests

### T-DB-01: Team Creation

**Preconditions:**
- Authentifizierter User (anonymous oder magic link)

**Steps:**
1. RPC oder INSERT in cs_teams mit name, season_year, created_by
2. Prüfe cs_team_members Eintrag

**Expected Result:**
- cs_teams-Row existiert mit korrektem name, season_year, created_by
- cs_team_members-Row existiert mit team_id, user_id=auth.uid(), role='captain'
- RLS: Anderer User ohne Membership kann Team nicht sehen

---

### T-DB-02: Match Creation

**Preconditions:**
- Team existiert (T-DB-01)
- User ist Captain des Teams

**Steps:**
1. INSERT in cs_matches mit team_id, opponent, match_at

**Expected Result:**
- cs_matches-Row existiert
- team_id referenziert korrektes Team
- Opponent und match_at korrekt gespeichert
- RLS: Nur Team-Mitglieder können Match sehen

---

### T-DB-03: Availability

**Preconditions:**
- Match existiert (T-DB-02)
- User ist Team-Mitglied

**Steps:**
1. UPSERT in cs_match_availability mit match_id, user_id, status='yes'
2. Erneutes UPSERT mit status='no'

**Expected Result:**
- cs_match_availability-Row existiert mit korrektem match_id und user_id
- UNIQUE Constraint auf (match_id, user_id) – kein Duplikat
- Status wird korrekt überschrieben (yes → no)
- updated_at wird aktualisiert

---

### T-DB-04: Lineup Publish

**Preconditions:**
- Match existiert mit mindestens 4 verfügbaren Spielern
- Lineup wurde via `generate_lineup` als Draft erstellt

**Steps:**
1. RPC `publish_lineup` mit match_id aufrufen

**Expected Result:**
- cs_match_lineups.status = 'published'
- cs_match_lineup_slots enthalten korrekte Positionen (Starter + Reserve)
- Trigger `trg_emit_lineup_published_event` feuert
- cs_events-Row mit event_type='lineup_published' existiert
- cs_event_deliveries-Rows für alle Team-Mitglieder erzeugt

---

### T-DB-05: Event Creation

**Preconditions:**
- Team mit mindestens 2 Mitgliedern
- Match mit published Lineup

**Steps:**
1. Lineup publishen (Trigger-basiert)
2. Oder: Spieler sagt ab → auto_handle_absence (Trigger-basiert)

**Expected Result:**
- cs_events-Row existiert
- team_id ist korrekt gesetzt
- match_id ist korrekt gesetzt
- event_type ist gesetzt ('lineup_published' | 'replacement_promoted' | 'no_reserve_available')
- created_by enthält den auslösenden User
- payload ist valides JSON mit mindestens team_id und match_id
- recipient_user_id ist NULL für Broadcasts, gesetzt für gezielte Events

---

### T-DB-06: Delivery Fanout

**Preconditions:**
- cs_events-Row wurde erzeugt (T-DB-05)
- Team hat mindestens 2 Mitglieder mit user_id in cs_team_members

**Steps:**
1. INSERT in cs_events (direkt oder via Trigger)

**Expected Result:**
- cs_event_deliveries-Rows erzeugt (1 pro Empfänger)
- user_id jeder Delivery ∈ cs_team_members.user_id für das Team
- channel = 'push'
- status = 'pending' (wenn Push-Prefs aktiv) oder 'skipped' (wenn deaktiviert)
- Kein Delivery für den Ersteller (created_by wird übersprungen)
- Kein Delivery für Nicht-Mitglieder
- UNIQUE auf (event_id, user_id, channel) – keine Duplikate

---

### T-DB-07: Device Token Registration

**Preconditions:**
- Authentifizierter User

**Steps:**
1. RPC `cs_upsert_device_token` mit platform='android', token='fcm_token_xxx', device_id='uuid-device-1'
2. Erneuter Aufruf mit neuem token aber gleichem device_id

**Expected Result:**
- cs_device_tokens-Row existiert mit user_id=auth.uid()
- token korrekt gespeichert
- device_id korrekt gespeichert
- enabled = true
- UNIQUE auf (user_id, device_id)
- Bei erneutem Aufruf: token wird aktualisiert (kein neuer Row)
- updated_at und last_seen_at aktualisiert

---

### T-DB-08: Token Reassignment bei Auth Change

**Preconditions:**
- User A hat Token registriert (T-DB-07)
- User B loggt sich auf dem gleichen Gerät ein

**Steps:**
1. User B ruft `cs_upsert_device_token` mit demselben token und/oder device_id auf

**Expected Result:**
- Alter Row von User A mit gleichem token wird gelöscht (DELETE WHERE token=X AND user_id≠B)
- Alter Row von User A mit gleichem device_id wird gelöscht (DELETE WHERE device_id=X AND user_id≠B)
- Neuer Row für User B wird erstellt
- Es gibt keinen Row mehr der token/device_id unter User A führt

---

### T-DB-09: Delivery Status Update

**Preconditions:**
- cs_event_deliveries-Row mit status='pending' existiert (T-DB-06)

**Steps:**
1. UPDATE status='sent', processed_at=now(), attempts=1
2. Oder: UPDATE status='failed', last_error='FCM error: invalid token', attempts=1

**Expected Result:**
- Bei Erfolg: status='sent', processed_at gesetzt, attempts=1
- Bei Fehler: status='failed', last_error enthält Fehlerbeschreibung, attempts hochgezählt
- processed_at ist nicht NULL nach Verarbeitung

> **Hinweis:** Aktuell wird kein Edge Worker ausgeführt. Deliveries bleiben auf status='pending'.

---

## 3. Android Push Tests

### T-PUSH-01: Android Token Registration

**Preconditions:**
- Android-Gerät mit installierbarer App
- Firebase-Projekt korrekt konfiguriert (google-services.json vorhanden)
- User eingeloggt (anonymous oder magic link)

**Steps:**
1. App starten
2. PushService.initPush() wird aufgerufen
3. FCM Token wird via FirebaseMessaging.instance.getToken() geholt

**Expected Result:**
- cs_device_tokens enthält Row mit user_id=aktueller User, platform='android'
- token ist nicht leer
- device_id ist stabile UUID aus SharedPreferences
- enabled = true
- Debug-Log zeigt: `PUSH_INIT userId=... tokenPrefix=...`

---

### T-PUSH-02: Delivery findet Token

**Preconditions:**
- User hat registrierten Token (T-PUSH-01)
- Event wird erzeugt (T-DB-05)
- Delivery mit status='pending' existiert (T-DB-06)

**Steps:**
1. SQL Query: `SELECT d.*, t.token FROM cs_event_deliveries d JOIN cs_device_tokens t ON t.user_id = d.user_id WHERE d.status = 'pending'`

**Expected Result:**
- JOIN liefert Ergebnis (Token gefunden für Delivery-User)
- t.token ist nicht NULL
- t.enabled = true
- t.user_id = d.user_id (kein Mismatch)

---

### T-PUSH-03: Delivery Status nach Push-Send

**Preconditions:**
- Edge Worker (oder manueller Test) verarbeitet pending Delivery

**Steps:**
1. Worker holt pending Deliveries
2. Joined mit cs_device_tokens
3. Sendet FCM HTTP v1 Request
4. Updated Delivery-Status

**Expected Result:**
- Bei Erfolg: status='sent', processed_at gesetzt
- Bei Fehler: status='failed', last_error enthält FCM Error, attempts++

> **Hinweis:** Edge Worker ist aktuell nicht produktiv. Dieser Test ist für die zukünftige Implementierung dokumentiert.

---

### T-PUSH-04: iOS wird übersprungen

**Preconditions:**
- iOS-Gerät oder Simulator
- App installiert

**Steps:**
1. App starten auf iOS
2. PushService.initPush() wird aufgerufen

**Expected Result:**
- Platform.isIOS Check verhindert FCM-Initialisierung
- Kein Token-Registration-Versuch
- Kein Eintrag in cs_device_tokens für iOS
- App stürzt nicht ab (kein Crash wegen fehlender GoogleService-Info.plist)
- Firebase.initializeApp() wird mit try/catch abgefangen

---

## 4. Integration Tests (Manual QA)

### T-INT-01: Vollständiger Team-Flow

**Steps:**
1. User A: Team erstellen (Name, Saison)
2. User A: Invite-Link generieren
3. User B: Invite-Link öffnen → Team beitreten
4. User B: ClaimScreen → Spieler-Profil claimen

**Expected Result:**
- cs_teams-Row existiert
- cs_team_members: 2 Rows (Captain + Member)
- cs_team_players.user_id gesetzt für User B
- Beide User sehen Team in TeamsScreen

---

### T-INT-02: Match + Availability + Lineup

**Steps:**
1. Captain: Match erstellen (Gegner, Datum)
2. Spieler A: Availability = 'yes'
3. Spieler B: Availability = 'yes'
4. Captain: Lineup generieren (Draft)
5. Captain: Lineup publishen

**Expected Result:**
- cs_matches-Row existiert
- cs_match_availability: 2 Rows
- cs_match_lineups.status = 'published'
- cs_match_lineup_slots: Starter + Reserve korrekt
- cs_events: Row mit event_type='lineup_published'
- cs_event_deliveries: Rows für alle Team-Mitglieder (außer Captain)
- EventInboxScreen: Event sichtbar für Spieler A und B

---

### T-INT-03: Absage + Auto-Promotion

**Steps:**
1. Spieler A (Starter): Availability = 'no'
2. Trigger `trg_availability_absence` feuert
3. `auto_handle_absence` RPC läuft

**Expected Result:**
- Spieler A wird aus cs_match_lineup_slots entfernt
- Nächster Ersatz rückt auf Starter-Position
- cs_lineup_events: Row mit event_type='auto_promotion'
- cs_events: Broadcast-Event + gezieltes Event an nachgerückten Spieler
- cs_event_deliveries: Rows für betroffene User
- EventInboxScreen: "Ersatz ist nachgerückt" Event sichtbar

---

### T-INT-04: Event Inbox + Read

**Steps:**
1. User öffnet EventInboxScreen
2. Unread-Events sind visuell hervorgehoben
3. User tappt auf Event

**Expected Result:**
- Unread-Badge (Glocke) zeigt korrekte Zahl
- cs_event_reads-Row wird bei Tap erzeugt
- Event wird als gelesen markiert (nicht mehr fett/hervorgehoben)
- Bei match_id: Navigation zu MatchDetailScreen
- Bei fehlendem Match: SnackBar "Match nicht verfügbar"

---

### T-INT-05: Android Push Empfang

**Steps:**
1. User B: App im Hintergrund auf Android-Gerät
2. User A (Captain): Lineup publishen
3. Event + Delivery werden erzeugt
4. Edge Worker sendet Push (wenn produktiv)

**Expected Result:**
- FCM Push-Notification wird auf Android-Gerät angezeigt
- Tap auf Notification: App öffnet MatchDetailScreen
- cs_event_deliveries.status = 'sent'

> **Hinweis:** Aktuell nur manuell testbar, da Edge Worker nicht produktiv ist. Push-Empfang kann via Firebase Console (Test-Nachricht) verifiziert werden.

---

### T-INT-06: Token Re-Assignment

**Steps:**
1. User A: App starten → Token registriert
2. User A: Magic-Link-Login (neue user_id)
3. PushService.onAuthStateChange feuert

**Expected Result:**
- cs_device_tokens: alter Row mit User-A-anonymous-uid gelöscht
- cs_device_tokens: neuer Row mit User-A-magic-link-uid erstellt
- Token und device_id bleiben gleich, nur user_id ändert sich

---

## 5. Known Gaps & Out of Scope

| Bereich | Status | Details |
|---------|--------|---------|
| Automatisierte Unit Tests | ❌ Nicht implementiert | Nur Default Flutter Widget-Test vorhanden |
| Automatisierte Widget Tests | ❌ Nicht implementiert | Keine Screen-Tests |
| CI/CD Pipeline | ❌ Nicht eingerichtet | Kein GitHub Actions / Codemagic Setup |
| Edge Worker (Push-Send) | ❌ Nicht produktiv | Deliveries bleiben auf 'pending' |
| iOS Push Notifications | ❌ Out of Scope | GoogleService-Info.plist fehlt, APNs Key nicht konfiguriert |
| Fahrgemeinschaften (Epic 7) | ❌ Nicht implementiert | Keine DB-Tabellen, kein UI |
| Essen & Spesen (Epic 8) | ❌ Nicht implementiert | Keine DB-Tabellen, kein UI |
| Offline Support | ❌ Nicht implementiert | Kein lokaler Cache |
| Load / Performance Tests | ❌ Nicht geplant | Keine Benchmarks |

---

## 6. Seed Data (Testdaten)

Minimale Seed-Daten für manuelle Tests:

```sql
-- 1. Team erstellen
INSERT INTO cs_teams (id, name, season_year, created_by)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'TC Muster Herren 3. Liga',
  2026,
  '<captain_user_id>'
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

-- 4. Match
INSERT INTO cs_matches (id, team_id, opponent, match_at, is_home, created_by)
VALUES (
  'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'TC Gegner',
  now() + interval '7 days',
  true,
  '<captain_user_id>'
);

-- 5. Event (manuell, normalerweise via Trigger)
INSERT INTO cs_events (id, team_id, match_id, event_type, title, body, payload, created_by)
VALUES (
  'cccccccc-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'bbbbbbbb-0000-0000-0000-000000000001',
  'lineup_published',
  'Aufstellung veröffentlicht',
  'Die Aufstellung für TC Gegner ist online.',
  '{"team_id":"aaaaaaaa-0000-0000-0000-000000000001","match_id":"bbbbbbbb-0000-0000-0000-000000000001"}'::jsonb,
  '<captain_user_id>'
);

-- 6. Delivery (wird normalerweise via Fanout-Trigger erzeugt)
INSERT INTO cs_event_deliveries (event_id, user_id, channel, status)
VALUES (
  'cccccccc-0000-0000-0000-000000000001',
  '<member_user_id>',
  'push',
  'pending'
);

-- 7. Device Token
INSERT INTO cs_device_tokens (user_id, platform, token, device_id, enabled)
VALUES (
  '<member_user_id>',
  'android',
  'fcm_test_token_abc123def456',
  'device-uuid-0001',
  true
);
```

> **Hinweis:** `<captain_user_id>` und `<member_user_id>` durch echte UUIDs aus auth.users ersetzen.

---

## 7. Regression Checklist (vor Release)

- [ ] Bestehende Supabase-Website unverändert: keine fremden Tabellen/Views/Functions geändert
- [ ] App-Tabellen sind ausschließlich `cs_*`
- [ ] RLS ist aktiv auf allen cs_*-Tabellen
- [ ] Storage (Avatare) ist geschützt (nur eigene Uploads)
- [ ] Anonymous Auth funktioniert (App-Start ohne Login)
- [ ] Magic Link Login funktioniert
- [ ] Team erstellen + Invite funktioniert
- [ ] Match + Availability + Lineup Flow funktioniert
- [ ] Auto-Promotion bei Absage funktioniert
- [ ] Events werden in cs_events erzeugt
- [ ] Deliveries werden in cs_event_deliveries erzeugt
- [ ] EventInboxScreen zeigt Events korrekt
- [ ] Android: FCM Token wird registriert
- [ ] Android: Push-Empfang funktioniert (Firebase Console Test)
- [ ] iOS: App startet ohne Crash (kein Push)

---

## 8. Test Coverage Status (Feb 2026)

| Bereich | Automatisiert | Manuell getestet | Abdeckung |
|---------|:---:|:---:|:---:|
| Auth (Anonymous + Magic Link) | ❌ | ✅ | ~70% |
| Team CRUD + Invite | ❌ | ✅ | ~80% |
| Match CRUD | ❌ | ✅ | ~80% |
| Availability | ❌ | ✅ | ~90% |
| Lineup (Generate, Publish) | ❌ | ✅ | ~80% |
| Auto-Promotion (Ersatzkette) | ❌ | ✅ | ~70% |
| Event-System (cs_events) | ❌ | ✅ | ~60% |
| Delivery Fanout | ❌ | ✅ | ~50% |
| Android Push (Token) | ❌ | ✅ | ~60% |
| iOS Push | ❌ | ❌ | 0% (Out of Scope) |
| Player Claim | ❌ | ✅ | ~70% |
| Avatar Upload | ❌ | ✅ | ~60% |
| Edge Worker | ❌ | ❌ | 0% (nicht implementiert) |
| **Gesamt** | **0%** | **~65%** | **~55%** |

> **Fazit:** Keine automatisierten Tests vorhanden. Gesamte Testabdeckung basiert auf manueller QA. Priorität für nächsten Sprint: Unit Tests für Event-Payload-Logik und DB-Trigger-Tests via pgTAP oder SQL-Skripte.
