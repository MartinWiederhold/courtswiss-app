# User Stories & Acceptance Criteria – CourtSwiss

> Letzte Aktualisierung: Februar 2026

---

## Epic 1: Auth & Profil

### US-1.1: Registrierung & Login (Magic Link)
**Als Spieler:in**
möchte ich mich per Magic Link anmelden,
damit ich ohne komplizierte Registrierung Zugriff auf mein Team habe.

**Acceptance Criteria**
- Login via Supabase Auth (Magic Link per E-Mail)
- AuthFlowType ist PKCE
- Nach Login wird ein App-Profil angelegt (cs_app_profiles, falls nicht vorhanden)
- Nutzer bleibt eingeloggt (Session wird in Keychain/SharedPreferences persistiert)

### US-1.2: Anonymous Auth
**Als neue:r Nutzer:in**
möchte ich die App sofort nutzen können, ohne mich einzuloggen,
damit ich das Team-Management testen kann, bevor ich mich registriere.

**Acceptance Criteria**
- Beim App-Start wird geprüft, ob eine Session existiert
- Falls keine Session vorhanden: `signInAnonymously()` wird aufgerufen
- Anonyme Session erhält eine eigene user_id
- Alle App-Funktionen sind mit anonymer Session nutzbar
- Nach Magic-Link-Login kann die Session upgraden (neue user_id)

### US-1.3: Profil anzeigen & bearbeiten
**Als Spieler:in**
möchte ich meinen Anzeigenamen und mein Avatar-Bild sehen und ändern,
damit andere mich erkennen.

**Acceptance Criteria**
- cs_app_profiles enthält display_name und avatar_path
- ProfileService.ensureProfile() wird bei Bedarf aufgerufen
- Änderungen werden per Upsert in cs_app_profiles gespeichert

---

## Epic 2: Team-Management

### US-2.1: Team erstellen (Captain)
**Als Captain**
möchte ich ein Team erstellen,
damit ich Interclub-Begegnungen planen kann.

**Acceptance Criteria**
- Teamname und Saison sind Pflichtfelder
- club_name und league sind optional
- Captain wird automatisch als Teammitglied gesetzt (cs_team_members, role='captain')
- created_by wird auf auth.uid() gesetzt

### US-2.2: Spieler zum Team einladen (Deep Link)
**Als Captain**
möchte ich Spieler per Einladungslink hinzufügen,
damit sie meinem Team beitreten können.

**Acceptance Criteria**
- Einladungstoken wird per RPC `create_team_invite` erstellt
- Token wird in cs_invites gespeichert
- Deep-Link-Format: `courtswiss://join?token=<TOKEN>`
- Share-Text enthält Teamname und Link
- Bei Annahme wird `accept_team_invite` RPC aufgerufen
- Spieler erscheint in cs_team_members mit role='member'
- Doppel-Beitritt wird verhindert (idempotent)

### US-2.3: Teamliste anzeigen
**Als Spieler:in**
möchte ich alle meine Teams sehen,
damit ich schnell zum richtigen Team navigieren kann.

**Acceptance Criteria**
- TeamsScreen zeigt alle Teams des Users (cs_team_members → cs_teams)
- Sortierung nach created_at DESC
- Unread-Event-Badge (Glocke) wird in der AppBar angezeigt

### US-2.4: Team-Detail mit Mitglieder-Übersicht
**Als Captain oder Spieler:in**
möchte ich die Mitglieder meines Teams sehen,
damit ich weiß, wer dabei ist.

**Acceptance Criteria**
- TeamDetailScreen zeigt: Team-Name, Mitgliederliste, Matches
- Mitglieder werden aus cs_team_members + cs_app_profiles geladen
- Captain kann Team-Avatar setzen
- Captain kann Spieler-Slots verwalten
- Invite-Button für Captain sichtbar

---

## Epic 3: Begegnungen (Matches)

### US-3.1: Match erstellen
**Als Captain**
möchte ich ein Match mit Gegner, Datum und Ort anlegen,
damit das Team planen kann.

