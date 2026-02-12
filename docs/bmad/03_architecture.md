# Architektur & Datenmodell – CourtSwiss

> Letzte Aktualisierung: 12. Februar 2026

## 1. Systemarchitektur (High Level)

CourtSwiss besteht aus einer Flutter Mobile App (iOS & Android) und einem bestehenden Supabase Backend, das um neue, klar abgegrenzte App-Tabellen erweitert wird.

Bestehende Supabase-Strukturen (Landingpage, Website, evtl. Analytics) bleiben vollständig unverändert.

```
┌──────────────────────────────────────────────────────────────┐
│                     Flutter App (iOS/Android)                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐ │
│  │  Screens  │  │ Services │  │PushService│  │DeepLinkSvc  │ │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘  └──────┬──────┘ │
└───────┼──────────────┼──────────────┼───────────────┼────────┘
        │              │              │               │
        ▼              ▼              ▼               ▼
┌──────────────────────────────────────────────────────────────┐
│                   Supabase (Backend)                         │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌─────────────┐ │
│  │  Auth    │  │ Postgres │  │  Storage   │  │  Realtime    │ │
│  │(Anon+ML)│  │ (cs_*)   │  │ (Avatare)  │  │ (Notifs)    │ │
│  └─────────┘  └────┬─────┘  └───────────┘  └─────────────┘ │
│                     │                                        │
│         ┌───────────┼───────────────┐                        │
│         ▼           ▼               ▼                        │
│   ┌──────────┐ ┌──────────┐  ┌────────────┐                 │
│   │cs_events │→│cs_event_ │→ │cs_device_  │                 │
│   │ (INSERT) │ │deliveries│  │  tokens     │                 │
│   └──────────┘ │(fanout)  │  └──────┬─────┘                 │
│                └─────┬────┘         │                        │
└──────────────────────┼──────────────┼────────────────────────┘
                       │              │
                       ▼              ▼
              ┌──────────────────────────┐
              │  Edge Worker (geplant)   │
              │  pending → FCM send →   │
              │  status = sent/failed   │
              └───────────┬─────────────┘
                          ▼
              ┌──────────────────────┐
              │  Firebase Cloud      │
              │  Messaging (FCM)     │
              │  → Android Push ✅   │
              │  → iOS Push (TODO)   │
              └──────────────────────┘
```

## 2. Technologiestack

| Layer | Technologie |
|-------|-------------|
| Frontend | Flutter (Dart) |
| Backend | Supabase (Postgres 15, Auth, Storage, Realtime) |
| Authentifizierung | Supabase Auth (Anonymous + Magic Link) |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Local Notifications | flutter_local_notifications |
| Deep Links | app_links (Android App Links + iOS Universal Links) |
| Entwicklung | VS Code + Cursor |

## 3. Datenbank-Strategie (Supabase-safe)

### Grundsatz
- Keine bestehenden Tabellen werden verändert
- Alle App-Tabellen erhalten das Prefix **`cs_`** (CourtSwiss)
- Row Level Security (RLS) ist für alle App-Tabellen aktiv
- Alle Schema-Änderungen sind als idempotente SQL-Dateien in `sql/` abgelegt

### Trennung
- Website-Daten: unverändert
- App-Daten: ausschließlich `cs_*` Tabellen

### SQL-Patches (sql/)

| Datei | Inhalt |
|-------|--------|
| `cs_events_patch.sql` | cs_events, cs_event_reads, Triggers, RPCs |
| `cs_events_payload_patch.sql` | Payload-Standardisierung, Backfill |
| `cs_push_pipeline_patch.sql` | cs_device_tokens, cs_notification_prefs, cs_event_deliveries, Fanout-Trigger |
| `cs_teams_sport_key_patch.sql` | sport_key Spalte zu cs_teams |
| `cs_teams_delete_policy_patch.sql` | RLS DELETE Policy für cs_teams (Creator + Captain) |
| `cs_carpool_rls_patch.sql` | RLS Policies für cs_carpool_offers + cs_carpool_passengers |
| `cs_dinner_rsvps_patch.sql` | cs_dinner_rsvps Tabelle + RLS + Trigger |
| `cs_expenses_patch.sql` | cs_expenses + cs_expense_shares Tabellen + RLS + RPC |
| `cs_expenses_v2_patch.sql` | is_paid/paid_at Spalten, Split nur Dinner "yes", Payer auto-paid |
| `cs_sub_requests_patch.sql` | cs_sub_requests Tabelle + RLS + RPCs (create/respond/list) |
| `cs_sub_requests_timeout_patch.sql` | expires_at Spalte, BEFORE INSERT Trigger, cs_expire_sub_requests() |

