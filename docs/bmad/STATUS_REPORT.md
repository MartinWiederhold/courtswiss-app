# BMAD Status Report

> Aktualisiert: 2026-02-11 | Basis: `docs/bmad/*` + `lib/**` + `sql/**`

---

## Zusammenfassung (Ampel)

| Bereich | Status |
|---|---|
| **Auth & Profil** | 🟢 Implementiert |
| **Team-Management** | 🟢 Implementiert |
| **Begegnungen (Matches)** | 🟢 Implementiert |
| **Verfügbarkeit** | 🟢 Implementiert |
| **Aufstellung (Lineup)** | 🟡 Teilweise (Auto-Lineup ✅, Drag & Drop ❌, Regelverstoss-Warnung ❌) |
| **Ersatzspieler-Kette** | 🟢 Implementiert (Auto-Nachrücken, Sub-Requests, Events) |
| **Fahrgemeinschaften** | 🟡 Teilweise (DB ✅, RPCs ✅, UI-Anzeige ✅, initiales Laden gefixt ✅, Stabilität noch offen) |
| **Essen & Spesen** | 🔴 Nicht implementiert |
| **Benachrichtigungen / Push** | 🟡 Teilweise (Events ✅, Push-Pipeline DB ✅, FCM-Token ✅, echter Push-Send ❌) |
| **Tests** | 🔴 Nur Default-Widget-Test vorhanden |

**Gesamteinschätzung: 🟡 MVP ~65 % fertig** – Kernflows (Team, Match, Lineup, Ersatz) stehen; Carpool existiert als instabiler Prototyp; Expenses und Tests fehlen komplett.

---

## BMAD-Docs Check (Tabelle)

| Datei | Status | Lücke 1 | Lücke 2 | Lücke 3 | Next Action |
|---|---|---|---|---|---|
| `README.md` | ✅ OK | – | – | – | – |
| `01_product_brief.md` | 🟡 Unvollst. | Kein Datenmodell-Detail für Fahrgemeinschaften / Spesen | Tabellen-Prefix `cs_` ist nicht spezifiziert | Kein Hinweis auf Anonymous Auth | Prefix `cs_` dokumentieren; Carpool/Expense-Spec schärfen |
| `02_prd.md` | 🟡 Unvollst. | Keine Detailspezifikation für Ersatz-Timeout / Timer | Keine Spezifikation für Push-Payload-Format | Offline-Lesbarkeit nicht detailliert | Timer-Spec + Push-Payload-Spec nachliefern |
| `03_architecture.md` | 🔴 Veraltet | Tabellen-Prefix im Doc = **`ic_`**, Code nutzt **`cs_`** | Fehlende Tabellen: `cs_events`, `cs_event_reads`, `cs_device_tokens`, `cs_notification_prefs`, `cs_event_deliveries`, `cs_lineup_events`, `cs_match_availability`, `cs_app_profiles`, `cs_carpool_offers`, `cs_carpool_passengers`, `cs_sub_requests` | Keine Erwähnung von Firebase/FCM-Integration im Datenmodell | Alle `ic_`→`cs_` ändern; Tabellenliste aktualisieren; FCM-Architektur + Carpool-Tabellen ergänzen |
| `04_stories.md` | 🟡 Unvollst. | Fehlende Stories für Event-/Notification-Inbox (Epic 10+) | Fehlende Stories für Push-Pipeline, Push-Preferences, Settings | Fehlende Stories für Player-Claim-Flow, Avatar Upload | Stories für Epics 10–14 (Events, Push, Claim, Avatar, Lineup Events) nachliefern |
| `05_test_plan.md` | 🔴 Veraltet | Referenziert `ic_*` Tabellen statt `cs_*` | Kein Abschnitt für Push/FCM-Tests, Carpool-Tests | Seed-Daten passen nicht zum aktuellen Schema (`ic_*` statt `cs_*`) | Komplett überarbeiten; Push-Tests, Carpool-Tests + korrektes DB-Schema ergänzen |

---

## Konsistenz-Check