**Acceptance Criteria**
- Match wird in cs_matches gespeichert
- Pflichtfelder: opponent, match_at
- Optional: is_home, location, note
- Match gehört zu genau einem Team (team_id)
- Match erscheint in der TeamDetailScreen-Übersicht

### US-3.2: Match bearbeiten & löschen
**Als Captain**
möchte ich ein Match bearbeiten oder löschen,
damit ich Änderungen korrigieren kann.

**Acceptance Criteria**
- Update auf cs_matches per Match-ID
- Delete auf cs_matches per Match-ID
- RLS: Nur Team-Mitglieder sehen Matches; nur Captain/Creator darf ändern

---

## Epic 4: Verfügbarkeit

### US-4.1: Verfügbarkeit angeben
**Als Spieler:in**
möchte ich angeben, ob ich Zeit habe,
damit der Captain planen kann.

**Acceptance Criteria**
- Status: yes / no / maybe
- Upsert in cs_match_availability (match_id, user_id)
- Änderung jederzeit möglich
- Captain sieht alle Antworten im MatchDetailScreen
- Optional: Kommentarfeld

### US-4.2: Absage löst Auto-Promotion aus
**Als Captain**
möchte ich, dass bei einer Absage automatisch der nächste Ersatz nachrückt,
damit die Aufstellung komplett bleibt.

**Acceptance Criteria**
- Trigger `trg_availability_absence` auf cs_match_availability
- Wenn status='no' und Lineup published: `auto_handle_absence` RPC wird aufgerufen
- Absagender Spieler wird aus cs_match_lineup_slots entfernt (nicht als Reserve behalten)
- Nächster Ersatz rückt auf Starter-Position nach
- Reserve-Slots werden renummeriert
- Wenn kein Ersatz: `no_reserve` Event wird erzeugt

---

## Epic 5: Aufstellung (Lineup)

### US-5.1: Automatische Aufstellung generieren
**Als Captain**
möchte ich automatisch eine Aufstellung generieren,
damit ich Zeit spare.

**Acceptance Criteria**
- RPC `generate_lineup` erstellt Draft-Lineup
- Sortierung nach Ranking (cs_team_players.ranking)
- Nur Spieler mit availability='yes' werden berücksichtigt
- Richtige Anzahl Starter + Ersatzspieler
- Lineup-Status ist 'draft'

### US-5.2: Manuelle Anpassung
**Als Captain**
möchte ich die Aufstellung manuell anpassen,
damit ich flexibel bleibe.

**Acceptance Criteria**
- RPC `move_lineup_slot` für Swap/Reorder
- RPC `set_lineup_slot` für gezielte Zuweisung
- Locked-Slots (locked=true) werden bei Auto-Promotion übersprungen
- Änderungen werden in cs_match_lineup_slots gespeichert

### US-5.3: Aufstellung veröffentlichen
**Als Captain**
möchte ich die Aufstellung veröffentlichen,
damit alle Spieler sie sehen können.

**Acceptance Criteria**
- RPC `publish_lineup` setzt cs_match_lineups.status='published'
- Trigger `trg_emit_lineup_published_event` feuert
- cs_events-Eintrag wird erzeugt (event_type='lineup_published')
- Alle Team-Mitglieder sehen die veröffentlichte Aufstellung
- Aufstellung kann nach Publish nicht mehr als Draft zurückgesetzt werden

---

## Epic 6: Ersatzspieler-Kette

### US-6.1: Automatisches Nachrücken
**Als Ersatzspieler**
möchte ich automatisch in die Aufstellung rücken, wenn ein Starter absagt,
damit kein manueller Eingriff nötig ist.

**Acceptance Criteria**
- `auto_handle_absence` RPC mit FOR UPDATE Locking (Race-Condition-sicher)
- Nächster Ersatzspieler (nach reserve_order) rückt auf Starter-Position
- cs_lineup_events-Eintrag mit event_type='auto_promotion' wird erzeugt
- Payload enthält: promoted_name, absent_name, from/to user_ids
- Trigger erzeugt cs_events (Broadcast + gezieltes Event an nachgerückten Spieler)