## 4. Zentrale Entitäten

### 4.1 Benutzer & Profile

#### cs_app_profiles
- user_id (uuid, PK, references auth.users)
- email (text, nullable)
- display_name (text)
- avatar_path (text, nullable) – Pfad im Supabase Storage
- Wird beim ersten Login automatisch via `ProfileService.ensureProfile()` angelegt

### 4.2 Team-Management

#### cs_teams
- id (uuid, PK)
- name (text) – z.B. „Herren 3. Liga"
- club_name (text, nullable)
- league (text, nullable)
- season_year (int)
- sport_key (text, nullable) – z.B. 'football', 'tennis', 'other'
- created_by (uuid, references auth.users)
- created_at (timestamptz)

#### cs_team_members
- id (uuid, PK)
- team_id (uuid, FK → cs_teams)
- user_id (uuid, FK → auth.users)
- role (text: 'captain' | 'member')
- nickname (text, nullable)
- is_playing (boolean, default false) – ob der User auch als Spieler aktiv ist
- created_at (timestamptz)
- UNIQUE (team_id, user_id)

#### cs_invites
- Token-basiertes Invite-System
- Verwaltung über RPCs: `create_team_invite`, `accept_team_invite`
- Deep-Link-Format: `courtswiss://join?token=<TOKEN>`

#### cs_team_players
- id (uuid, PK)
- team_id (uuid, FK → cs_teams)
- first_name, last_name (text)
- ranking (int, nullable) – Klassierung (1=N1, 9=R9)
- user_id (uuid, nullable) – verknüpft nach Claim
- claimed_by (uuid, nullable)
- Verwaltet über RPCs: `create_team_player`, `claim_team_player`, `unclaim_team_player`, `upsert_captain_player_slot`, `remove_captain_player_slot`

### 4.3 Matches & Verfügbarkeit

#### cs_matches
- id (uuid, PK)
- team_id (uuid, FK → cs_teams)
- opponent (text)
- match_at (timestamptz)
- is_home (boolean)
- location (text, nullable)
- note (text, nullable)
- created_by (uuid)
- created_at (timestamptz)

#### cs_match_availability
- match_id (uuid, FK → cs_matches)
- user_id (uuid, FK → auth.users)
- status (text: 'yes' | 'no' | 'maybe')
- comment (text, nullable)
- updated_at (timestamptz)
- PK (match_id, user_id)

### 4.4 Aufstellung (Lineup)

#### cs_match_lineups
- id (uuid, PK)
- match_id (uuid, FK → cs_matches)
- team_id (uuid, FK → cs_teams)
- status (text: 'draft' | 'published')
- created_by (uuid)
- created_at, updated_at (timestamptz)

#### cs_match_lineup_slots
- id (uuid, PK)
- match_id (uuid, FK → cs_matches)
- slot_type (text: 'starter' | 'reserve')
- position (int)
- player_slot_id (uuid, nullable, FK → cs_team_players)
- user_id (uuid, nullable)
- locked (boolean, default false) – gesperrte Slots werden bei Auto-Promotion übersprungen

#### cs_lineup_events
- id (uuid, PK)
- match_id (uuid, FK → cs_matches)
- team_id (uuid, FK → cs_teams)
- event_type (text: 'auto_promotion' | 'no_reserve')
- payload (jsonb) – enthält promoted_name, absent_name, from/to user_ids
- created_by (uuid, nullable)
- created_at (timestamptz)
- Dient als Audit-Trail für automatische Aufstellungsänderungen

