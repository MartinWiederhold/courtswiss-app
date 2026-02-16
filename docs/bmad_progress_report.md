# BMAD Progress Report — CourtSwiss

> Updated: 2026-02-16
> Scope: Navigation, Auth/Onboarding v2, Teams UX, Motion Phase, Push Notifications, Account Deletion, Production Config

---

## 1. Executive Summary

CourtSwiss now has a fully functional **email/password auth system** (registration, email confirmation via SendGrid, password reset via deep links), a **3-tab bottom navigation** (Teams / Spiele / Profil), and **team segmentation** (Eigene Teams / Geteilte Teams). Anonymous users can still join teams via invite links without registering; when they later register, the system either **upgrades the anon session in-place** (same `user_id`) or **migrates all data** to an existing account via a server-side RPC.

The **Spiele (matches) tab** aggregates all matches across all teams and auto-refreshes when a team is deleted or left. The **Profil tab** surfaces notification preferences, account info, account deletion, and sign-out/register CTAs.

All BottomSheets, dialogs, and popup menus use **unified motion** (`easeOutCubic` 280ms for sheets, 200ms for dialogs).

The **email verification pending screen** provides anti-enumeration messaging, a resend-confirmation button with rate-limit handling, and a login-fallback CTA. All strings are fully localised (DE/EN).

**Push Notifications (FCM + APNs)** are wired end-to-end: permission request, FCM token registration to `cs_device_tokens`, token refresh + auth-change re-registration, foreground/background/terminated message handling, and notification-tap deep navigation. iOS-specific fixes for APNs entitlements, foreground presentation, and background handler initialisation have been applied.

**Account deletion** is implemented with a type-to-confirm dialog, server-side `cs_delete_account` RPC (SECURITY DEFINER, factory-reset across all `cs_*` tables + `auth.users`), and smoke tests.

---

## 2. Implemented Features

### Navigation
- **3-tab BottomNavigationBar** via `MainTabScreen` (`lib/screens/main_tab_screen.dart`)
  - Teams (default) → `TeamsScreen`
  - Spiele → `SpieleOverviewScreen`
  - Profil → `ProfilScreen`
- `IndexedStack` keeps all tabs alive when switching — no reload on tab change.

### Auth / Onboarding v2
- **AuthScreen** (`lib/screens/auth_screen.dart`): Login/Register toggle with email + password fields.
- **Anon upgrade on registration**: If an anonymous session exists, "Registrieren" calls `updateUser(UserAttributes(email, password))` instead of `signUp()` → same `user_id`, no migration needed.
- **Email Verification**: `EmailVerificationPendingScreen` shown after registration; includes resend button, anti-enumeration messaging, and login-fallback CTA.
- **Forgot Password**: `ForgotPasswordScreen` → sends reset email → `ResetPasswordScreen` (opened via deep link `io.courtswiss://reset-password#...`).
- **AuthGate** (`lib/screens/auth_gate.dart`):
  - No session → shows `AuthScreen`
  - Session exists → shows `MainTabScreen`
  - Invite without session → creates on-demand anonymous session
  - Password recovery deep link → pushes `ResetPasswordScreen`
- **No forced anon on cold start**: Anonymous sessions are only created on-demand for invite flows.

### Email Verification UX (Anti-Enumeration)
- **`EmailVerificationPendingScreen`** (`lib/screens/email_verification_pending_screen.dart`):
  - Anti-enumeration body text: never confirms whether an account with the given email exists.
  - **Resend confirmation email** button → `supabase.auth.resend(type: OtpType.signup, email: email)` with success/rate-limit toasts.
  - **"Already have an account? Log in"** CTA → pops back to `AuthScreen` with email pre-filled on the login tab.
  - Auto-detects successful email confirmation via `onAuthStateChange` listener.
  - Signup flow always navigates here if `session == null` after `signUp()` or `updateUser()`.
- **Localisation**: 6 new keys added to `app_en.arb` / `app_de.arb`:
  - `verificationPendingTitle`, `verificationPendingBody`, `resendConfirmationEmail`, `resendEmailSuccess`, `resendEmailRateLimit`, `alreadyHaveAccountLogin`

### Identity Linking / Migration
- **`IdentityLinkService`** (`lib/services/identity_link_service.dart`):
  - `saveAnonUid()` — persists anon `user_id` + `wasAnon` flag to `SharedPreferences`.
  - `migrateIfNeeded()` — runs only when: (a) saved UID exists, (b) current user differs, (c) saved user was genuinely anon.
