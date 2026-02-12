# BMAD Status Report

> Aktualisiert: 2026-02-12 | Basis: `docs/bmad/*` + `lib/**` + `sql/**` + `test/**`

---

## Zusammenfassung (Ampel)

| Bereich | Status |
|---|---|
| **Auth & Profil** | 🟢 Implementiert |
| **Team-Management** | 🟢 Implementiert (inkl. Sportart-Auswahl, sport_key, Swipe-to-Delete) |
| **Begegnungen (Matches)** | 🟢 Implementiert |
| **Verfügbarkeit** | 🟢 Implementiert |
| **Aufstellung (Lineup)** | 🟡 Teilweise (Auto-Lineup ✅, Drag & Drop ❌, Regelverstoss-Warnung ❌) |
| **Ersatzspieler-Kette** | 🟢 Implementiert (Auto-Nachrücken, Sub-Requests, Events) |
| **Fahrgemeinschaften** | 🟢 Implementiert (Create ✅, Join/Leave ✅, Delete ✅, Multi-Offer ✅, Persistenz ✅) |
| **Essen & Spesen** | 🟢 Implementiert (Dinner RSVPs ✅, Expenses + Shares ✅, Split nur "yes" ✅, is_paid Toggle ✅, Payer auto-paid ✅) |
| **Benachrichtigungen / Push** | 🟡 Teilweise (Events ✅, Push-Pipeline DB ✅, FCM-Token ✅, echter Push-Send ❌) |
| **Sportart-Auswahl** | 🟢 Implementiert (SportSelectionScreen ✅, Team Header-Banner ✅, Assets ✅, "Andere" ✅) |
| **Tests** | 🟡 Teilweise (3 Unit-Test-Suites: Carpool, Dinner, Expense ✅; Widget-Test Default ⚠️) |

**Gesamteinschätzung: 🟡 MVP ~82 % fertig** – Alle Kernflows (Team, Match, Lineup, Ersatz, Carpool, Essen/Spesen) stehen und sind funktional. Offene Lücken: Drag & Drop Lineup (US-5.2), Regelverstoss-Warnung, Ersatz-Timeout und echter Push-Send (iOS).

---

## BMAD-Docs Check (Tabelle)

| Datei | Status | Lücke 1 | Lücke 2 | Lücke 3 | Next Action |
|---|---|---|---|---|---|
| `README.md` | ✅ OK | – | – | – | – |
| `01_product_brief.md` | 🟡 Unvollst. | Kein Datenmodell-Detail für Fahrgemeinschaften / Spesen | Tabellen-Prefix `cs_` ist nicht spezifiziert | Kein Hinweis auf Anonymous Auth | Prefix `cs_` dokumentieren; Carpool/Expense-Spec schärfen |
| `02_prd.md` | 🟡 Unvollst. | Keine Detailspezifikation für Ersatz-Timeout / Timer | Keine Spezifikation für Push-Payload-Format | Offline-Lesbarkeit nicht detailliert | Timer-Spec + Push-Payload-Spec nachliefern |
| `03_architecture.md` | 🔴 Veraltet | Tabellen-Prefix im Doc = **`ic_`**, Code nutzt **`cs_`** | Fehlende Tabellen: `cs_events`, `cs_event_reads`, `cs_device_tokens`, `cs_notification_prefs`, `cs_event_deliveries`, `cs_lineup_events`, `cs_match_availability`, `cs_app_profiles`, `cs_carpool_offers`, `cs_carpool_passengers`, `cs_sub_requests`, `cs_dinner_rsvps`, `cs_expenses`, `cs_expense_shares` | Keine Erwähnung von Firebase/FCM-Integration im Datenmodell | Alle `ic_`→`cs_` ändern; Tabellenliste aktualisieren; FCM-Architektur + Carpool/Expense-Tabellen ergänzen |
| `04_stories.md` | 🟡 Unvollst. | Fehlende Stories für Event-/Notification-Inbox (Epic 10+) | Fehlende Stories für Push-Pipeline, Push-Preferences, Settings | Fehlende Stories für Player-Claim-Flow, Avatar Upload, Sportart-Auswahl | Stories für Epics 10–14 + Sportart-Auswahl nachliefern |
| `05_test_plan.md` | 🔴 Veraltet | Referenziert `ic_*` Tabellen statt `cs_*` | Kein Abschnitt für Push/FCM-Tests, Carpool-Tests, Dinner/Expense-Tests | Seed-Daten passen nicht zum aktuellen Schema (`ic_*` statt `cs_*`) | Komplett überarbeiten; alle neuen Domains ergänzen |

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
| Essen & Spesen | ✅ | Beide: Essen-Zusage + Spesenerfassung mit automatischem Split |