#### Lineup RPCs
| RPC | Funktion |
|-----|----------|
| `generate_lineup` | Erstellt Draft-Lineup nach Ranking |
| `publish_lineup` | Setzt Status auf 'published', löst Event-Trigger aus |
| `move_lineup_slot` | Move zwischen Positionen (from_type/from_pos → to_type/to_pos) |
| `set_lineup_slot` | Spieler auf bestimmte Position setzen |
| `auto_handle_absence` | Automatisches Nachrücken bei Absage |

#### Drag & Drop Reorder (Client-seitig)

Die Aufstellungs-Reihenfolge kann per Drag & Drop in der App verändert werden:
- **Widget**: `LineupReorderList` (lib/widgets/lineup_reorder_list.dart) – `ReorderableListView.builder` mit Haptic Feedback
- **Pure Dart Logic**: `applyReorder()`, `computeMoveSteps()`, `moveStepToRpcParams()` in lib/utils/lineup_reorder.dart
- **Gating**: Drag & Drop ist nur aktiv wenn: Lineup geladen, Status = 'draft', User = Captain, keine Generate/Publish-Operation läuft
- **Persist**: Optimistic UI Update → `move_lineup_slot` RPC → bei Fehler: Rollback auf Deep-Copy Snapshot + SnackBar

#### Regelverstoss-Warnung (Client-seitig)

Reine Client-seitige Warnungen für Captains, keine Blockade:
- **Logic**: `detectLineupViolations()` in lib/utils/lineup_rules.dart (pure Dart, unit-testbar)
- **Regeln**: A) Ranking-Reihenfolge verletzt, B) Fehlende Spieler in Starter-Slots, C) Duplikat-Spieler
- **UI**: Gelbes Warning-Banner über dem Lineup, verschwindet automatisch wenn keine Violations

### 4.5 Ersatzanfragen (Sub-Requests)

#### cs_sub_requests
- id (uuid, PK)
- created_at (timestamptz)
- match_id (uuid, FK → cs_matches)
- team_id (uuid, FK → cs_teams)
- original_user_id (uuid, FK → auth.users) – der Spieler, der ersetzt werden soll
- substitute_user_id (uuid, FK → auth.users) – der angefragte Ersatzspieler
- status (text: 'pending' | 'accepted' | 'declined' | 'expired')
- responded_at (timestamptz, nullable)
- expires_at (timestamptz, nullable) – Default: created_at + 30 Minuten

#### Sub-Request RPCs
| RPC | Funktion |
|-----|----------|
| `cs_create_sub_request` | Findet besten verfügbaren Ersatz (Ranking-basiert) und erstellt pending Request |
| `cs_respond_sub_request` | Ersatzspieler akzeptiert oder lehnt ab; bei Accept: Lineup-Slot Update |
| `cs_list_my_sub_requests` | Alle pending Requests für den aktuellen User |
| `cs_expire_sub_requests` | Markiert überfällige pending Requests als 'expired' (idempotent) |

#### Ersatz-Timeout (ohne Cron)

Das Timeout-System funktioniert ohne pg_cron oder Edge Function Scheduler:

1. **BEFORE INSERT Trigger** (`trg_cs_sub_request_set_expires_at`): Setzt `expires_at = now() + 30 min` wenn nicht explizit gesetzt
2. **Expire-Funktion** (`cs_expire_sub_requests()`): UPDATE … SET status='expired' WHERE status='pending' AND expires_at < now() – SECURITY DEFINER, idempotent, schnell (Index auf status+expires_at)
3. **App-seitige Ausführung**: `SubRequestService.expireStale()` wird **bei jedem Screen-Load** aufgerufen, bevor Sub-Requests geladen werden. Dies ist der primäre Expire-Mechanismus.
4. **Client-seitige Safety-Net**: `sub_request_timeout.dart` bietet reine Dart-Helpers (`isRequestExpired`, `isRequestActionable`, `expiresInLabel`) als zweite Sicherheitsebene für die UI.
5. **pg_cron**: Der SQL-Patch enthält einen optionalen `cron.schedule`-Block, der nur ausgeführt wird wenn die pg_cron Extension vorhanden ist.

### 4.6 Fahrgemeinschaften (Carpool)