- **`migrate_anon_user_data` RPC** (`sql/cs_migrate_anon_user_data.sql`):
  - Migrates all user references across 15 tables.
  - Server-side safety: validates `auth.uid() == p_new_uid` AND `p_old_uid` must be anonymous (`auth.users.is_anonymous = true OR email IS NULL`).

### Teams UX
- **Segmentation**: "Eigene Teams" (captain / creator) vs "Geteilte Teams" (member).
- **Team creation gate**: Anonymous users see a bottom sheet ("Konto erforderlich") when tapping the FAB.
- **Swipe-to-delete** (Eigene Teams): Red "Löschen" action → calls `TeamService.deleteTeam()`.
- **Swipe-to-leave** (Geteilte Teams): Blue "Entfernen" action → calls `TeamService.leaveTeam()` (deletes membership row only).
- **Confirm dialogs**: Destructive (red) for delete, informational (blue) for leave, both with German copy.
- **Empty state**: "Willkommen bei CourtSwiss" card with "So funktioniert's" guide (light-style: white card, black text, green circles with black numbers).
- **No hint text**: Removed "Du hast noch keine eigenen Teams…" placeholder.
- **No neon accent line**: Team cards no longer show a colored top accent bar.

### Spiele Tab
- **`SpieleOverviewScreen`** (`lib/screens/spiele_overview_screen.dart`): Shows all matches across all teams via `MatchService.listAllMyMatches()`.
- **Live refresh on team changes**: Listens to `TeamService.teamChangeNotifier` — auto-reloads when a team is deleted or left.
- **Manual refresh**: Pull-to-refresh + refresh icon in AppBar.

### Profil Tab
- **`ProfilScreen`** (`lib/screens/profil_screen.dart`):
  - Anon users → "Registrieren / Anmelden" CTA card.
  - Registered users → Email display + "Abmelden" button.
  - Notification preference toggles.
  - **Account deletion** with type-to-confirm dialog.

### Account Deletion
- **`AccountService`** (`lib/services/account_service.dart`): Calls `cs_delete_account` RPC → signs out → clears `SharedPreferences`.
- **`DeleteAccountDialog`** (`lib/widgets/delete_account_dialog.dart`): Type-to-confirm UI (user must type "LÖSCHEN" / "DELETE").
- **`cs_delete_account` RPC** (`sql/cs_delete_account.sql`): SECURITY DEFINER function that deletes all user data across every `cs_*` table + the `auth.users` row. Uses `_cs_da_delete` helper for safe per-table deletion.
- **Smoke test**: `sql/cs_delete_account_smoke_test.sql` (182 lines).
- **Localisation**: Keys for `deleteAccount`, `deleteAccountTitle`, `deleteAccountBody`, `typeToConfirm`, `confirmWordDelete`, `deleting`, `accountDeleted`, `accountDeleteError`.

### Push Notifications (FCM + APNs)
- **`PushService`** (`lib/services/push_service.dart`):
  - `initPush()` called after auth session exists (in `LoggedInScreen._init()`).
  - Requests permission (`alert`, `badge`, `sound`).
  - iOS: `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)`.
  - iOS: APNs token diagnostic logging (`getAPNSToken()`).
  - Gets FCM token → registers in `cs_device_tokens` via `DeviceTokenService`.
  - Listens for token refresh → re-registers.
  - Listens for auth state changes → re-registers under new `user_id`.
  - Foreground messages → shows local notification via `LocalNotificationService`.
  - Background messages → top-level `firebaseMessagingBackgroundHandler` with `Firebase.initializeApp()`.
  - Notification tap → navigates to `MatchDetailScreen`.
  - Cold start (terminated) → `getInitialMessage()` → navigates.
  - `dispose()` cleans up all subscriptions (called on logout).
- **`DeviceTokenService`** (`lib/services/device_token_service.dart`): Stable `device_id` via UUID v4 + SharedPreferences; `registerToken()` calls `cs_upsert_device_token` RPC; `disableCurrentDevice()` for logout.
- **`LocalNotificationService`** (`lib/services/local_notification_service.dart`): `flutter_local_notifications` wrapper for in-app foreground notifications.
- **`PushPrefsService`** (`lib/services/push_prefs_service.dart`): Read/write notification preferences (global + per-team) via `cs_get_notification_prefs` / `cs_set_notification_prefs` RPCs.
- **iOS Entitlements** (`ios/Runner/Runner.entitlements`): `aps-environment = production` — **newly created**, wired into all 3 build configs (Debug/Release/Profile) in `project.pbxproj`.
- **Info.plist**: `UIBackgroundModes` includes `remote-notification` ✅.
- **Push pipeline DB** (`sql/cs_push_pipeline_patch.sql`): `cs_device_tokens`, `cs_notification_prefs`, `cs_event_deliveries`, fanout trigger on `cs_events` INSERT.

