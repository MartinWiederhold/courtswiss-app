# Report: Auto-Promotion System — Ersatzkette bei Absage

> Stand: 19. Februar 2026  
> Datei: `docs/report_auto_promotion_system.md`

---

## 1. Überblick

Wenn ein **Starter** (Spieler oder Captain) in einer veröffentlichten Aufstellung absagt, soll der erste verfügbare **Ersatzspieler** automatisch zum Starter befördert werden. Dieses System heisst intern **Auto-Promotion** oder **Ersatzkette**.

---

## 2. Beteiligte Komponenten

### 2.1 Datenbank-Tabellen

| Tabelle | Rolle |
|---------|-------|
| `cs_match_availability` | Verfügbarkeit pro Spieler (status: `yes` / `no` / `maybe`) |
| `cs_match_lineups` | Aufstellungs-Master (status: `draft` / `published`) |
| `cs_match_lineup_slots` | Einzelne Slots (slot_type: `starter` / `reserve`, position, player_slot_id, user_id, locked) |
| `cs_team_players` | Spieler-Profile mit `claimed_by` (Auth-User-ID) |
| `cs_lineup_events` | Audit-Log für Auto-Promotion Events |

### 2.2 SQL-Funktionen & Trigger

| Objekt | Typ | Datei |
|--------|-----|-------|
| `fn_auto_promote_on_absence()` | Trigger-Funktion | `sql/cs_fix_autopromote_v4.sql` |
| `trg_auto_promote_on_absence` | AFTER INSERT OR UPDATE Trigger auf `cs_match_availability` | `sql/cs_fix_autopromote_v4.sql` |
| `auto_handle_absence(uuid, uuid)` | RPC (SECURITY DEFINER) | `sql/cs_fix_autopromote_v4.sql` |
| `cs_confirm_promotion(uuid)` | RPC | `sql/cs_fix_autopromote_v4.sql` |
| `cs_decline_promotion(uuid)` | RPC | `sql/cs_fix_autopromote_v4.sql` |

### 2.3 Flutter-Dateien

| Datei | Relevante Methoden |
|-------|-------------------|
| `lib/services/match_service.dart` | `setAvailability()` — Upsert auf `cs_match_availability` |
| `lib/services/lineup_service.dart` | `triggerAutoPromotion()`, `confirmPromotion()`, `declinePromotion()`, `getEvents()`, `getSlots()` |
| `lib/screens/match_detail_screen.dart` | `_setAvailability()`, `_confirmPromotion()`, `_declinePromotion()`, `_buildPromotionBanner()`, `_load()` |

---

## 3. Ablauf: Spieler (Starter) sagt ab

### 3.1 Sequenzdiagramm

```
Spieler (App)              Flutter                    Supabase DB
    │                         │                            │
    │  Klickt "Absagen"       │                            │
    │────────────────────────>│                            │
    │                         │  setAvailability('no')     │
    │                         │───────────────────────────>│
    │                         │                            │  UPSERT cs_match_availability
    │                         │                            │  SET status = 'no'
    │                         │                            │
    │                         │                            │  AFTER Trigger feuert:
    │                         │                            │  fn_auto_promote_on_absence()
    │                         │                            │    └─ Prüft: status == 'no'? ✓
    │                         │                            │    └─ Prüft: published lineup? ✓
    │                         │                            │    └─ Ruft auto_handle_absence()
    │                         │                            │        └─ Findet Starter-Slot
    │                         │                            │        └─ Findet Reserve #1
    │                         │                            │        └─ UPDATE reserve → starter
    │                         │                            │        └─ DELETE absent slot
    │                         │                            │        └─ Renumber reserves
    │                         │                            │        └─ INSERT cs_lineup_events
    │                         │                            │           (event_type: 'auto_promotion')
    │                         │<───────────────────────────│
    │                         │                            │
    │                         │  triggerAutoPromotion()    │  ← Sicherheitsnetz (expliziter RPC)
    │                         │───────────────────────────>│  auto_handle_absence():
    │                         │                            │  → "not_starter" (schon verarbeitet)
    │                         │<───────────────────────────│
    │                         │                            │
    │                         │  _load() → getSlots()     │
    │                         │───────────────────────────>│
    │                         │  ← aktualisierte Slots    │
    │<────────────────────────│                            │
    │  UI zeigt: Reserve      │                            │
    │  ist jetzt Starter      │                            │
```