#### cs_carpool_offers
- id (uuid, PK)
- match_id (uuid, FK → cs_matches)
- team_id (uuid, FK → cs_teams)
- driver_user_id (uuid, FK → auth.users)
- seats_total (int)
- start_location (text, nullable)
- note (text, nullable)
- depart_at (timestamptz, nullable)
- created_at, updated_at (timestamptz)

#### cs_carpool_passengers
- id (uuid, PK)
- offer_id (uuid, FK → cs_carpool_offers)
- user_id (uuid, FK → auth.users)
- created_at (timestamptz)
- UNIQUE (offer_id, user_id)

#### Carpool RPCs
| RPC | Funktion |
|-----|----------|
| `cs_upsert_carpool_offer` | Angebot erstellen/aktualisieren (Driver only) |
| `cs_join_carpool` | Als Mitfahrer beitreten |
| `cs_leave_carpool` | Als Mitfahrer austreten |

RLS: Team-Mitglieder sehen alle Angebote; nur Driver kann eigenes Angebot ändern/löschen; Mitfahrer kann sich selbst ein-/austragen.

### 4.7 Essen & Spesen (Dinner & Expenses)

#### cs_dinner_rsvps
- id (uuid, PK)
- match_id (uuid, FK → cs_matches)
- user_id (uuid, FK → auth.users)
- status (text: 'yes' | 'no' | 'maybe')
- note (text, nullable)
- updated_at, created_at (timestamptz)
- UNIQUE (match_id, user_id)

#### cs_expenses
- id (uuid, PK)
- match_id (uuid, FK → cs_matches)
- team_id (uuid, FK → cs_teams)
- title (text)
- amount_cents (int, CHECK > 0)
- currency (text, default 'CHF')
- paid_by_user_id (uuid, FK → auth.users) – wer vorgestreckt hat
- note (text, nullable)
- created_at, updated_at (timestamptz)

#### cs_expense_shares
- id (uuid, PK)
- expense_id (uuid, FK → cs_expenses)
- user_id (uuid, FK → auth.users)
- share_cents (int, CHECK >= 0)
- is_paid (boolean, default false)
- paid_at (timestamptz, nullable)
- created_at (timestamptz)
- UNIQUE (expense_id, user_id)

#### Expense RPCs
| RPC | Funktion |
|-----|----------|
| `cs_create_expense_equal_split` | Erstellt Expense und splittet gleichmäßig unter Dinner-"yes"-Teilnehmern; Payer-Share wird automatisch als bezahlt markiert |
| `cs_mark_expense_share_paid` | Einzelnen Share als bezahlt/unbezahlt markieren |

### 4.8 Event-System (Benachrichtigungen)

#### cs_events
- id (uuid, PK)
- created_at (timestamptz)
- team_id (uuid, FK → cs_teams)
- match_id (uuid, nullable, FK → cs_matches)
- event_type (text: 'lineup_published' | 'replacement_promoted' | 'no_reserve_available' | 'sub_request' | 'sub_accepted')
- title (text)
- body (text, nullable)
- payload (jsonb) – standardisiert: team_id, match_id, in_name, out_name etc.
- recipient_user_id (uuid, nullable) – NULL = Broadcast, gesetzt = gezielt
- created_by (uuid, nullable)

#### cs_event_reads
- event_id (uuid, FK → cs_events)
- user_id (uuid, FK → auth.users)
- read_at (timestamptz)
- PK (event_id, user_id)

#### Event RPCs
| RPC | Funktion |
|-----|----------|
| `cs_mark_event_read` | Einzelnes Event als gelesen markieren |
| `cs_mark_all_events_read` | Alle sichtbaren Events als gelesen markieren |
| `cs_unread_event_count` | Anzahl ungelesener Events (für Badge) |

#### Event-Triggers (automatische Erzeugung)
| Trigger | Auslöser | Erzeugt |
|---------|----------|---------|
| `trg_emit_lineup_published_event` | cs_match_lineups.status → 'published' | Broadcast-Event an Team |
| `trg_emit_lineup_event_to_cs_events` | INSERT in cs_lineup_events | Broadcast + gezieltes Event an nachgerückten Spieler/Captain |

### 4.9 Push-Pipeline (FCM)