### 01 → 02 (Product Brief → PRD)
| Thema | Konsistent? | Detail |
|---|---|---|
| Features MVP | ✅ | Brief und PRD decken dieselben Epics ab |
| Rollen (Captain/Spieler) | ✅ | Übereinstimmend |
| Ersatzlogik | 🟡 | PRD nennt "Zeitlimit konfigurierbar" – Brief nicht; kein konkreter Default definiert |
| Offline-Lesbarkeit | 🟡 | PRD §11 erwähnt "Offline-lesbar" – weder in Brief noch in Architektur konkretisiert |
| Fahrgemeinschaften | ✅ | Beide: Fahrer definiert Auto/Plätze/Treffpunkt, Spieler treten bei |

### 02 → 03 (PRD → Architektur)
| Thema | Konsistent? | Detail |
|---|---|---|
| **Tabellen-Prefix** | ❌ **Widerspruch** | PRD sagt nichts; Architektur sagt `ic_`; **Code nutzt `cs_`** |
| Entitäten-Abdeckung | 🔴 | Architektur fehlen: `cs_events`, `cs_event_reads`, `cs_device_tokens`, `cs_notification_prefs`, `cs_event_deliveries`, `cs_app_profiles`, `cs_team_players`, `cs_invites`, `cs_lineup_events`, `cs_carpool_offers`, `cs_carpool_passengers`, `cs_sub_requests` |
| Business-Logik-Verteilung | 🟡 | Architektur sagt "Ersatzketten server-seitig" ✅, aber Push-Trigger, Fanout-Logik (DB-Triggers) und Carpool-RPCs nicht dokumentiert |
| FCM | ✅ | Brief, PRD und Architektur erwähnen FCM |

### 03 → 04 (Architektur → Stories)
| Thema | Konsistent? | Detail |
|---|---|---|
| Epics | 🟡 | Stories decken Epics 1–9 ab; es fehlen Stories für Events/Inbox (Epic 10+), Push-Pipeline, Settings, Player-Claim, Avatar |
| Detailgrad | 🟡 | Stories sind eher Outline-Level; keine Sub-Tasks oder technische Acceptance Criteria |
| Carpool | 🟡 | Stories für Epic 7 existieren auf Outline-Level; Implementation existiert bereits teilweise, aber Stories reflektieren den Stand nicht |

### 04 → 05 (Stories → Testplan)
| Thema | Konsistent? | Detail |
|---|---|---|
| Test-Coverage pro Epic | 🟡 | Testplan deckt Epics 1–8 ab, aber nicht Events/Push/Settings/Carpool |
| Testdaten | ❌ | Seed spricht von `ic_*` Tabellen – Code nutzt `cs_*` |
| Unit-Tests | 🔴 | Im Testplan beschrieben, im Repo nur ein Default-Counter-Test vorhanden |
| Carpool-Tests | 🔴 | Keine Testfälle für Carpool-Offers, Join/Leave, RLS-Policies |

---

## App Implementierungs-Check (Story Mapping)

### Screens (lib/screens/)
| Screen | Zweck |
|---|---|
| `auth_gate.dart` | Auth-State-Router + Invite-Accept |
| `auth_screen.dart` | Login (Magic Link) |
| `teams_screen.dart` | Team-Liste + Unread-Badge |
| `team_detail_screen.dart` | Team-Detail: Members, Matches, Invite, Settings, Avatar |
| `create_match_screen.dart` | Match erstellen |
| `match_detail_screen.dart` | Match: Availability, Lineup, Generate, Publish, Carpool, Sub-Requests |
| `claim_screen.dart` | Spieler-Zuordnung (Player Claim) |
| `event_inbox_screen.dart` | Notification Inbox (Events) |
| `notifications_screen.dart` | Legacy-Notifications (cs_notifications) |
| `notification_settings_screen.dart` | Push-Preferences |

### Services (lib/services/)
| Service | Zweck |
|---|---|
| `profile_service.dart` | Profil (cs_app_profiles) |
| `team_service.dart` | Teams CRUD |
| `member_service.dart` | Team-Members |
| `invite_service.dart` | Invite-Link erstellen/akzeptieren |
| `match_service.dart` | Matches + Availability |
| `lineup_service.dart` | Lineups + Slots + Publish |
| `team_player_service.dart` | Spieler-Zuordnung / Ranking |
| `roster_service.dart` | Kader-Verwaltung |
| `event_service.dart` | Events (cs_events + cs_event_reads) |
| `notification_service.dart` | Legacy-Notifications (Realtime) |
| `push_service.dart` | FCM Token + Foreground/Background |
| `device_token_service.dart` | Device-Token Registration (cs_device_tokens) |
| `push_prefs_service.dart` | Notification Preferences |
| `local_notification_service.dart` | Local Notifications (flutter_local_notifications) |
| `deep_link_service.dart` | Deep Links / Invite-Tokens |
| `avatar_service.dart` | Avatar-Upload (Storage) + Signed URLs |
| `carpool_service.dart` | Fahrgemeinschaften (cs_carpool_offers + cs_carpool_passengers) |
| `sub_request_service.dart` | Ersatzanfragen (cs_sub_requests) |