### 3.2 Detaillierter Code-Ablauf

#### Schritt 1: Flutter `_setAvailability('no')`

**Datei:** `lib/screens/match_detail_screen.dart` (Zeile 625–685)

1. Optimistic UI: `_myStatus = 'no'`, `_availUpdating = true`
2. Ruft `MatchService.setAvailability(status: 'no')` auf
3. `MatchService.setAvailability` macht einen **Upsert** auf `cs_match_availability`:
   ```dart
   await _supabase.from('cs_match_availability').upsert({
     'match_id': matchId,
     'user_id': uid,
     'status': status,
     'updated_at': DateTime.now().toUtc().toIso8601String(),
   }, onConflict: 'match_id,user_id');
   ```
4. Nach Upsert: Verfügbarkeits-Liste neu laden (lightweight)
5. **Expliziter RPC-Aufruf** als Sicherheitsnetz:
   ```dart
   final promoResult = await LineupService.triggerAutoPromotion(
     matchId: widget.matchId,
     absentUserId: uid,
   );
   ```
6. Vollständige Seite neu laden: `_load()`

#### Schritt 2: DB-Trigger `trg_auto_promote_on_absence`

**Datei:** `sql/cs_fix_autopromote_v4.sql` (Zeile 260–298)

- Typ: `AFTER INSERT OR UPDATE` auf `cs_match_availability`
- Prüfung: `NEW.status == 'no'` → weiter
- **Kein Guard** für "Status war schon 'no'" — der RPC ist idempotent
- Prüft ob veröffentlichte Aufstellung existiert
- Ruft `auto_handle_absence(match_id, user_id)` auf
- Gesamter Body in `EXCEPTION`-Block → kann **niemals** die Verfügbarkeitsänderung blockieren

#### Schritt 3: RPC `auto_handle_absence`

**Datei:** `sql/cs_fix_autopromote_v4.sql` (Zeile 80–251)

| Schritt | Aktion | Detail |
|---------|--------|--------|
| 1 | Lineup prüfen | `cs_match_lineups.status = 'published'` nötig |
| 2 | Starter-Slot finden | JOIN mit `cs_team_players`: sucht per `s.user_id = p_absent_user_id` **ODER** `tp.claimed_by = p_absent_user_id` |
| 3 | Reserve finden | Nächster nicht-gesperrter Reserve-Slot (`locked IS NOT TRUE`), sortiert nach `position ASC` |
| 4 | Befördern | `UPDATE slot_type = 'starter'`, `position = absent_pos`, `user_id = COALESCE(user_id, resolved_uid)` |
| 5 | Absent entfernen | `DELETE FROM cs_match_lineup_slots WHERE id = absent_slot_id` |
| 6 | Renumber | Verbleibende Reserves neu nummerieren (1, 2, 3, …) |
| 7 | Audit-Event | `INSERT INTO cs_lineup_events` mit `event_type = 'auto_promotion'` |

**Mögliche Rückgabewerte:**

| promoted | reason | Bedeutung |
|----------|--------|-----------|
| `false` | `no_lineup` | Keine Aufstellung vorhanden |
| `false` | `not_published` | Aufstellung ist noch Entwurf |
| `false` | `not_starter` | Absagender ist kein Starter |
| `false` | `no_reserve` | Kein Ersatzspieler verfügbar |
| `false` | `rpc_exception` | Unerwarteter Fehler (geloggt) |
| `true` | – | Erfolgreich befördert |

---

## 4. Ablauf: Captain (Starter) sagt ab

### 4.1 Identischer Ablauf

Der Ablauf ist **exakt gleich** wie bei einem normalen Spieler. Es gibt **keine Sonderbehandlung** für den Captain. Die `_setAvailability`-Methode wird von allen Benutzern gleich aufgerufen.

### 4.2 Bekannte Probleme (behoben in v4)