#### cs_device_tokens
- id (uuid, PK)
- user_id (uuid, FK → auth.users)
- platform (text: 'ios' | 'android')
- token (text) – FCM Registration Token
- device_id (text) – stable UUID per App-Install (SharedPreferences)
- enabled (boolean, default true)
- last_seen_at (timestamptz)
- created_at, updated_at (timestamptz)
- UNIQUE (user_id, device_id)

#### cs_notification_prefs
- id (uuid, PK)
- user_id (uuid, FK → auth.users)
- team_id (uuid, nullable, FK → cs_teams) – NULL = global, gesetzt = Team-Override
- push_enabled (boolean, default true)
- types_disabled (text[]) – z.B. `{'lineup_published','replacement_promoted'}`
- Funktionaler Unique Index auf (user_id, COALESCE(team_id, nil-UUID))

#### cs_event_deliveries
- id (uuid, PK)
- event_id (uuid, FK → cs_events)
- user_id (uuid, FK → auth.users) – der Empfänger
- channel (text: 'push')
- status (text: 'pending' | 'sent' | 'failed' | 'skipped')
- attempts (int, default 0)
- last_error (text, nullable)
- processed_at (timestamptz, nullable)
- created_at (timestamptz)
- UNIQUE (event_id, user_id, channel)

#### Push RPCs
| RPC | Funktion |
|-----|----------|
| `cs_upsert_device_token` | Token registrieren/updaten; bereinigt stale Tokens anderer User |
| `cs_get_notification_prefs` | Prefs lesen (Team-spezifisch oder global) |
| `cs_set_notification_prefs` | Prefs setzen (Upsert) |

#### Fanout-Trigger
`trg_cs_event_fanout` (AFTER INSERT ON cs_events):
1. Bestimmt Empfänger: `recipient_user_id` gesetzt → nur dieser User; NULL → alle Team-Members
2. Prüft pro Empfänger die Notification-Prefs (Team-Override > Global)
3. Erstellt `cs_event_deliveries`-Zeile: `status='pending'` oder `status='skipped'` (wenn disabled/type ausgeschlossen)
4. Überspringt den Ersteller (`created_by`)

#### Token-Registration Flow (Flutter-seitig)
1. `PushService` initialisiert FCM beim App-Start, fordert Permission an
2. `DeviceTokenService` generiert eine stabile `device_id` (SharedPreferences) pro App-Install
3. Bei Token-Empfang oder Auth-State-Change: `cs_upsert_device_token` RPC registriert/updatet den Token
4. Der RPC bereinigt dabei stale Tokens (`DELETE WHERE token=X AND user_id≠current`)

#### Datenfluss (Event → Push)

```
1. Aktion im Client (z.B. Lineup publishen)
        │
        ▼
2. RPC/DB-Operation (publish_lineup → cs_match_lineups.status='published')
        │
        ▼
3. DB-Trigger (trg_emit_lineup_published_event)
   → INSERT INTO cs_events
        │
        ▼
4. Fanout-Trigger (trg_cs_event_fanout)
   → INSERT INTO cs_event_deliveries (status='pending' | 'skipped')
        │
        ▼
5. Edge Worker (geplant, noch nicht produktiv)
   → SELECT deliveries WHERE status='pending'
   → JOIN cs_device_tokens ON user_id
   → FCM HTTP v1 API send
   → UPDATE status='sent' oder 'failed'
```

**Status Push-Send**: Die DB-Pipeline (Events → Fanout → Deliveries) ist produktiv. Der letzte Schritt – ein Edge Worker / Cloud Function der `pending` Deliveries via FCM HTTP v1 API versendet und den Status aktualisiert – ist **noch nicht implementiert**. Deliveries bleiben aktuell auf `status='pending'`.

#### Flutter-seitige FCM-Integration

| Komponente | Aufgabe |
|------------|---------|
| `PushService` | FCM Init, Permission, Token-Handling, Auth-Listener, Message-Handling |
| `DeviceTokenService` | Device-ID-Verwaltung (SharedPreferences), RPC-Aufruf für Token-Upsert |
| `PushPrefsService` | Notification-Preferences lesen/schreiben |
| `LocalNotificationService` | Foreground-Messages als lokale Notification anzeigen |