### US-6.2: Kein Ersatz verfügbar
**Als Captain**
möchte ich benachrichtigt werden, wenn kein Ersatz mehr verfügbar ist,
damit ich reagieren kann.

**Acceptance Criteria**
- cs_lineup_events mit event_type='no_reserve' wird erzeugt
- cs_events-Eintrag (Broadcast + gezieltes Event an Captain) wird erzeugt
- Payload enthält: absent_name
- Event erscheint in der Inbox

---

## Epic 7: Fahrgemeinschaften

> **Status: Nicht implementiert (Post-MVP)**

### US-7.1: Fahrgemeinschaft erstellen
**Als Fahrer**
möchte ich eine Fahrgemeinschaft erstellen,
damit Mitspieler mitfahren können.

**Acceptance Criteria**
- Sitzplätze definierbar
- Treffpunkt und Zeit optional
- Status „voll" bei Erreichen der Kapazität

### US-7.2: Fahrgemeinschaft beitreten
**Als Spieler:in**
möchte ich einer Fahrgemeinschaft beitreten,
damit ich organisiert zum Spiel komme.

**Acceptance Criteria**
- Beitritt nur bei freien Plätzen
- Status sichtbar

---

## Epic 8: Essen & Spesen

> **Status: Nicht implementiert (Post-MVP)**

### US-8.1: Essen zusagen
**Als Spieler:in**
möchte ich angeben, ob ich nach dem Spiel zum Essen bleibe,
damit der Captain planen kann.

**Acceptance Criteria**
- Ja / Nein auswählbar
- Status sichtbar für Captain

### US-8.2: Spesen erfassen
**Als Captain**
möchte ich einen Beleg hochladen und Kosten aufteilen,
damit alles transparent ist.

**Acceptance Criteria**
- Beleg-Upload möglich
- Kosten gleichmässig verteilt
- Zahlungsstatus pro Spieler sichtbar

---

## Epic 9: Benachrichtigungen (Legacy)

> **Status: Legacy-System. Wird durch Epic 10 (Event-System) und Epic 11 (Push-Pipeline) ersetzt.**

### US-9.1: Wichtige Events (Legacy)
**Als Nutzer:in**
möchte ich über wichtige Ereignisse informiert werden,
damit ich nichts verpasse.

**Acceptance Criteria**
- cs_notifications-Tabelle mit Realtime-Subscription
- NotificationsScreen zeigt Benachrichtigungen
- Push bei Ersatzanfrage
- Push bei Nachrücken

---

## Epic 10: Event & Notification Inbox

### US-10.1: Event wird bei Aktionen erzeugt
**Als System**
soll bei relevanten Aktionen automatisch ein cs_events-Eintrag erzeugt werden,
damit alle Betroffenen informiert werden.

**Auslöser:**
- Lineup wird veröffentlicht (Trigger `trg_emit_lineup_published_event`)
- Ersatzspieler rückt nach (Trigger `trg_emit_lineup_event_to_cs_events`, event_type='auto_promotion')
- Kein Ersatz verfügbar (Trigger `trg_emit_lineup_event_to_cs_events`, event_type='no_reserve')

**Acceptance Criteria**
- cs_events-Row existiert nach Auslöser
- team_id ist korrekt gesetzt
- match_id ist korrekt gesetzt (wenn Match-bezogen)
- created_by enthält den auslösenden User
- event_type ist gesetzt ('lineup_published' | 'replacement_promoted' | 'no_reserve_available')
- payload ist valides JSON mit mindestens team_id und match_id
- recipient_user_id ist NULL für Broadcasts, gesetzt für gezielte Events

### US-10.2: Delivery-Fanout
**Als System**
sollen für jedes Event cs_event_deliveries-Einträge erzeugt werden,
damit Push-Nachrichten zugestellt werden können.

**Acceptance Criteria**
- Fanout-Trigger `trg_cs_event_fanout` feuert AFTER INSERT ON cs_events
- Für Broadcast (recipient_user_id IS NULL): Delivery für jedes Team-Mitglied (cs_team_members)
- Für gezieltes Event: Delivery nur für den spezifischen User
- Delivery-User muss in cs_team_members.user_id existieren
- status='pending' für aktivierte Push-Prefs
- status='skipped' wenn push_enabled=false oder event_type in types_disabled
- Kein Delivery für den Ersteller (created_by wird übersprungen)
- Kein Delivery für Nicht-Mitglieder
- UNIQUE Constraint auf (event_id, user_id, channel) verhindert Duplikate