| Problem | Ursache | Fix in v4 |
|---------|---------|-----------|
| **user_id NULL in Lineup-Slots** | `generate_lineup` setzt nur `player_slot_id`, nicht `user_id` | Slot-Suche per JOIN mit `cs_team_players.claimed_by` als Fallback; Backfill bestehender Slots |
| **Trigger überspringt bei wiederholter Absage** | Guard `OLD.status = 'no'` verhinderte erneute Ausführung | Guard entfernt; `auto_handle_absence` ist idempotent |
| **Kein Fallback im Flutter-Code** | App verliess sich ausschliesslich auf den DB-Trigger | Expliziter `triggerAutoPromotion()` RPC-Aufruf nach `setAvailability('no')` |
| **locked-Check beim absagenden Spieler** | Gesperrte Slots konnten nicht verarbeitet werden | `locked`-Check nur bei Reserve-Suche, nicht beim absagenden Spieler |

### 4.3 Doppelter Schutz (Belt & Suspenders)

Die Auto-Promotion wird auf **zwei Wegen** ausgelöst:

1. **DB-Trigger** (`trg_auto_promote_on_absence`): Feuert synchron beim Upsert auf `cs_match_availability`
2. **Expliziter RPC** (`LineupService.triggerAutoPromotion`): Wird von Flutter nach dem Upsert aufgerufen

Da `auto_handle_absence` **idempotent** ist (liefert `"not_starter"` wenn der Slot schon verarbeitet wurde), schadet ein doppelter Aufruf nicht.

---

## 5. Nachrücker: Bestätigung & Absage

### 5.1 Promotion-Banner

Wenn der nachrückende Spieler die App öffnet, prüft `_load()` (Zeile 452–468):

```dart
final events = await LineupService.getEvents(widget.matchId);
for (final ev in events) {
  if (ev['event_type'] == 'auto_promotion' &&
      ev['confirmed_at'] == null) {
    final payload = ev['payload'] as Map<String, dynamic>?;
    if (payload != null && payload['to'] == uid) {
      pendingPromotion = ev;
      break;
    }
  }
}
```

Wenn ein unbestätigtes `auto_promotion`-Event existiert, wird ein **grüner Banner** angezeigt:

- **Text:** „Du bist nachgerückt! [Name] hat abgesagt. Du spielst jetzt als Starter."
- **Button 1:** „Bestätigen" → `_confirmPromotion()`
- **Button 2:** „Absagen" → `_declinePromotion()`

Der Banner erscheint sowohl im **Übersicht-Tab** als auch im **Aufstellung-Tab**.

### 5.2 Bestätigung (`_confirmPromotion`)

**Datei:** `lib/screens/match_detail_screen.dart` (Zeile 691–704)

1. Ruft `LineupService.confirmPromotion(eventId)` auf
2. RPC `cs_confirm_promotion`: setzt `confirmed_at = now()` auf dem Event
3. Banner verschwindet
4. Seite wird neu geladen

### 5.3 Absage (`_declinePromotion`)

**Datei:** `lib/screens/match_detail_screen.dart` (Zeile 707–712)

1. Banner wird sofort entfernt (optimistic UI)
2. Ruft `_setAvailability('no')` auf → identischer Ablauf wie bei Starter-Absage
3. Da der nachrückende Spieler **jetzt Starter ist** (wurde ja befördert), löst seine Absage erneut die Auto-Promotion aus → **nächster Ersatzspieler rückt nach**
4. Seite wird neu geladen

**Kaskade:** Wenn auch der zweite Ersatzspieler absagt, rückt der dritte nach, usw.

---

## 6. Push-Benachrichtigungen

### 6.1 Trigger-Kette

Wenn `auto_handle_absence` ein `auto_promotion`-Event in `cs_lineup_events` einfügt, wird folgende Trigger-Kette ausgelöst:

```
cs_lineup_events (INSERT)
    └─ trg_emit_lineup_event_to_cs_events → cs_events (INSERT)
        └─ trg_cs_event_fanout → cs_event_deliveries (INSERT pro Empfänger)
            └─ trg_bridge_delivery_to_notification → cs_notifications + Push
```