#### Notification-Tap → Deep Navigation
- Push-Data enthält `match_id` + `team_id`
- `PushService._handleNotificationTap()` → `MatchDetailScreen` via globalem `navigatorKey`

### 4.10 Legacy Notifications (cs_notifications)

#### cs_notifications
- Älteres Benachrichtigungssystem (vor Event-Pipeline)
- Wird noch für Supabase Realtime-Benachrichtigungen verwendet
- Langfristig durch cs_events + cs_event_deliveries zu ersetzen

## 5. Anonymous Auth & Session Handling

### Authentifizierungs-Flow
1. **App-Start**: `Supabase.initialize()` stellt vorhandene Session aus Keychain/SharedPreferences wieder her
2. **Keine Session**: `signInAnonymously()` erstellt eine anonyme Session → sofortiger Zugriff
3. **Magic Link**: User kann sich per Email-Link verifizieren → Session-Wechsel (neue user_id)

### Bekanntes Problem: User-ID Drift
- Anonymous Auth erzeugt bei Neuinstallation/Cache-Verlust eine **neue** user_id
- Team-Member-Einträge (`cs_team_members.user_id`) zeigen weiterhin auf die **alte** user_id
- Dadurch Mismatch: Event-Deliveries laufen unter alter user_id, Device-Token unter neuer

### Device Token Re-Registration
- `PushService` hört auf `onAuthStateChange`
- Bei user_id-Wechsel wird der FCM Token unter der neuen user_id re-registriert
- Der SQL RPC `cs_upsert_device_token` bereinigt dabei stale Tokens (DELETE WHERE token=X AND user_id≠current)

## 6. Event vs. Legacy Notification System

| Merkmal | Legacy (cs_notifications) | Neu (cs_events + cs_event_deliveries) |
|---------|---------------------------|---------------------------------------|
| Tabelle | cs_notifications | cs_events + cs_event_reads + cs_event_deliveries |
| Erzeugung | Manuell / RPC | Automatisch via DB-Triggers |
| Empfänger | Einzeln | Broadcast oder gezielt, mit Fanout |
| Read-Tracking | In derselben Tabelle | Separate Tabelle (cs_event_reads) |
| Push-Delivery | Nicht integriert | Über cs_event_deliveries Pipeline |
| Prefs | Keine | cs_notification_prefs (global + Team-Override) |
| UI | NotificationsScreen | EventInboxScreen |
| Status | **Legacy – wird ersetzt** | **Aktives System** |

## 7. Zugriff & Sicherheit (RLS-Prinzip)

- Alle `cs_*` Tabellen haben RLS aktiviert
- Team-Mitglieder dürfen nur Daten ihres Teams sehen (`is_team_member(team_id)`)
- Nur Captains/Creator dürfen:
  - Aufstellungen erstellen, publizieren
  - Events erstellen/löschen
  - Teams löschen (RLS DELETE Policy: Creator + Captain)
  - Sub-Requests erstellen
- Carpool: nur Driver kann eigenes Angebot ändern/löschen; Mitfahrer können sich selbst ein-/austragen
- Expenses: nur der Bezahler (paid_by_user_id) oder Admin kann löschen/updaten
- Dinner RSVPs: nur eigene RSVPs setzen/ändern
- Device Tokens: nur eigene (`user_id = auth.uid()`)
- Event Reads: nur eigene (`user_id = auth.uid()`)
- Notification Prefs: nur eigene (`user_id = auth.uid()`)
- SECURITY DEFINER RPCs umgehen RLS gezielt für Trigger-Operationen (z.B. Fanout, Sub-Request-Erstellung, Expire)
- Storage-Zugriffe (Avatare) nur für Team-Mitglieder

## 8. Business-Logik-Verteilung

