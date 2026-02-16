# BMAD Status Snapshot — Lineup
> Datum: 2026-02-16  
> Branch: `main`  
> Commit: `19c68ce` — fix: invite join crashes, navigation back handling, light claim sheet

---

## 1) Repo / Build Status

### Git
- **Branch:** `main`
- **Letzter Commit:** `19c68ce` — fix: invite join crashes, navigation back handling, light claim sheet
- **`git status`:** Clean — keine unstaged/untracked Änderungen

### Flutter
- **Flutter Version:** 3.38.4 (stable, 2025-12-03)
- **Dart Version:** 3.10.3
- **`flutter doctor -v` Kurzfazit:** Nicht ausgeführt (Sandbox-Einschränkung), letzter bekannter Stand OK
- **`flutter analyze` Ergebnis:** **0 Errors, 0 Warnings, 12 Infos**
  - 4× `use_build_context_synchronously` in `claim_screen.dart` (false positives — nutzen `navigatorKey.currentContext`)
  - 3× `use_build_context_synchronously` in `profil_screen.dart`
  - 1× `control_flow_in_finally` in `teams_screen.dart`
  - 2× `dangling_library_doc_comments` (utils)
  - 2× `use_null_aware_elements` (service + test)
- **iOS Build (Debug):** Nicht getestet in dieser Session (kein Device verbunden)
- **Android Build (Debug):** Nicht getestet in dieser Session

---

## 2) Fixes seit dem letzten Report

### Crash-Fixes (Invite/Join Flow)
- **`_dependents.isEmpty` Assertion** — `MediaQuery.of(ctx)` innerhalb `StatefulBuilder` durch `MediaQuery.of(sheetCtx)` (outer route context) ersetzt, damit der `StatefulBuilder` kein `MediaQuery`-Dependent wird (Keyboard-Dismiss während Exit-Animation triggert keinen Rebuild mehr). Betrifft: `auth_gate.dart`, `team_detail_screen.dart` (3 Sheets).
- **`_children.contains(child)` Assertion** — Zwei Fixes:
  1. `TextEditingController.dispose()` in `_showMandatoryNameDialog` mit `addPostFrameCallback` deferred (Controller wurde während der Sheet-Exit-Animation disposed, während `TextField` noch mounted war).
  2. `_navigateToTeam` deferred Push um ein Frame via `Completer` + `addPostFrameCallback` (verhindert Same-Frame Pop+Push im Navigator-Overlay).
- **Global Error Handler** in `main.dart` — `FlutterError.onError` + `PlatformDispatcher.instance.onError` loggen Fehler in die Console statt Red-Screen (Safety Net).

### UX / Navigation Fixes
- **AuthScreen Back/Close** — Neuer Parameter `showClose` (default `false`). Wenn `true`: AppBar mit ✕-Button. Auto-Pop nach erfolgreichem Login/Register. Callers: `teams_screen.dart` ("Konto erforderlich" Sheet) und `profil_screen.dart` übergeben `showClose: true`.
- **"Wie heisst du?" Sheet Light Design** — Komplettes Redesign von Dark-Theme (blackCard, onDarkPrimary) auf Light-Theme (white, titleLarge, bodyMedium, Theme-InputDecoration). Drag Handle + zentriertes Icon hinzugefügt, konsistent mit anderen Sheets.

### Branding
- Invite Deep Link: `courtswiss://join` → `lineup://join` (iOS Info.plist, Android Manifest, `invite_service.dart`, `deep_link_service.dart`)
- Auth Deep Links (`io.courtswiss://login`, `io.courtswiss://reset-password`) bleiben **unverändert**
- UI-Strings: "CourtSwiss" → "Lineup" in Toasts, Share-Text, Notification Fallbacks, Tab-Titel
- `kAppName = 'Lineup'` in `lib/constants/app_constants.dart`
- Android Notification Channel: `courtswiss_default` → `lineup_default`

