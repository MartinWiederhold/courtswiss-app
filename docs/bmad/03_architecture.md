# Architektur & Datenmodell – CourtSwiss

> Letzte Aktualisierung: Februar 2026

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
- Alle App-Tabellen erhalten das Prefix `cs_`
- Row Level Security (RLS) ist für alle App-Tabellen aktiv

### Trennung
- Website-Daten: unverändert
- App-Daten: ausschließlich `cs_*` Tabellen

### SQL-Patches
Alle DB-Änderungen sind als idempotente SQL-Dateien in `sql/` abgelegt:

| Datei | Inhalt |
|-------|--------|
| `cs_events_patch.sql` | cs_events, cs_event_reads, Triggers, RPCs |
| `cs_events_payload_patch.sql` | Payload-Standardisierung, Backfill |
| `cs_push_pipeline_patch.sql` | cs_device_tokens, cs_notification_prefs, cs_event_deliveries, Fanout-Trigger |

## 4. Zentrale Entitäten

### 4.1 Benutzer & Profile

#### cs_app_profiles
- user_id (uuid, PK, references auth.users)
- email (text, nullable)
- display_name (text)
- Wird beim ersten Login automatisch via `ProfileService.ensureProfile()` angelegt

### 4.2 Team-Management

#### cs_teams
- id (uuid, PK)
- name (text) – z.B. „Herren 3. Liga"
- club_name (text, nullable)
- league (text, nullable)
- season_year (int)
- created_by (uuid, references auth.users)
- created_at (timestamptz)

#### cs_team_members
- id (uuid, PK)
- team_id (uuid, FK → cs_teams)
- user_id (uuid, FK → auth.users)
- role (text: 'captain' | 'member')
- nickname (text, nullable)
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
| `move_lineup_slot` | Swap/Move zwischen Positionen (Captain) |
| `set_lineup_slot` | Spieler auf bestimmte Position setzen |
| `auto_handle_absence` | Automatisches Nachrücken bei Absage |

### 4.5 Event-System (Benachrichtigungen)

#### cs_events
- id (uuid, PK)
- created_at (timestamptz)
- team_id (uuid, FK → cs_teams)
- match_id (uuid, nullable, FK → cs_matches)
- event_type (text: 'lineup_published' | 'replacement_promoted' | 'no_reserve_available')
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

### 4.6 Push-Pipeline

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

### 4.7 Legacy Notifications (cs_notifications)

#### cs_notifications
- Älteres Benachrichtigungssystem (vor Event-Pipeline)
- Wird noch für Supabase Realtime-Benachrichtigungen verwendet
- Langfristig durch cs_events + cs_event_deliveries zu ersetzen

### 4.8 Geplante Tabellen (nicht implementiert)

#### cs_carpools / cs_carpool_members
- Fahrgemeinschaften pro Match
- **Status: Noch nicht implementiert**

#### cs_expenses / cs_expense_participants
- Spesen und Kostenaufteilung
- **Status: Noch nicht implementiert**

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

## 6. Push-Architektur (FCM)

### Datenfluss

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

### Flutter-seitige FCM-Integration

| Komponente | Aufgabe |
|------------|---------|
| `PushService` | FCM Init, Permission, Token-Handling, Auth-Listener, Message-Handling |
| `DeviceTokenService` | Device-ID-Verwaltung (SharedPreferences), RPC-Aufruf für Token-Upsert |
| `PushPrefsService` | Notification-Preferences lesen/schreiben |
| `LocalNotificationService` | Foreground-Messages als lokale Notification anzeigen |

### Notification-Tap → Deep Navigation
- Push-Data enthält `match_id` + `team_id`
- `PushService._handleNotificationTap()` → `MatchDetailScreen` via globalem `navigatorKey`

## 7. Event vs. Legacy Notification System

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

## 8. Zugriff & Sicherheit (RLS-Prinzip)

- Alle `cs_*` Tabellen haben RLS aktiviert
- Team-Mitglieder dürfen nur Daten ihres Teams sehen (`is_team_member(team_id)`)
- Nur Captains/Creator dürfen:
  - Aufstellungen erstellen, publizieren
  - Events erstellen/löschen
- Device Tokens: nur eigene (`user_id = auth.uid()`)
- Event Reads: nur eigene (`user_id = auth.uid()`)
- Notification Prefs: nur eigene (`user_id = auth.uid()`)
- SECURITY DEFINER RPCs umgehen RLS gezielt für Trigger-Operationen (z.B. Fanout)
- Storage-Zugriffe (Avatare) nur für Team-Mitglieder