### Motion Phase (Design 2.0)
- **Unified BottomSheet animation**: `easeOutCubic` 280ms in / `easeInCubic` 220ms out. Applied via `CsMotion.sheet` to `BottomSheetThemeData` + all 16 direct `showModalBottomSheet` calls.
- **Dialog/Menu animation**: `easeOutCubic` 200ms in / 160ms out. Applied via `CsMotion.dialog` to `DialogThemeData`, `PopupMenuThemeData`, and all `PopupMenuButton` instances.
- **Centralised tokens**: `CsDurations` and `CsMotion` classes in `lib/theme/cs_theme.dart`.

### Localisation
- Full DE/EN support via `app_en.arb` / `app_de.arb` with `flutter gen-l10n`.
- `LocaleController` for reactive locale switching persisted in `SharedPreferences`.
- All UI strings localised — no hardcoded strings in widgets.

---

## 3. Files Changed

### New Files

| File | Purpose |
|---|---|
| `lib/screens/main_tab_screen.dart` | 3-tab bottom navigation (Teams / Spiele / Profil) |
| `lib/screens/spiele_overview_screen.dart` | Global matches tab across all teams |
| `lib/screens/profil_screen.dart` | User profile, notification prefs, account deletion, sign-out |
| `lib/screens/auth_screen.dart` | Login/Register screen (email + password) |
| `lib/screens/email_verification_pending_screen.dart` | Post-registration screen with anti-enumeration UX |
| `lib/screens/forgot_password_screen.dart` | Password reset email request |
| `lib/screens/reset_password_screen.dart` | Set new password (deep link target) |
| `lib/screens/notification_settings_screen.dart` | Push notification settings per team |
| `lib/screens/notifications_screen.dart` | In-app notifications list |
| `lib/screens/event_inbox_screen.dart` | Event inbox screen |
| `lib/screens/claim_screen.dart` | Player claim screen (after invite) |
| `lib/screens/sport_selection_screen.dart` | Sport selection for team creation |
| `lib/services/identity_link_service.dart` | Anon→registered data migration client |
| `lib/services/push_service.dart` | FCM push notification setup + handling |
| `lib/services/device_token_service.dart` | FCM token registration to Supabase |
| `lib/services/local_notification_service.dart` | flutter_local_notifications wrapper |
| `lib/services/push_prefs_service.dart` | Notification preferences read/write |
| `lib/services/notification_service.dart` | In-app notification service (Realtime) |
| `lib/services/account_service.dart` | Account deletion service |
| `lib/services/locale_controller.dart` | Reactive locale switching |
| `lib/widgets/delete_account_dialog.dart` | Type-to-confirm account deletion dialog |
| `ios/Runner/Runner.entitlements` | APNs entitlement (`aps-environment = production`) |
| `sql/cs_migrate_anon_user_data.sql` | PostgreSQL RPC for migrating data across 15 tables |
| `sql/cs_push_pipeline_patch.sql` | cs_device_tokens, cs_notification_prefs, cs_event_deliveries, fanout trigger |
| `sql/cs_delete_account.sql` | cs_delete_account RPC (factory-reset) |
| `sql/cs_delete_account_smoke_test.sql` | Smoke test for account deletion |

### Modified Files