### 02 → 03 (PRD → Architektur)
| Thema | Konsistent? | Detail |
|---|---|---|
| **Tabellen-Prefix** | ❌ **Widerspruch** | PRD sagt nichts; Architektur sagt `ic_`; **Code nutzt `cs_`** |
| Entitäten-Abdeckung | 🔴 | Architektur fehlen: `cs_events`, `cs_event_reads`, `cs_device_tokens`, `cs_notification_prefs`, `cs_event_deliveries`, `cs_app_profiles`, `cs_team_players`, `cs_invites`, `cs_lineup_events`, `cs_carpool_offers`, `cs_carpool_passengers`, `cs_sub_requests`, `cs_dinner_rsvps`, `cs_expenses`, `cs_expense_shares` |
| Business-Logik-Verteilung | 🟡 | Architektur sagt "Ersatzketten server-seitig" ✅, aber Push-Trigger, Fanout-Logik (DB-Triggers), Carpool-RPCs und Expense-Split-Logik nicht dokumentiert |
| FCM | ✅ | Brief, PRD und Architektur erwähnen FCM |

### 03 → 04 (Architektur → Stories)
| Thema | Konsistent? | Detail |
|---|---|---|
| Epics | 🟡 | Stories decken Epics 1–9 ab; es fehlen Stories für Events/Inbox (Epic 10+), Push-Pipeline, Settings, Player-Claim, Avatar, Sportart-Auswahl |
| Detailgrad | 🟡 | Stories sind eher Outline-Level; keine Sub-Tasks oder technische Acceptance Criteria |
| Carpool | ✅ | Stories für Epic 7 existieren; Implementation ist vollständig |
| Essen & Spesen | 🟡 | Stories für Epic 8 existieren auf Outline-Level; Implementation ist fertig, Stories reflektieren den Stand nicht vollständig |

### 04 → 05 (Stories → Testplan)
| Thema | Konsistent? | Detail |
|---|---|---|
| Test-Coverage pro Epic | 🟡 | Testplan deckt Epics 1–8 ab, aber nicht Events/Push/Settings/Carpool/Expense |
| Testdaten | ❌ | Seed spricht von `ic_*` Tabellen – Code nutzt `cs_*` |
| Unit-Tests | 🟡 | 3 Test-Suites vorhanden (carpool_passenger, dinner_rsvp, expense_split); Widget-Test ist Default-Counter |
| Carpool-Tests | ✅ | `carpool_passenger_test.dart` deckt CarpoolPassenger.fromMap ab |
| Dinner-Tests | ✅ | `dinner_rsvp_test.dart` deckt DinnerRsvp.fromMap ab |
| Expense-Tests | ✅ | `expense_split_test.dart` deckt ExpenseShare.fromMap + Split-Logik ab |

---

## App Implementierungs-Check (Story Mapping)