### Push Notifications (Infrastruktur)
- `ios/Runner/Runner.entitlements` mit `aps-environment = production` erstellt
- `project.pbxproj`: `CODE_SIGN_ENTITLEMENTS` verknüpft
- `push_service.dart`: `Firebase.initializeApp()` im Background-Handler, `setForegroundNotificationPresentationOptions`, APNs/FCM Diagnostic Logging
- Business Push Triggers (SQL): Expenses, Dinner RSVP, Carpool, Match Reminders, Availability, Expense Share Paid/Due
- Edge Functions: `send-push` (FCM v1 API), `match-reminders` (Cron)
- SQL Patches: `cs_business_notifications_v2_patch.sql` (vollständig, merged v1+v2)

---

## 3) Aktuelle Blocker / bekannte Repros

### Pflicht-Checkliste

- [x] Invite Join → Name speichern → kein Flutter Red Screen mehr
  - Fix: MediaQuery sheetCtx, Controller defer, _navigateToTeam defer
  - **Muss auf Device verifiziert werden** (Crash war nur auf Real Device reproduzierbar)
- [x] Re-Join Shared Team stabil
  - Fix: `_processingInvite` Guard, `navigatorKey` für alle post-await Navigationen
- [x] AuthScreen aus „Konto erforderlich" hat Back/Close
  - Fix: `AuthScreen(showClose: true)` mit AppBar ✕-Button
- [x] „Wie heisst du?" BottomSheet im Light Design
  - Fix: Komplett auf CsColors.white + CsTextStyles.titleLarge/bodyMedium umgestellt
- [x] Keine doppelten Navigations-Pops
  - Fix: `_processingInvite` Flag, Frame-Deferral in `_navigateToTeam`

### Offene Items (nicht Blocker, aber zu verifizieren auf Device)

| # | Titel | Status |
|---|---|---|
| 1 | Push Notifications auf echtem iPhone testen (FCM Token → cs_device_tokens → send-push Edge Function → Notification erscheint) | **Noch nicht getestet** |
| 2 | SQL Patches (`cs_business_notifications_v2_patch.sql`) auf Supabase Production ausführen | **Noch nicht ausgeführt** |
| 3 | Edge Functions (`send-push`, `match-reminders`) auf Supabase deployen | **Noch nicht deployed** |
| 4 | Cron-Jobs für `match-reminders` und `send-push` in Supabase einrichten | **Noch nicht eingerichtet** |
| 5 | Bundle ID `com.example.swisscourt` → Production ID ändern (für App Store) | **Noch nicht geändert** |
| 6 | `email_verification_pending_screen.dart` Resend-Button + Localization testen | **Implementiert, nicht getestet** |

---

## 4) Navigation / Auth Status

| Bereich | Status |
|---|---|
| **AuthGate: No Session** | Zeigt `AuthScreen()` (ohne Back/Close) ✅ |
| **AuthGate: Session vorhanden** | Zeigt `LoggedInScreen` → `MainTabScreen` ✅ |
| **AuthGate: Anon Invite (kein Session)** | Erstellt Anon-Session on-demand, dann `LoggedInScreen` → Invite Flow ✅ |
| **IndexedStack Main Tabs** | 3 Tabs (Teams, Spiele, Profil) mit `IndexedStack` — State preserved ✅ |
| **Invite → Anon → Register Upgrade** | Implementiert (`updateUser` mit emailRedirectTo), **nicht E2E getestet** |
| **Invite → Login → Migration** | `IdentityLinkService.migrateIfNeeded()` implementiert, **nicht E2E getestet** |
| **Deep Link Scheme** | Invite: `lineup://join?token=...` ✅, Auth: `io.courtswiss://login` + `io.courtswiss://reset-password` ✅ |
| **PKCE Auth Flow** | `AuthFlowType.pkce` in Supabase.initialize ✅ |
| **Password Recovery** | `AuthChangeEvent.passwordRecovery` → `ResetPasswordScreen` push ✅ |

---

## 5) Push / Email / Production Konfiguration

### Bundle ID
- **Aktuell:** `com.example.swisscourt` (iOS + Android + GoogleService-Info.plist)
- **Ziel:** Eigene Production Bundle ID (z.B. `app.lineup.ios` o.ä.)
- **Bereits geändert?** ❌ Nein — noch auf Beispiel-ID