### 6.2 Empfänger

Der nachrückende Spieler erhält eine Push-Benachrichtigung mit der Information, dass er zum Starter befördert wurde.

### 6.3 Voraussetzung

Alle vier Trigger müssen in der Datenbank existieren. Die Diagnose am Ende von `cs_fix_autopromote_v4.sql` prüft dies:

- `trg_emit_lineup_event_to_cs_events`
- `trg_cs_event_fanout`
- `trg_bridge_delivery_to_notification`

---

## 7. Datenfluss-Zusammenfassung

```
┌─────────────────────────────────────────────────────────────────┐
│                    STARTER SAGT AB                               │
│  (Captain oder Spieler – identischer Ablauf)                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Flutter: _setAvailability('no')                                │
│    1. MatchService.setAvailability(status: 'no')                │
│    2. LineupService.triggerAutoPromotion() ← Sicherheitsnetz    │
│    3. _load() → UI aktualisieren                                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  DB: auto_handle_absence(match_id, user_id)                     │
│    1. Lineup published? ✓                                       │
│    2. Starter-Slot finden (user_id ODER claimed_by)             │
│    3. Nächsten Reserve finden (nicht locked)                     │
│    4. Reserve → Starter (slot_type, position, user_id)          │
│    5. Absent-Slot löschen                                       │
│    6. Reserves renummern                                        │
│    7. cs_lineup_events INSERT → Push-Kette                      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Nachrücker sieht:                                              │
│    • Push-Benachrichtigung (via FCM)                            │
│    • Promotion-Banner in der App                                │
│    • Buttons: "Bestätigen" / "Absagen"                          │
│                                                                  │
│  Bei "Absagen" → Kette startet erneut für nächsten Ersatz       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Fehlerbehandlung

| Situation | Verhalten |
|-----------|-----------|
| Kein Lineup vorhanden | RPC liefert `{"promoted": false, "reason": "no_lineup"}` — kein Fehler |
| Lineup ist Draft (nicht published) | RPC liefert `"not_published"` — kein Fehler |
| Absagender ist kein Starter | RPC liefert `"not_starter"` — kein Fehler |
| Kein Ersatz verfügbar | RPC liefert `"no_reserve"`, Event `no_reserve` wird geloggt |
| Alle Ersätze gesperrt (locked) | Wie "kein Ersatz" — `locked` Slots werden übersprungen |
| SQL-Fehler in `auto_handle_absence` | Äusserer EXCEPTION-Block fängt alles, loggt Warning, gibt `"rpc_exception"` zurück |
| Trigger-Fehler | EXCEPTION-Block in Trigger-Funktion — Verfügbarkeitsänderung geht **immer** durch |
| Flutter RPC-Fehler | try/catch mit `debugPrint` — blockiert UI nicht |

---

## 9. Relevante SQL-Dateien (chronologisch)

| Datei | Status | Beschreibung |
|-------|--------|-------------|
| `sql/cs_auto_promote_fix.sql` | ⚠️ Veraltet | Erste Version mit `locked`-Check beim Starter und Guard für Status 'no' |
| `sql/cs_fix_captain_availability.sql` | ⚠️ Veraltet | Entfernte `locked`-Check, aber Guard für Status 'no' blieb |
| **`sql/cs_fix_autopromote_v4.sql`** | ✅ Aktuell | Vollständiger Fix: Backfill, JOIN-Fallback, kein Guard, expliziter RPC |

---

## 10. Voraussetzungen für korrekte Funktion

1. **SQL `cs_fix_autopromote_v4.sql` muss im Supabase SQL Editor ausgeführt sein**
2. Aufstellung muss Status `published` haben (nicht `draft`)
3. Absagender muss einen Starter-Slot haben (direkt `user_id` oder via `cs_team_players.claimed_by`)
4. Mindestens ein nicht-gesperrter Reserve-Slot muss existieren
5. Push-Trigger-Kette muss vollständig sein (3 Trigger: emit → fanout → bridge)
6. Flutter-App muss die aktuelle Version mit dem expliziten RPC-Aufruf verwenden