### Client (Flutter)
- UI Rendering
- Verfügbarkeiten setzen
- Lineup generieren (Draft, via RPC)
- Manuelle Lineup-Anpassungen (Drag & Drop Reorder, Lock)
- Regelverstoss-Warnung (pure Dart Logic, keine Blockade)
- Fahrgemeinschaften erstellen/beitreten/verlassen
- Dinner RSVPs (yes/no/maybe)
- Spesen erstellen / Share-Paid-Toggle
- Ersatzanfragen: Accept/Decline UI, Timeout-Anzeige
- Expire stale Sub-Requests on-load (kein Cron → App-seitig)
- FCM Token Management + Auth-State-Listener
- Local Notifications (Foreground)
- Deep Link Handling (Invites)

### Server (Supabase Postgres)
- Auto-Aufstellung (generate_lineup RPC)
- Ersatzspieler-Ketten (auto_handle_absence Trigger)
- Ersatz-Erstellung + Kandidaten-Suche (cs_create_sub_request RPC)
- Ersatz-Timeout (cs_expire_sub_requests, idempotent)
- Expense Equal-Split inkl. nur Dinner-"yes" (cs_create_expense_equal_split RPC)
- Event-Erzeugung (DB Triggers)
- Event-Fanout (cs_event_deliveries Trigger)
- Device-Token Cleanup (cs_upsert_device_token RPC)
- Kritische Statuswechsel (publish_lineup)

### Geplant: Edge Worker
- Verarbeitung von `cs_event_deliveries` (status='pending')
- FCM HTTP v1 API Calls
- Status-Updates (sent/failed)
- **Status**: Noch nicht implementiert

## 9. Flutter Services & Screens

### Services (lib/services/)

| Service | Verantwortlichkeit |
|---------|--------------------|
| `profile_service.dart` | cs_app_profiles Upsert |
| `team_service.dart` | Teams CRUD (inkl. deleteTeam, sport_key, captainNickname) |
| `member_service.dart` | Team-Members, Nicknames |
| `invite_service.dart` | Invite erstellen/akzeptieren (RPC) |
| `team_player_service.dart` | Spieler-Slots, Claim, Ranking, upsertCaptainSlot |
| `match_service.dart` | Matches CRUD, Availability |
| `lineup_service.dart` | Lineup Generate/Publish/Reorder (RPCs), moveSlot |
| `roster_service.dart` | Kader-Verwaltung |
| `carpool_service.dart` | Fahrgemeinschaften (cs_carpool_offers + cs_carpool_passengers) |
| `dinner_service.dart` | Essen-Zusage (cs_dinner_rsvps) |
| `expense_service.dart` | Spesen (cs_expenses + cs_expense_shares, Split, markSharePaid) |
| `sub_request_service.dart` | Ersatzanfragen (cs_sub_requests), expireStale |
| `event_service.dart` | cs_events + cs_event_reads |
| `notification_service.dart` | Legacy cs_notifications (Realtime) |
| `push_service.dart` | FCM Init, Token, Auth-Listener, Message-Handling |
| `device_token_service.dart` | Device-ID + Token-Registration (RPC) |
| `push_prefs_service.dart` | Notification Preferences (RPCs) |
| `local_notification_service.dart` | flutter_local_notifications |
| `deep_link_service.dart` | App Links + Invite-Token Parsing |
| `avatar_service.dart` | Avatar Upload/Download (Supabase Storage) |

### Screens (lib/screens/)

| Screen | Funktion |
|--------|----------|
| `auth_gate.dart` | Auth-State-Router + Invite-Accept + PushService Init |
| `auth_screen.dart` | Login via Magic Link |
| `sport_selection_screen.dart` | Sportart-Auswahl (Grid mit 11 Bild-Kacheln + "Andere") |
| `teams_screen.dart` | Team-Liste + Unread-Badge + Glocke + Swipe-to-Delete |
| `team_detail_screen.dart` | Team-Detail: Members, Matches, Invite, Avatar, Settings, "Ich spiele selbst" Toggle |
| `create_match_screen.dart` | Match erstellen (Gegner, Datum, Ort) |
| `match_detail_screen.dart` | Match: Availability, Lineup (Drag & Drop), Generate, Publish, Carpool, Dinner, Expenses, Sub-Requests |
| `claim_screen.dart` | Spieler-Zuordnung bei Team-Beitritt |
| `event_inbox_screen.dart` | Event-Inbox (neues System) |
| `notifications_screen.dart` | Legacy-Notifications |
| `notification_settings_screen.dart` | Push-Preferences (global + per Event-Type) |