## 9. Business-Logik-Verteilung

### Client (Flutter)
- UI Rendering
- Verfügbarkeiten setzen
- Lineup generieren (Draft, via RPC)
- Manuelle Lineup-Anpassungen (Reorder, Lock)
- FCM Token Management + Auth-State-Listener
- Local Notifications (Foreground)
- Deep Link Handling (Invites)

### Server (Supabase Postgres)
- Auto-Aufstellung (generate_lineup RPC)
- Ersatzspieler-Ketten (auto_handle_absence Trigger)
- Event-Erzeugung (DB Triggers)
- Event-Fanout (cs_event_deliveries Trigger)
- Device-Token Cleanup (cs_upsert_device_token RPC)
- Kritische Statuswechsel (publish_lineup)

### Geplant: Edge Worker
- Verarbeitung von `cs_event_deliveries` (status='pending')
- FCM HTTP v1 API Calls
- Status-Updates (sent/failed)

## 10. Flutter Services & Screens

### Services (lib/services/)

| Service | Verantwortlichkeit |
|---------|--------------------|
| `profile_service.dart` | cs_app_profiles Upsert |
| `team_service.dart` | Teams CRUD |
| `member_service.dart` | Team-Members, Nicknames |
| `invite_service.dart` | Invite erstellen/akzeptieren (RPC) |
| `team_player_service.dart` | Spieler-Slots, Claim, Ranking |
| `match_service.dart` | Matches CRUD, Availability |
| `lineup_service.dart` | Lineup Generate/Publish/Reorder (RPCs) |
| `roster_service.dart` | Kader-Verwaltung |
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
| `teams_screen.dart` | Team-Liste + Unread-Badge + Glocke |
| `team_detail_screen.dart` | Team-Detail: Members, Matches, Invite, Avatar, Settings |
| `create_match_screen.dart` | Match erstellen (Gegner, Datum, Ort) |
| `match_detail_screen.dart` | Match: Availability, Lineup, Generate, Publish |
| `claim_screen.dart` | Spieler-Zuordnung bei Team-Beitritt |
| `event_inbox_screen.dart` | Event-Inbox (neues System) |
| `notifications_screen.dart` | Legacy-Notifications |
| `notification_settings_screen.dart` | Push-Preferences (global + per Event-Type) |

## 11. Erweiterbarkeit

- Doppel-Aufstellungen (Lineup-Erweiterung)
- Fahrgemeinschaften (cs_carpools + cs_carpool_members)
- Essen & Spesen (cs_expenses + cs_expense_participants)
- Swiss Tennis Sync (myTennis API)
- Statistiken
- Mehrere Saisons pro Team
- iOS Push Notifications (APNs Setup)
- Edge Worker für Push-Send

## 12. Current Implementation Status (Feb 2026)

| Bereich | Status | Details |
|---------|--------|---------|
| Auth (Anonymous + Magic Link) | ✅ Produktiv | `signInAnonymously()` + Magic Link via Supabase Auth |
| Teams, Members, Invites | ✅ Produktiv | CRUD + Deep-Link-Invite |
| Matches, Availability | ✅ Produktiv | yes/no/maybe + Captain-Übersicht |
| Lineup (Generate, Publish) | ✅ Produktiv | Ranking-basiert, Draft → Publish |
| Auto-Promotion (Ersatzkette) | ✅ Produktiv | DB-Trigger bei Absage |
| Event-System (cs_events) | ✅ Produktiv | DB-Triggers + Inbox + Badge |
| Push-Pipeline DB | ✅ Produktiv | cs_device_tokens, cs_event_deliveries, Fanout |
| Android FCM Token | ✅ Produktiv | Token-Registration + Auth-Re-Registration |
| iOS FCM/APNs | ❌ Deaktiviert | GoogleService-Info.plist fehlt, APNs Key nicht konfiguriert |
| Edge Worker (Push-Send) | ❌ Nicht implementiert | cs_event_deliveries bleiben auf 'pending' |
| Fahrgemeinschaften | ❌ Nicht implementiert | Keine DB-Tabellen, kein UI |
| Essen & Spesen | ❌ Nicht implementiert | Keine DB-Tabellen, kein UI |
| Automatisierte Tests | ❌ Minimal | Nur Default Flutter Widget-Test |
| Offline-Support | ❌ Nicht implementiert | Kein lokaler Cache |