| File | Changes |
|---|---|
| `lib/main.dart` | Removed forced `signInAnonymously()`, added Firebase init, LocalNotificationService init, locale controller |
| `lib/screens/auth_gate.dart` | AuthScreen when no session; on-demand anon for invites; password recovery; migration call; PushService init |
| `lib/screens/teams_screen.dart` | Segmentation, swipe delete/leave, creation gate, guide card light-style, removed hint text, removed accent bar |
| `lib/screens/team_detail_screen.dart` | `sheetAnimationStyle` on all BottomSheets, `popUpAnimationStyle` on PopupMenuButton |
| `lib/screens/match_detail_screen.dart` | `sheetAnimationStyle` on all 7 BottomSheets, `popUpAnimationStyle` on PopupMenuButton |
| `lib/screens/claim_screen.dart` | `sheetAnimationStyle` on BottomSheet |
| `lib/services/team_service.dart` | `leaveTeam()`, `teamChangeNotifier` (ValueNotifier for cross-tab refresh) |
| `lib/services/match_service.dart` | `listAllMyMatches()` for global Spiele tab |
| `lib/services/deep_link_service.dart` | Auth callback + password reset deep link handling |
| `lib/theme/cs_theme.dart` | `CsDurations`, `CsMotion`, `sheetAnimationStyle`, `dialogAnimationStyle`, `popUpAnimationStyle` in theme data |
| `lib/widgets/ui/cs_bottom_sheet_form.dart` | `sheetAnimationStyle: CsMotion.sheet` |
| `android/app/src/main/AndroidManifest.xml` | Intent filters for `io.courtswiss://login` and `io.courtswiss://reset-password` |
| `ios/Runner.xcodeproj/project.pbxproj` | Added `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` to all 3 build configs |
| `lib/l10n/app_en.arb` | All localisation keys (90+ keys) |
| `lib/l10n/app_de.arb` | All localisation keys (90+ keys) |

---

## 4. Supabase Configuration

### URL Configuration
| Setting | Value | Notes |
|---|---|---|
| **Site URL** | `https://courtswiss.netlify.app` | Must be an `https://` web URL, **not** a custom scheme |
| **Redirect URLs** (allow list) | `io.courtswiss://login` | Auth confirmation / email verify callback |
| | `io.courtswiss://reset-password` | Password reset callback |
| | `courtswiss://join` | Team invite links |

### Custom SMTP (SendGrid)
| Setting | Value |
|---|---|
| **Host** | `smtp.sendgrid.net` |
| **Port** | `587` (STARTTLS) |
| **Username** | `apikey` (literal string) |
| **Password** | SendGrid API Key (`SG.xxxxx...`) |
| **Sender email** | `info@onewell.ch` |
| **Sender name** | `Courtswiss` |
| **Domain Auth** | `em7814.onewell.ch` — verified ✅ |
| **Single Sender** | `info@onewell.ch` — verified ✅ |

### Email Templates
- **Confirmation**: Supabase auto-generates links using `{{ .ConfirmationURL }}`. Client passes `emailRedirectTo: 'io.courtswiss://login'` → link redirects to `io.courtswiss://login#access_token=...&type=signup`.
- **Recovery**: Client passes `redirectTo: 'io.courtswiss://reset-password'` → link redirects to `io.courtswiss://reset-password#access_token=...&type=recovery`.
- Configure at: **Supabase Dashboard → Authentication → Email Templates**.

### Email Provider Settings
- **Confirm email**: Enabled ✅
- **Double confirm email changes**: Recommended ✅

---

## 5. Push Notification Configuration

### Firebase (iOS)
| Setting | Value | Status |
|---|---|---|
| **Bundle ID in Firebase** | `com.example.swisscourt` | ✅ Matches `project.pbxproj` + `GoogleService-Info.plist` |
| **APNs Auth Key (.p8)** | Uploaded in Firebase Console | ✅ Production |
| **GoogleService-Info.plist** | `ios/Runner/GoogleService-Info.plist` | ✅ Present |
| **GCM_SENDER_ID** | `73144175672` | ✅ |
| **IS_GCM_ENABLED** | `true` | ✅ |

### iOS Project Configuration
| Setting | Status | Details |
|---|---|---|
| **Runner.entitlements** | ✅ Created | `aps-environment = production` |
| **CODE_SIGN_ENTITLEMENTS** | ✅ Set | All 3 build configs (Debug/Release/Profile) |
| **UIBackgroundModes** | ✅ | `remote-notification` in `Info.plist` |
| **FirebaseAppDelegateProxyEnabled** | ✅ Default (YES) | Not explicitly set → Firebase swizzling enabled |
| **AppDelegate.swift** | ✅ Clean | No custom `UNUserNotificationCenter` overrides |