### US-10.3: Event Inbox anzeigen
**Als Spieler:in**
möchte ich meine Events in einer Inbox sehen,
damit ich nichts verpasse.

**Acceptance Criteria**
- EventInboxScreen zeigt Events für alle Teams des Users
- Sortierung: newest first
- Unread-Events sind optisch hervorgehoben (fett/Punkt)
- Unread-Badge (Glocke) in TeamsScreen AppBar zeigt korrekte Anzahl
- RPC `cs_unread_event_count` liefert Zähler
- Tap auf Event: `cs_mark_event_read` RPC wird aufgerufen
- Read-Status wird in cs_event_reads gespeichert
- Bei match_id: Navigation zu MatchDetailScreen (mit Soft-Fail bei fehlendem Match)
- "Alle gelesen"-Button: `cs_mark_all_events_read` RPC
- Optionaler Team-Filter (Dropdown)

---

## Epic 11: Push Pipeline (Android)

### US-11.1: Device Token Registrierung
**Als App-Nutzer auf Android**
möchte ich, dass mein Gerät für Push-Nachrichten registriert wird,
damit ich Benachrichtigungen erhalte.

**Acceptance Criteria**
- `PushService.initPush()` wird nach Auth-Session aufgerufen
- FCM Token wird via `FirebaseMessaging.instance.getToken()` geholt
- Token wird per RPC `cs_upsert_device_token` in cs_device_tokens gespeichert
- cs_device_tokens enthält: user_id, token, platform='android', device_id, enabled=true
- device_id ist eine stabile UUID aus SharedPreferences (pro App-Installation)
- Token-Refresh-Listener registriert (`onTokenRefresh`)
- UNIQUE Constraint auf (user_id, device_id)
- Debug-Log: `print('PUSH_INIT userId=... tokenPrefix=...')`

### US-11.2: Token Re-Assignment bei Auth Change
**Als System**
soll bei einem User-Wechsel (Anonymous → Magic Link, Neuinstallation) das Device Token
automatisch unter der neuen user_id registriert werden.

**Acceptance Criteria**
- `PushService` hört auf `Supabase.instance.client.auth.onAuthStateChange`
- Bei user_id-Wechsel: `_registerTokenForCurrentUser()` wird aufgerufen
- `_lastRegisteredUserId` verhindert Endlosschleifen
- SQL RPC `cs_upsert_device_token` löscht stale Rows: DELETE WHERE token=X AND user_id≠current
- SQL RPC löscht auch stale device_id-Rows: DELETE WHERE device_id=X AND user_id≠current
- Guard: wenn currentUser == null → keine Registration

### US-11.3: Delivery Status Handling
**Als System**
sollen Deliveries nach Push-Versand aktualisiert werden,
damit der Zustellstatus nachvollziehbar ist.

**Acceptance Criteria**
- cs_event_deliveries.status: pending → sent (bei Erfolg)
- cs_event_deliveries.status: pending → failed (bei Fehler)
- last_error enthält Fehlerbeschreibung bei failed
- attempts wird hochgezählt
- processed_at wird gesetzt

> **Hinweis:** Aktuell bleibt status auf 'pending', da der Edge Worker noch nicht produktiv ist.

### US-11.4: iOS Push deaktiviert
**Als System**
soll auf iOS keine FCM-Initialisierung stattfinden,
da die iOS Push-Konfiguration noch nicht abgeschlossen ist.

**Acceptance Criteria**
- `PushService.initPush()` prüft `Platform.isIOS` und bricht ggf. ab
- Keine Firebase Messaging Calls auf iOS
- Kein Token-Registration-Versuch auf iOS
- GoogleService-Info.plist fehlt im iOS-Projekt (bewusst)
- App stürzt auf iOS nicht wegen fehlender Firebase-Konfiguration ab