### Models (lib/models/)
| Model | Zweck |
|---|---|
| `carpool_offer.dart` | CarpoolOffer + CarpoolPassenger Modelle |

### Story → Implementation Mapping

| Story | Screen(s) | Service(s) | Status |
|---|---|---|---|
| **US-1.1** Auth & Profil | `auth_gate`, `auth_screen` | `profile_service` | ✅ Implementiert (Anonymous + Magic Link) |
| **US-2.1** Team erstellen | `teams_screen`, `team_detail_screen` | `team_service` | ✅ Implementiert |
| **US-2.2** Spieler einladen | `team_detail_screen`, `auth_gate` | `invite_service`, `deep_link_service` | ✅ Implementiert (Share-Link + Deep Link) |
| **US-3.1** Begegnung erstellen | `create_match_screen`, `team_detail_screen` | `match_service` | ✅ Implementiert |
| **US-4.1** Verfügbarkeit | `match_detail_screen` | `match_service` | ✅ Implementiert (yes/no/maybe Buttons) |
| **US-5.1** Auto-Aufstellung | `match_detail_screen` | `lineup_service` | ✅ Implementiert (Ranking-basiert, Generate + Publish) |
| **US-5.2** Manuelle Anpassung | `match_detail_screen` | `lineup_service` | 🟡 Teilweise (Reorder via RPC + Drag & Drop UI vorhanden, **Drag & Drop noch instabil**) |
| **US-6.1** Ersatzanfrage | `match_detail_screen` | `lineup_service`, `sub_request_service`, `event_service` | ✅ Implementiert (Auto-Nachrücken via DB-Trigger + Event + Sub-Request-UI) |
| **US-7.1** Fahrgemeinschaft erstellen | `match_detail_screen` | `carpool_service` | 🟡 Teilweise (DB + RPCs + UI vorhanden; initiales Laden gefixt; Stabilität offen) |
| **US-7.2** Fahrgemeinschaft beitreten | `match_detail_screen` | `carpool_service` | 🟡 Teilweise (Join/Leave RPCs + Buttons vorhanden; Realtime-Updates aktiv) |
| **US-8.1** Essen zusagen | – | – | 🔴 **Nicht implementiert** |
| **US-8.2** Spesen erfassen | – | – | 🔴 **Nicht implementiert** |
| **US-9.1** Benachrichtigungen | `event_inbox_screen`, `notification_settings_screen` | `event_service`, `push_service`, `push_prefs_service`, `device_token_service` | 🟡 DB-Pipeline ✅, FCM-Token ✅, echter Push-Send ❌ |
| *(nicht in Stories)* Player Claim | `claim_screen` | `team_player_service` | ✅ Implementiert (fehlt als Story) |
| *(nicht in Stories)* Avatar Upload | `team_detail_screen` | `avatar_service` | ✅ Implementiert (fehlt als Story) |
| *(nicht in Stories)* Lineup Events | `event_inbox_screen` | `event_service` | ✅ Implementiert (fehlt als Story) |
| *(nicht in Stories)* Sub-Requests | `match_detail_screen` | `sub_request_service` | ✅ Implementiert (fehlt als eigene Story) |

---

## Offene Risiken