### Push Flow (Client-Side)
```
App start → Firebase.initializeApp()
Login → LoggedInScreen → PushService.initPush()
  1. requestPermission(alert, badge, sound)
  2. setForegroundNotificationPresentationOptions (iOS)
  3. getAPNSToken() (iOS diagnostic)
  4. getToken() → FCM token
  5. registerToken → cs_upsert_device_token RPC → cs_device_tokens
  6. onTokenRefresh → re-register
  7. onAuthStateChange → re-register under new user_id
  8. onMessage → LocalNotificationService.show()
  9. onMessageOpenedApp → navigate to MatchDetailScreen
  10. getInitialMessage() → navigate (cold start)
```

### Push Flow (Server-Side — Partially Implemented)
```
cs_events INSERT → fn_cs_event_fanout() trigger
  → cs_event_deliveries (status = 'pending' or 'skipped')
  → Edge Worker (NOT YET IMPLEMENTED) → FCM v1 API → device
```

⚠️ **The Edge Worker for processing `cs_event_deliveries` and sending via FCM v1 API is planned but not yet implemented.** Push notifications can currently only be tested via Firebase Console.

---

## 6. QA Checklist

### ✅ Verified

- [x] Open app without session → AuthScreen displayed
- [x] Register with email + password → EmailVerificationPendingScreen shown
- [x] EmailVerificationPendingScreen shows anti-enumeration text (no account existence leak)
- [x] Resend confirmation email button works with rate-limit toast
- [x] "Already have an account? Log in" prefills email on login tab
- [x] Login with existing account → main tabs displayed
- [x] Sign out from Profil → returns to AuthScreen
- [x] Invite link without session → anon session created → team joined
- [x] Anon user taps FAB (+) → "Konto erforderlich" gate shown
- [x] Teams segmentation: "Eigene Teams" and "Geteilte Teams" sections displayed correctly
- [x] Swipe own team → red "Löschen" → confirm → team deleted
- [x] Swipe shared team → blue "Entfernen" → confirm → membership removed
- [x] After deleting/leaving team → Spiele tab auto-refreshes (no stale matches)
- [x] BottomSheet animations: smooth easeOutCubic slide-in
- [x] PopupMenu / Dialog animations: gentle fade with easeOutCubic
- [x] "So funktioniert's" card: white background, dark text, green step circles
- [x] Team cards: no neon accent line
- [x] No "Du hast noch keine eigenen Teams…" hint text
- [x] Account deletion with type-to-confirm dialog
- [x] All UI strings localised (DE/EN), no hardcoded strings
- [x] iOS Runner.entitlements with `aps-environment = production` created
- [x] iOS foreground notification presentation options set
- [x] Background handler calls `Firebase.initializeApp()`
- [x] APNs token diagnostic logging present
- [x] `flutter analyze` clean (only 9 pre-existing info-level issues, 0 errors, 0 warnings)

### 🔲 Needs Manual Testing (Production)

- [ ] SendGrid confirmation email arrives from `info@onewell.ch`
- [ ] Clicking email confirm link opens app via `io.courtswiss://login#...`
- [ ] Password reset email arrives, link opens `ResetPasswordScreen`
- [ ] Anon upgrade: invite → register → `user_id` stays same (no migration triggered)
- [ ] Login existing account: invite → login → migration triggered, data preserved
- [ ] Resend confirmation email works from `EmailVerificationPendingScreen`
- [ ] iOS + Android deep link routing for all 3 scheme types
- [ ] iOS Push: `APNS_TOKEN` is non-null in console log on real device
- [ ] iOS Push: `FCM_TOKEN` is non-null in console log
- [ ] iOS Push: Token appears in `cs_device_tokens` with `platform = 'ios'`
- [ ] iOS Push: Firebase Console test message arrives (foreground)
- [ ] iOS Push: Firebase Console test message arrives (background)
- [ ] iOS Push: Firebase Console test message arrives (terminated)
- [ ] Account deletion: RPC deletes all data + auth.users row

---

## 7. Known Issues / Open Tasks

### Implemented (Recent Sessions)
These items were requested and have been completed:

| Item | Status | Details |
|---|---|---|
| Remove neon top accent line from Team cards | ✅ Done | Removed `accentBarColor` from `_buildTeamCard()` in `teams_screen.dart` |
| "So funktioniert's" card → light style | ✅ Done | White bg, dark text, lime circles with black numbers |
| Remove "Du hast noch keine eigenen Teams…" hint | ✅ Done | Removed from `_buildSegmentedList()` |
| Shared Teams swipe "Entfernen" (blue) | ✅ Done | `_confirmLeaveTeam()` + `TeamService.leaveTeam()` |
| Spiele tab live-update on team delete/leave | ✅ Done | `TeamService.teamChangeNotifier` + listener in `SpieleOverviewScreen` |
| Email verification UX (anti-enumeration) | ✅ Done | Rewritten `EmailVerificationPendingScreen` with resend + login CTA |
| iOS Push Notifications audit + fixes | ✅ Done | Entitlements, foreground options, APNs diagnostics, background handler |
| Account deletion | ✅ Done | `cs_delete_account` RPC + `AccountService` + `DeleteAccountDialog` |