---

## Epic 12: Player Claim

### US-12.1: Spieler übernimmt eigenes Profil
**Als Spieler:in**
möchte ich nach dem Team-Beitritt mein Spielerprofil übernehmen (claimen),
damit meine Klassierung und mein Ranking mit meinem Account verknüpft sind.

**Acceptance Criteria**
- ClaimScreen wird nach Team-Beitritt angezeigt
- Zeigt liste aller unclaimed cs_team_players für das Team
- Suchfeld zum Filtern nach Name
- Tap auf Spieler: RPC `claim_team_player` wird aufgerufen
- cs_team_players.user_id wird auf auth.uid() gesetzt
- cs_team_players.claimed_by wird auf auth.uid() gesetzt
- Ranking (Klassierung R9–N1) bleibt erhalten
- Doppel-Claim wird verhindert (RPC-seitig)
- Captain kann via `unclaim_team_player` zurücksetzen

---

## Epic 13: Avatar Upload

### US-13.1: Avatar speichern & anzeigen
**Als Spieler:in**
möchte ich ein Profilbild hochladen,
damit andere mich erkennen.

**Acceptance Criteria**
- AvatarService.pickAndUpload() öffnet Image Picker (Kamera oder Galerie)
- Bild wird in Supabase Storage Bucket 'profile-photos' hochgeladen
- Pfad wird in cs_app_profiles.avatar_path gespeichert
- Avatar wird im TeamDetailScreen bei Mitgliederliste angezeigt
- RLS: Nur eigene Bilder können hochgeladen/geändert werden
- Private Bucket: Bilder sind nicht öffentlich zugänglich
- Signed URLs werden für die Anzeige verwendet

---

## Epic 14: Lineup Events (Audit Trail)

### US-14.1: Lineup Publish erzeugt Events
**Als System**
sollen bei Aufstellungsänderungen Audit-Einträge in cs_lineup_events geschrieben werden,
damit Änderungen nachvollziehbar sind und Benachrichtigungen ausgelöst werden.

**Acceptance Criteria**
- Lineup Publish: Trigger erzeugt cs_events-Eintrag (event_type='lineup_published')
- Auto-Promotion: `auto_handle_absence` schreibt cs_lineup_events (event_type='auto_promotion')
- No-Reserve: `auto_handle_absence` schreibt cs_lineup_events (event_type='no_reserve')
- Trigger `trg_emit_lineup_event_to_cs_events` spiegelt cs_lineup_events → cs_events
- cs_event_deliveries werden per Fanout-Trigger erzeugt
- Payload enthält: promoted_name, absent_name, from/to user_ids, match_id, team_id

---

## Post-MVP Backlog

| # | Feature | Epic / Bereich | Priorität |
|---|---------|----------------|-----------|
| 1 | **Edge Function Push Worker** | Epic 11 | Hoch – Deliveries verarbeiten, FCM HTTP v1 senden |
| 2 | **iOS Push Notifications** | Epic 11 | Hoch – APNs Key, GoogleService-Info.plist, Firebase Setup |
| 3 | **Fahrgemeinschaften** | Epic 7 | Mittel – cs_carpools + cs_carpool_members |
| 4 | **Essen & Spesen** | Epic 8 | Mittel – cs_expenses + cs_expense_participants |
| 5 | **Ersatz-Timeout** | Epic 6 | Mittel – Automatische Absage nach Frist |
| 6 | **Offline Support** | Infrastruktur | Mittel – Lokaler Cache, Sync |
| 7 | **Drag & Drop Lineup** | Epic 5 | Niedrig – Native Drag & Drop statt Button-basiertem Reorder |
| 8 | **Test Coverage** | Infrastruktur | Hoch – Unit Tests, Widget Tests, Integration Tests |
| 9 | **Swiss Tennis Sync** | Infrastruktur | Niedrig – myTennis API Integration |
| 10 | **Statistiken** | Infrastruktur | Niedrig – Spieler- und Teamstatistiken |
| 11 | **Mehrere Saisons pro Team** | Epic 2 | Niedrig – Saison-Archiv |