| # | Risiko | Impact | Mitigation |
|---|---|---|---|
| 1 | **Architektur-Doc veraltet** (`ic_` vs `cs_`, fehlende Tabellen inkl. Events, Push, Profiles, Carpool, Sub-Requests) | Neue Entwickler werden verwirrt; falsche Annahmen bei Erweiterungen | `03_architecture.md` vollständig aktualisieren |
| 2 | **Keine automatisierten Tests** (nur Default-Counter-Test) | Regressionen bei jedem Change; kein CI möglich | Mindestens Service-Unit-Tests + Widget-Tests schreiben |
| 3 | **Push-Send noch nicht aktiv** | User bekommen keine echten Push-Notifications; DB-Pipeline (cs_event_deliveries) produziert nur `pending`-Rows | Edge Function / Cloud Function für Delivery-Processing implementieren |
| 4 | **Carpool instabil** (initiales Laden war defekt, RLS-Policies neu, Realtime-Updates abhängig von zwei Channels) | Offers verschwinden nach Refresh oder werden bei Members nicht angezeigt | Stabilisieren: initiales Laden gefixt ✅; RLS-Policies verifizieren; E2E-Test Carpool-Flow |
| 5 | **Essen & Spesen komplett fehlend** | MVP-Scope laut Brief/PRD nicht erfüllt | Priorisieren oder explizit aus MVP ausschliessen |
| 6 | **Drag & Drop Lineup** | US-5.2 hat Drag & Drop UI, aber Stabilität/UX noch nicht validiert | Testen und ggf. verbessern |
| 7 | **Ersatz-Timeout nicht implementiert** | PRD §7 fordert "Zeitlimit pro Anfrage konfigurierbar" – Sub-Requests haben kein Timeout | Timer-Logik + DB-Column + Cron/Trigger implementieren |
| 8 | **Legacy vs. neue Notifications** | `notifications_screen.dart` (cs_notifications) + `event_inbox_screen.dart` (cs_events) koexistieren | Konsolidieren oder Legacy entfernen |
| 9 | **Stories / Docs nicht synchron mit Code** | `04_stories.md` fehlen Epics 10–14; `05_test_plan.md` referenziert `ic_*` | Docs aktualisieren |

---

## Next Steps (priorisiert)

| # | Aktion | Prio | Aufwand |
|---|---|---|---|
| 1 | **`03_architecture.md` aktualisieren**: `ic_`→`cs_`, alle fehlenden Tabellen ergänzen (inkl. `cs_carpool_*`, `cs_sub_requests`, `cs_events`, `cs_device_tokens` etc.), FCM-Architektur + Carpool-Flow dokumentieren | 🔴 Hoch | Klein (2h) |
| 2 | **`04_stories.md` erweitern**: Stories für Epics 10–14 (Events/Inbox, Push-Pipeline, Player-Claim, Avatar, Lineup Events) nachliefern; bestehende Carpool-Stories (Epic 7) auf aktuellen Implementierungsstand anpassen | 🔴 Hoch | Klein (1–2h) |
| 3 | **`05_test_plan.md` überarbeiten**: `ic_`→`cs_`, Push/FCM-Tests, Event-Tests, Carpool-Tests ergänzen; Seed-Daten an aktuelles Schema anpassen | 🟡 Mittel | Klein (1h) |
| 4 | **Push-Send implementieren**: Supabase Edge Function oder Cloud Function die `cs_event_deliveries` mit `status='pending'` verarbeitet und via FCM sendet | 🔴 Hoch | Mittel (4–8h) |
| 5 | **Fahrgemeinschaften stabilisieren**: RLS-Policies verifizieren (cs_carpool_rls_patch.sql anwenden), Carpool E2E testen (Captain erstellt → Member sieht + Join/Leave), Realtime-Channel Robustheit prüfen | 🔴 Hoch | Klein (2–3h) |
| 6 | **Essen & Spesen (Epic 8)** implementieren: DB-Tabellen (`cs_dinner_rsvp`, `cs_expenses`, `cs_expense_shares`), Service, UI, Storage für Belege | 🟡 Mittel | Mittel (8–12h) |
| 7 | **Unit-Tests schreiben**: Lineup-Sortierung, Carpool-Service, Event-Service, Invite-Flow, Sub-Request-Flow | 🟡 Mittel | Mittel (4–6h) |
| 8 | **Drag & Drop Lineup** stabilisieren und UX validieren (US-5.2) | 🟢 Niedrig | Klein (2–3h) |
| 9 | **Legacy `notifications_screen.dart`** entfernen oder mit `event_inbox_screen.dart` konsolidieren | 🟢 Niedrig | Klein (1h) |
| 10 | **Scope-Entscheid**: Offline-Support + Ersatz-Timeout + Doppel-Aufstellung → MVP oder Post-MVP? Im PRD dokumentieren | 🟡 Mittel | Klein (Entscheid) |