### Screens (lib/screens/)
| Screen | Zweck |
|---|---|
| `auth_gate.dart` | Auth-State-Router + Invite-Accept |
| `auth_screen.dart` | Login (Magic Link) |
| `teams_screen.dart` | Team-Liste + Unread-Badge + Swipe-to-Delete |
| `team_detail_screen.dart` | Team-Detail: Members, Matches, Invite, Settings, Avatar, Sport-Header-Banner |
| `create_match_screen.dart` | Match erstellen |
| `match_detail_screen.dart` | Match: Availability, Lineup, Generate, Publish, Carpool, Dinner, Expenses, Sub-Requests |
| `claim_screen.dart` | Spieler-Zuordnung (Player Claim) |
| `event_inbox_screen.dart` | Notification Inbox (Events) |
| `notifications_screen.dart` | Legacy-Notifications (cs_notifications) |
| `notification_settings_screen.dart` | Push-Preferences |
| `sport_selection_screen.dart` | Sportart-Auswahl (Grid mit Bild-Kacheln) |

### Services (lib/services/)
| Service | Zweck |
|---|---|
| `profile_service.dart` | Profil (cs_app_profiles) |
| `team_service.dart` | Teams CRUD (inkl. deleteTeam) |
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
| `dinner_service.dart` | Essen-Zusage (cs_dinner_rsvps) |
| `expense_service.dart` | Spesen (cs_expenses + cs_expense_shares) |
| `sub_request_service.dart` | Ersatzanfragen (cs_sub_requests) |

### Models (lib/models/)
| Model | Zweck |
|---|---|
| `carpool_offer.dart` | CarpoolOffer + CarpoolPassenger Modelle |
| `dinner_rsvp.dart` | DinnerRsvp Model |
| `expense.dart` | Expense + ExpenseShare Modelle |
| `sport.dart` | Sport Model (11 Sportarten inkl. "Andere") |

### Utils (lib/utils/)
| Utility | Zweck |
|---|---|
| `expense_split.dart` | Expense-Split-Logik (Berechnung, nur Dinner "yes" Teilnehmer) |

### Tests (test/)
| Testdatei | Abdeckung |
|---|---|
| `carpool_passenger_test.dart` | CarpoolPassenger.fromMap Parsing (DB column names, legacy alias, edge cases) |
| `dinner_rsvp_test.dart` | DinnerRsvp.fromMap Parsing (alle Felder, optionale Felder, Defaults) |
| `expense_split_test.dart` | ExpenseShare.fromMap + Expense-Split-Logik (is_paid, paid_at, Split-Berechnung) |
| `widget_test.dart` | Default Flutter Widget-Test (Counter) |

### SQL Migrations (sql/)
| Migration | Zweck |
|---|---|
| `cs_teams_sport_key_patch.sql` | sport_key Spalte zu cs_teams |
| `cs_teams_delete_policy_patch.sql` | RLS DELETE Policy für cs_teams (Creator + Captain) |
| `cs_carpool_rls_patch.sql` | RLS Policies für Carpool-Tabellen |
| `cs_dinner_rsvps_patch.sql` | cs_dinner_rsvps Tabelle + RLS |
| `cs_expenses_patch.sql` | cs_expenses + cs_expense_shares Tabellen |
| `cs_expenses_v2_patch.sql` | Expenses V2: is_paid/paid_at, paid_by_user_id Fix, Payer auto-paid |
| `cs_events_patch.sql` | cs_events + cs_event_reads + Trigger-Logik |
| `cs_events_payload_patch.sql` | Event-Payload-Erweiterung |
| `cs_push_pipeline_patch.sql` | Push-Pipeline (cs_event_deliveries, cs_device_tokens, cs_notification_prefs) |
| `cs_sub_requests_patch.sql` | cs_sub_requests Tabelle + RLS |

### Story → Implementation Mapping