### Open / Future Work

| Item | Priority | Notes |
|---|---|---|
| **Edge Worker for push delivery** | High | `cs_event_deliveries` rows are created (status=pending) by the fanout trigger, but no Edge Function yet processes them and sends via FCM v1 API. Push is currently only testable via Firebase Console. |
| **Bundle ID: `com.example.swisscourt`** | High | The current bundle ID is the Flutter template default. For App Store release, this should be changed to a proper reverse-domain identifier (e.g. `ch.onewell.courtswiss`). Must be updated in: `project.pbxproj`, `GoogleService-Info.plist`, Firebase Console, Apple Developer Portal. |
| **Supabase email templates: German copy + branding** | High | Default Supabase templates are English. Need to customise confirmation + recovery templates with German text, CourtSwiss logo, and sender name "Courtswiss" in Supabase Dashboard. |
| **Spiele tab: live-update on new game creation** | Medium | Currently only refreshes on team delete/leave. When a new match is created inside `TeamDetailScreen` → `CreateMatchScreen`, the Spiele tab does not auto-update until user manually refreshes or switches tabs. |
| **Spiele tab: live-update on game deletion** | Medium | Same issue: deleting a match from `MatchDetailScreen` does not signal `SpieleOverviewScreen`. |
| **RLS for `leaveTeam()`** | Medium | Verify that Supabase RLS on `cs_team_members` allows a user to delete their own membership row (`user_id = auth.uid()`). |
| **Captains should not leave their own team** | Low | Currently `leaveTeam` is only shown for "Geteilte Teams" (non-owner), but no server-side guard prevents a captain from deleting their own membership via API. |
| **Edge case: last member leaves** | Low | If the only member of a shared team leaves, the team still exists but has no members. This is correct (captain manages it), but worth a QA check. |

---

## 8. Architecture Notes

### Cross-Tab Communication
- `MainTabScreen` uses `IndexedStack` — all 3 tabs stay alive.
- `TeamService.teamChangeNotifier` (`ValueNotifier<int>`) is the signal bus.
- `SpieleOverviewScreen` listens via `addListener` / `removeListener`.
- Pattern can be extended for match-level changes if needed.

### Deep Link Routing
```
courtswiss://join?token=XYZ           → DeepLinkService → onInviteToken stream
io.courtswiss://login#access_token=…  → DeepLinkService → getSessionFromUrl()
io.courtswiss://reset-password#…      → DeepLinkService → onPasswordRecovery stream
```

### Auth Flow Summary
```
Cold start (no session)  →  AuthScreen (Login / Register)
Invite link (no session) →  auto signInAnonymously → join team → AuthScreen later
Register (anon session)  →  updateUser() (upgrade in-place, same user_id)
Register (no session)    →  signUp() (new user_id)
Login (with saved anon)  →  migrateIfNeeded() → RPC migrate_anon_user_data
```

### Push Notification Flow
```
initPush() → requestPermission → setForegroundPresentationOptions (iOS)
           → getAPNSToken (iOS diagnostic)
           → getToken → registerToken → cs_upsert_device_token RPC
           → onTokenRefresh listener → re-register
           → onAuthStateChange listener → re-register for new user
           → onMessage → LocalNotificationService.show()
           → onMessageOpenedApp → _handleNotificationTap → MatchDetailScreen
           → getInitialMessage → _handleNotificationTap (cold start)
Background: firebaseMessagingBackgroundHandler (top-level, @pragma, Firebase.initializeApp)
```

### Account Deletion Flow
```
ProfilScreen → DeleteAccountDialog (type "LÖSCHEN" / "DELETE")
             → AccountService.deleteAccount()
               → cs_delete_account RPC (SECURITY DEFINER)
                 → _cs_da_delete helper per cs_* table
                 → DELETE FROM auth.users
               → supabase.auth.signOut()
               → SharedPreferences.clear()
             → AuthGate rebuilds → AuthScreen
```