### Widgets (lib/widgets/)

| Widget | Funktion |
|--------|----------|
| `lineup_reorder_list.dart` | ReorderableListView.builder mit optimistic update, rollback, haptics |

### Utils (lib/utils/)

| Utility | Funktion |
|---------|----------|
| `lineup_reorder.dart` | applyReorder, computeMoveSteps, moveStepToRpcParams (pure Dart) |
| `lineup_rules.dart` | detectLineupViolations – Ranking, Missing, Duplicate Checks (pure Dart) |
| `expense_split.dart` | Expense-Split-Logik (Berechnung) |
| `sub_request_timeout.dart` | parseExpiresAt, isRequestExpired, isRequestActionable, expiresInLabel |

### Models (lib/models/)

| Model | Funktion |
|-------|----------|
| `sport.dart` | Sport Model (11 Sportarten + "Andere", assetPath, icon, color) |
| `carpool_offer.dart` | CarpoolOffer + CarpoolPassenger Modelle |
| `dinner_rsvp.dart` | DinnerRsvp Model |
| `expense.dart` | Expense + ExpenseShare Modelle |

## 10. Erweiterbarkeit

- Doppel-Aufstellungen (Lineup-Erweiterung)
- Swiss Tennis Sync (myTennis API)
- Statistiken
- Mehrere Saisons pro Team
- iOS Push Notifications (APNs Setup – Key + GoogleService-Info.plist)
- Edge Worker für Push-Send (cs_event_deliveries processing)
- Offline-Support (lokaler Cache)
- Legacy Notifications (cs_notifications) konsolidieren/entfernen

## 11. Implementierungsstatus (Feb 2026)

| Bereich | Status | Details |
|---------|--------|---------|
| Auth (Anonymous + Magic Link) | ✅ Produktiv | `signInAnonymously()` + Magic Link via Supabase Auth |
| Teams, Members, Invites | ✅ Produktiv | CRUD + Deep-Link-Invite + sport_key + Swipe-to-Delete |
| Matches, Availability | ✅ Produktiv | yes/no/maybe + Captain-Übersicht |
| Lineup (Generate, Publish) | ✅ Produktiv | Ranking-basiert, Draft → Publish |
| Lineup Drag & Drop Reorder | ✅ Produktiv | ReorderableListView, Gating, Persist, Rollback |
| Regelverstoss-Warnung | ✅ Produktiv | Ranking-Reihenfolge, fehlende Starter, Duplikate |
| Auto-Promotion (Ersatzkette) | ✅ Produktiv | DB-Trigger bei Absage |
| Ersatzanfragen (Sub-Requests) | ✅ Produktiv | Create, Accept/Decline, Timeout (30 min, on-load expire) |
| Fahrgemeinschaften | ✅ Produktiv | Create, Join/Leave, Delete, Multi-Offer, Persistenz |
| Essen & Spesen | ✅ Produktiv | Dinner RSVPs, Expenses, Split nur "yes", is_paid Toggle, Payer auto-paid |
| Sportart-Auswahl | ✅ Produktiv | 11 Sportarten + "Andere", Header-Banner, Assets |
| Captain Self-Play Toggle | ✅ Produktiv | "Ich spiele selbst" im Create-Dialog + Team-Detail |
| Event-System (cs_events) | ✅ Produktiv | DB-Triggers + Inbox + Badge |
| Push-Pipeline DB | ✅ Produktiv | cs_device_tokens, cs_event_deliveries, Fanout |
| Android FCM Token | ✅ Produktiv | Token-Registration + Auth-Re-Registration |
| iOS FCM/APNs | ❌ Deaktiviert | GoogleService-Info.plist fehlt, APNs Key nicht konfiguriert |
| Edge Worker (Push-Send) | ❌ Nicht implementiert | cs_event_deliveries bleiben auf 'pending' |
| Automatisierte Tests | 🟡 Teilweise | 6 Test-Suites (lineup_reorder, lineup_rules, sub_request_timeout, carpool, dinner, expense) |
| Offline-Support | ❌ Nicht implementiert | Kein lokaler Cache |