| Story | Screen(s) | Service(s) | Status |
|---|---|---|---|
| **US-1.1** Auth & Profil | `auth_gate`, `auth_screen` | `profile_service` | ✅ Implementiert (Anonymous + Magic Link) |
| **US-2.1** Team erstellen | `teams_screen`, `team_detail_screen` | `team_service` | ✅ Implementiert (inkl. Sportart-Auswahl + Swipe-to-Delete) |
| **US-2.2** Spieler einladen | `team_detail_screen`, `auth_gate` | `invite_service`, `deep_link_service` | ✅ Implementiert (Share-Link + Deep Link) |
| **US-3.1** Begegnung erstellen | `create_match_screen`, `team_detail_screen` | `match_service` | ✅ Implementiert |
| **US-4.1** Verfügbarkeit | `match_detail_screen` | `match_service` | ✅ Implementiert (yes/no/maybe Buttons) |
| **US-5.1** Auto-Aufstellung | `match_detail_screen` | `lineup_service` | ✅ Implementiert (Ranking-basiert, Generate + Publish) |
| **US-5.2** Manuelle Anpassung | `match_detail_screen` | `lineup_service` | 🟡 Teilweise (Reorder via RPC vorhanden, **Drag & Drop UI noch nicht stabil/implementiert**) |
| **US-6.1** Ersatzanfrage | `match_detail_screen` | `lineup_service`, `sub_request_service`, `event_service` | ✅ Implementiert (Auto-Nachrücken via DB-Trigger + Event + Sub-Request-UI) |
| **US-7.1** Fahrgemeinschaft erstellen | `match_detail_screen` | `carpool_service` | ✅ Implementiert (Create + Delete + Multi-Offer + Persistenz stabil) |
| **US-7.2** Fahrgemeinschaft beitreten | `match_detail_screen` | `carpool_service` | ✅ Implementiert (Join/Leave + Realtime-Updates) |
| **US-8.1** Essen zusagen | `match_detail_screen` | `dinner_service` | ✅ Implementiert (cs_dinner_rsvps + UI, yes/no/maybe) |
| **US-8.2** Spesen erfassen | `match_detail_screen` | `expense_service` | ✅ Implementiert (cs_expenses + cs_expense_shares, Split nur "yes", is_paid Toggle, Payer auto-paid) |
| **US-9.1** Benachrichtigungen | `event_inbox_screen`, `notification_settings_screen` | `event_service`, `push_service`, `push_prefs_service`, `device_token_service` | 🟡 DB-Pipeline ✅, FCM-Token ✅, echter Push-Send ❌ |
| *(nicht in Stories)* Player Claim | `claim_screen` | `team_player_service` | ✅ Implementiert |
| *(nicht in Stories)* Avatar Upload | `team_detail_screen` | `avatar_service` | ✅ Implementiert |
| *(nicht in Stories)* Lineup Events | `event_inbox_screen` | `event_service` | ✅ Implementiert |
| *(nicht in Stories)* Sub-Requests | `match_detail_screen` | `sub_request_service` | ✅ Implementiert |
| *(nicht in Stories)* Sportart-Auswahl | `sport_selection_screen`, `teams_screen`, `team_detail_screen` | – (Sport Model) | ✅ Implementiert (11 Sportarten + "Andere", Header-Banner, Asset-Bilder) |
| *(nicht in Stories)* Team löschen | `teams_screen` | `team_service` | ✅ Implementiert (Swipe-to-Delete + Confirm Dialog) |

---

## Offene Risiken