### Push (Firebase)
- **iOS APNs Token sichtbar?** Implementiert (Diagnostic Logging), **nicht auf Device verifiziert**
- **FCM Token sichtbar?** Implementiert (Logging bei `getToken()`), **nicht auf Device verifiziert**
- **Eintrag in `cs_device_tokens`?** Code vorhanden (`push_service.dart` → Upsert), **nicht verifiziert**
- **`aps-environment`:** `production` ✅
- **`UIBackgroundModes`:** `remote-notification` ✅
- **Background Handler:** `Firebase.initializeApp()` im Background-Isolate ✅
- **Foreground Presentation:** `setForegroundNotificationPresentationOptions(alert, badge, sound)` ✅
- **Edge Function `send-push`:** Implementiert (FCM v1 API), **nicht deployed**
- **Edge Function `match-reminders`:** Implementiert, **nicht deployed**

### Supabase Email
- **SendGrid aktiv?** Konfiguriert laut vorherigem BMAD-Report, **nicht in dieser Session verifiziert**
- **Confirmation Mail getestet?** Implementiert (PKCE + redirect `io.courtswiss://login`), **E2E nicht getestet**
- **Password Recovery getestet?** Implementiert (redirect `io.courtswiss://reset-password`), **E2E nicht getestet**

---

## 6) Einschätzung Release Readiness

### Interner Test möglich?
**Ja, mit Einschränkungen.** Die App ist intern testbar für:
- Team erstellen, Spieler hinzufügen, Lineup verwalten
- Invite-Link teilen und beitreten
- Spesen, Essen, Fahrgemeinschaften
- Login / Register / Password Reset Flow

### Blocker für App Store / Play Store

| # | Blocker | Priorität |
|---|---|---|
| 1 | **Bundle ID ändern** — `com.example.swisscourt` ist keine gültige Production-ID | 🔴 Kritisch |
| 2 | **Firebase iOS App registrieren** mit der finalen Bundle ID | 🔴 Kritisch |
| 3 | **Push Notifications E2E verifizieren** — SQL Patches ausführen, Edge Functions deployen, Crons einrichten, auf Device testen | 🟡 Hoch |
| 4 | **APNs Auth Key (.p8)** in Firebase Console prüfen + Production-Bundle-ID matchen | 🟡 Hoch |
| 5 | **Supabase Redirect URLs** anpassen wenn Bundle ID sich ändert | 🟡 Hoch |
| 6 | **App Icons + Splash Screen** für "Lineup" Branding | 🟡 Mittel |
| 7 | **Localization Review** — Restliche hardcoded Strings in Sheets/Dialoge prüfen | 🟢 Nice-to-have |
| 8 | **Crash-Fixes auf Device verifizieren** — `_dependents.isEmpty` + `_children.contains(child)` | 🟡 Hoch |

---

## Appendix: Dateistruktur (Key Files)

```
lib/
├── constants/app_constants.dart          # kAppName = 'Lineup'
├── main.dart                             # Global error handler, navigatorKey
├── screens/
│   ├── auth_gate.dart                    # AuthGate + LoggedInScreen (invite flow, name dialog)
│   ├── auth_screen.dart                  # Login/Register (showClose param)
│   ├── claim_screen.dart                 # Player claim after invite
│   ├── main_tab_screen.dart              # Bottom tabs (Teams/Spiele/Profil)
│   ├── team_detail_screen.dart           # Team management sheets
│   └── teams_screen.dart                 # Teams list + "Konto erforderlich" sheet
├── services/
│   ├── deep_link_service.dart            # lineup://join only
│   ├── invite_service.dart               # buildDeepLink, acceptInvite
│   ├── push_service.dart                 # FCM init, navigatorKey
│   └── notification_service.dart         # formatTitle/formatMessage
├── theme/cs_theme.dart                   # Design tokens, InputDecorationTheme
sql/
├── cs_business_notifications_v2_patch.sql  # Business push triggers (merged v1+v2)
├── cs_delete_account.sql                   # Account deletion RPC
supabase/
├── functions/send-push/index.ts            # FCM v1 sender
├── functions/match-reminders/index.ts      # Match reminder scheduler
└── config.toml                             # Edge function registration
ios/Runner/
├── Runner.entitlements                     # aps-environment = production
├── Info.plist                              # UIBackgroundModes, CFBundleURLSchemes
```