| # | Risiko | Impact | Mitigation |
|---|---|---|---|
| 1 | **Architektur-Doc veraltet** (`ic_` vs `cs_`, fehlende Tabellen inkl. Dinner, Expenses, Events, Push, Profiles, Carpool, Sub-Requests) | Neue Entwickler werden verwirrt; falsche Annahmen bei Erweiterungen | `03_architecture.md` vollständig aktualisieren |
| 2 | **Push-Send noch nicht aktiv** | User bekommen keine echten Push-Notifications; DB-Pipeline (cs_event_deliveries) produziert nur `pending`-Rows | Edge Function / Cloud Function für Delivery-Processing implementieren |
| 3 | **Drag & Drop Lineup nicht stabil** (US-5.2) | Manuelle Aufstellungsanpassung per UI nicht nutzbar; Captain muss sich auf Auto-Lineup verlassen | Drag & Drop UI implementieren/stabilisieren |
| 4 | **Ersatz-Timeout nicht implementiert** | PRD §7 fordert "Zeitlimit pro Anfrage konfigurierbar" – Sub-Requests haben kein Timeout | Timer-Logik + DB-Column + Cron/Trigger implementieren |
| 5 | **Regelverstoss-Warnung fehlt** | Captain wird nicht gewarnt wenn Aufstellung gegen Regeln verstösst (z.B. Ranking-Reihenfolge) | Validierungslogik im Lineup-Flow ergänzen |
| 6 | **Legacy vs. neue Notifications** | `notifications_screen.dart` (cs_notifications) + `event_inbox_screen.dart` (cs_events) koexistieren | Konsolidieren oder Legacy entfernen |
| 7 | **Stories / Docs nicht synchron mit Code** | `04_stories.md` fehlen Epics 10–14 + Sportart; `05_test_plan.md` referenziert `ic_*` | Docs aktualisieren |
| 8 | **Test-Coverage begrenzt** | 3 Unit-Test-Suites vorhanden, aber keine Service-Integration-Tests oder Widget-Tests | Weitere Tests schreiben (Lineup, Invite, Sub-Requests) |

---

## Next Steps (priorisiert)

| # | Aktion | Prio | Aufwand |
|---|---|---|---|
| 1 | **Drag & Drop Lineup** (US-5.2): Stabile Drag & Drop UI für manuelle Aufstellungsanpassung implementieren | 🔴 Hoch | Mittel (4–6h) |
| 2 | **Regelverstoss-Warnung**: Captain bei ungültiger Aufstellung warnen (Ranking-Reihenfolge, fehlende Spieler) | 🔴 Hoch | Klein (2–3h) |
| 3 | **Ersatz-Timeout**: Timer-Logik für Sub-Requests (konfigurierbar, auto-Nachrücken nach Ablauf) | 🟡 Mittel | Mittel (4–6h) |
| 4 | **`03_architecture.md` aktualisieren**: `ic_`→`cs_`, alle fehlenden Tabellen ergänzen (inkl. Dinner, Expenses, Carpool, Sub-Requests, Events), FCM-Architektur dokumentieren | 🟡 Mittel | Klein (2h) |
| 5 | **`04_stories.md` erweitern**: Stories für Epics 10–14 (Events/Inbox, Push-Pipeline, Player-Claim, Avatar, Sportart-Auswahl) nachliefern | 🟡 Mittel | Klein (1–2h) |
| 6 | **`05_test_plan.md` überarbeiten**: `ic_`→`cs_`, alle neuen Domains ergänzen (Carpool, Dinner, Expense, Push), Seed-Daten anpassen | 🟡 Mittel | Klein (1h) |
| 7 | **Weitere Unit-Tests**: Lineup-Sortierung, Invite-Flow, Sub-Request-Flow, Service-Integration-Tests | 🟡 Mittel | Mittel (4–6h) |
| 8 | **Legacy Notifications** konsolidieren oder entfernen | 🟢 Niedrig | Klein (1h) |
| 9 | **Push-Send implementieren**: Supabase Edge Function / Cloud Function für `cs_event_deliveries` → FCM | 🟢 Niedrig (ans Ende) | Mittel (4–8h) |
| 10 | **Design / UI Polish**: Konsistentes Design, Animationen, Error States | 🟢 Niedrig (ans Ende) | Mittel (4–8h) |
| 11 | **Scope-Entscheid**: Offline-Support + Doppel-Aufstellung → MVP oder Post-MVP? Im PRD dokumentieren | 🟢 Niedrig | Klein (Entscheid) |
