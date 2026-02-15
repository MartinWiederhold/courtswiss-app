# Auth/Onboarding v2 – Implementation Report

## 1. Current State Summary (before this change)

| Aspect | Implementation |
|---|---|
| **Auth flow** | `signInAnonymously()` always called in `main()` when no session exists. Every user starts as anonymous. |
| **Login screen** | `LoginScreen` (magic-link via `signInWithOtp`) exists at `lib/screens/auth_screen.dart` but is **not** routed to from the UI. |
| **Invite links** | `courtswiss://join?token=XYZ` – handled by `DeepLinkService`, accepted via RPC `accept_team_invite`. |
| **Auth callbacks** | `io.courtswiss://login` registered in iOS Info.plist only. Ignored by `DeepLinkService` (filtered out). |
| **Team creation** | Any user (including anon) can create a team. |
| **Team list** | Single flat list, no segmentation. |
| **Identity linking** | Not implemented. |

---

## 2. Implemented Changes

### A. New Screens

| Screen | File | Purpose |
|---|---|---|
| **AuthScreen** | `lib/screens/auth_screen.dart` | Login/Register with tab toggle. E-Mail + Passwort. |
| **EmailVerificationPendingScreen** | `lib/screens/email_verification_pending_screen.dart` | Shown after registration. "Check your inbox" + resend button. |
| **ForgotPasswordScreen** | `lib/screens/forgot_password_screen.dart` | Enter email → send password reset link. |
| **ResetPasswordScreen** | `lib/screens/reset_password_screen.dart` | Set new password (opened via deep link after password recovery). |

### B. AuthGate Rework (`lib/screens/auth_gate.dart`)

- **No session → AuthScreen**: Instead of showing a spinner waiting for anon auth, the AuthGate now shows the `AuthScreen` (Login/Register).
- **Session exists → LoggedInScreen**: Unchanged behaviour — shows `MainTabScreen`.
- **Invite without session → on-demand anon**: When an invite deep link arrives and no session exists, an anonymous session is created automatically to allow `acceptInvite` to proceed.
- **Password recovery deep link → ResetPasswordScreen**: `DeepLinkService.onPasswordRecovery` stream fires → `AuthGate` pushes `ResetPasswordScreen`.

### C. `main.dart` – Removed Forced Anon Auth

```diff
- // Ensure a session exists – anonymous auth for instant access
- if (Supabase.instance.client.auth.currentSession == null) {
-   final res = await Supabase.instance.client.auth.signInAnonymously();
- }
+ // No longer auto-creating anonymous session on cold start.
+ // Anonymous sessions are created on-demand ONLY when an invite link
+ // is opened without an existing session (see AuthGate).
```

### D. DeepLinkService Update (`lib/services/deep_link_service.dart`)

Now handles **three** link types:

| Link Type | Pattern | Handling |
|---|---|---|
| **Invite** | `courtswiss://join?token=XYZ` | `_tokenController` broadcast (unchanged) |
| **Auth callback** | `io.courtswiss://login#access_token=...` | `getSessionFromUrl()` – PKCE session exchange |
| **Password reset** | `io.courtswiss://reset-password#access_token=...` | `getSessionFromUrl()` + `_passwordRecoveryController` broadcast |

### E. Team Creation Gate (`lib/screens/teams_screen.dart`)

- When an anonymous user taps the FAB (+), a bottom sheet appears:
  - Title: "Konto erforderlich"
  - Message: "Um eigene Teams zu erstellen, benötigst du ein Konto."
  - CTA: "Registrieren / Anmelden" → pushes `AuthScreen`.
  - Cancel button.

### F. Teams Segmentation (`lib/screens/teams_screen.dart` + `lib/services/team_service.dart`)

- `TeamService.listMyTeams()` now returns `my_role` and `is_owner` per team.
- **"Eigene Teams"** = role == `captain` OR `created_by` == current user ID.
- **"Geteilte Teams"** = member but not owner/captain.
- Each section has a header with icon + label.
- If "Eigene Teams" is empty but "Geteilte Teams" has entries, a hint text is shown.

### G. Identity Linking / Migration

**Strategy chosen: Server-side data migration RPC.**

Supabase supports upgrading anon users via `updateUser(email, password)` which preserves the same `user_id`. However, when a user logs into an **existing** account after being anon, the old anon `user_id` is abandoned. For this case:

1. **`IdentityLinkService`** (`lib/services/identity_link_service.dart`):
   - `saveAnonUid()` — persists current anon user_id to `SharedPreferences`.
   - `migrateIfNeeded()` — after login/signup, checks if there's a saved anon UID and calls the migration RPC.

2. **`migrate_anon_user_data` RPC** (`sql/cs_migrate_anon_user_data.sql`):
   - Updates all user references in 15 tables from `old_uid` → `new_uid`.
   - Handles unique constraint conflicts by deleting old duplicate rows.
   - `SECURITY DEFINER` to bypass RLS.
   - Validates that `auth.uid()` matches `p_new_uid`.

**Tables migrated:**
| Table | Column |
|---|---|
| `cs_app_profiles` | `user_id` |
| `cs_team_members` | `user_id` |
| `cs_team_players` | `claimed_by` |
| `cs_teams` | `created_by` |
| `cs_matches` | `created_by` |
| `cs_match_availability` | `user_id` |
| `cs_match_roster` | `user_id` |
| `cs_match_lineup_slots` | `user_id` |
| `cs_dinner_rsvps` | `user_id` |
| `cs_carpool_offers` | `driver_user_id` |
| `cs_expenses` | `paid_by` |
| `cs_event_reads` | `user_id` |
| `cs_notifications` | `recipient_user_id` |
| `cs_device_tokens` | `user_id` |
| `cs_notification_prefs` | `user_id` |

### H. Profil Screen Updates (`lib/screens/profil_screen.dart`)

- **Anon users**: See "Registrieren / Anmelden" CTA card.
- **Registered users**: See "Abmelden" (sign out) button.

### I. Android Manifest Updates (`android/app/src/main/AndroidManifest.xml`)

Added two new intent filters for:
- `io.courtswiss://login` — auth confirmation callbacks
- `io.courtswiss://reset-password` — password reset callbacks

---

## 3. Deep Link Formats & How to Test

### Registered Schemes

| Platform | Scheme | Host | Purpose |
|---|---|---|---|
| iOS + Android | `courtswiss://` | `join` | Invite links |
| iOS + Android | `io.courtswiss://` | `login` | Auth confirm / magic link |
| iOS + Android | `io.courtswiss://` | `reset-password` | Password reset |

### Testing Deep Links (Simulator/Device)

**Invite link:**
```bash
# iOS Simulator
xcrun simctl openurl booted "courtswiss://join?token=YOUR_TOKEN"

# Android Emulator
adb shell am start -a android.intent.action.VIEW -d "courtswiss://join?token=YOUR_TOKEN"
```

**Auth confirm (after registration):**
The link is sent by Supabase in the confirmation email. Format:
```
io.courtswiss://login#access_token=...&type=signup&...
```

**Password reset:**
```
io.courtswiss://reset-password#access_token=...&type=recovery&...
```

---

## 4. SendGrid / Supabase SMTP Configuration

Supabase Auth sends transactional emails (confirmation, password reset) via its built-in SMTP or a **Custom SMTP provider**. We use **SendGrid** with the verified domain `onewell.ch`.

### Production Values

| Setting | Value | Notes |
|---|---|---|
| **SMTP Host** | `smtp.sendgrid.net` | |
| **SMTP Port** | `587` | STARTTLS |
| **SMTP Username** | `apikey` | Literal string (not your email) |
| **SMTP Password** | `SG.xxxxx...` | SendGrid API Key with "Mail Send" permission |
| **Sender email** | `info@onewell.ch` | Single Sender verified ✅ |
| **Sender name** | `Courtswiss` | |
| **Domain Auth** | `em7814.onewell.ch` | Domain Authentication verified ✅ |

### Step-by-Step Setup

1. **SendGrid (already done)**
   - Domain Authentication: `em7814.onewell.ch` — verified ✅
   - Single Sender: `info@onewell.ch` — verified ✅
   - API Key with "Mail Send" permission created.

2. **Configure Supabase Custom SMTP**
   - Go to: **Supabase Dashboard → Project Settings → Authentication → SMTP Settings**
   - Enable "Custom SMTP"
   - Enter the production values from the table above.

3. **Configure URL Settings**
   - Go to: **Supabase Dashboard → Authentication → URL Configuration**
   - **Site URL**: `https://courtswiss.netlify.app`
     > ⚠️ The Site URL must be an `https://` web URL — **not** a custom scheme like `io.courtswiss://`.
     > It serves as the default redirect if no `redirect_to` parameter is provided and is used
     > by Supabase for building confirmation/reset links when no explicit redirect is set.
   - **Redirect URLs** (allow list — these are the deep link schemes the app registers):
     - `io.courtswiss://login`
     - `io.courtswiss://reset-password`
     - `courtswiss://join`

4. **Email Templates**
   - Go to: **Supabase Dashboard → Authentication → Email Templates**
   - **Confirmation template** (`{{ .ConfirmationURL }}`):
     - Supabase auto-generates the link. Because the client passes `emailRedirectTo: 'io.courtswiss://login'` during `signUp` / `updateUser`, the confirmation link will redirect to:
       ```
       io.courtswiss://login#access_token=...&type=signup&...
       ```
     - The app's `DeepLinkService` picks this up → `getSessionFromUrl()` → session established.
   - **Password Recovery template** (`{{ .ConfirmationURL }}`):
     - The client passes `redirectTo: 'io.courtswiss://reset-password'` during `resetPasswordForEmail`, so the link will redirect to:
       ```
       io.courtswiss://reset-password#access_token=...&type=recovery&...
       ```
     - The app's `DeepLinkService` picks this up → `_passwordRecoveryController` fires → `ResetPasswordScreen`.
   - You can customise the email subject/body text. The `{{ .ConfirmationURL }}` placeholder already contains the full redirect URL.

5. **Enable Email Confirmation**
   - Go to: **Supabase Dashboard → Authentication → Providers → Email**
   - Ensure **"Confirm email"** is **enabled**
   - Ensure **"Double confirm email changes"** is enabled (recommended)

### Where is the redirect URL set in code?

| File | Call | `redirectTo` value |
|---|---|---|
| `lib/screens/auth_screen.dart` | `signUp(...)` | `io.courtswiss://login` |
| `lib/screens/auth_screen.dart` | `updateUser(...)` (anon upgrade) | `io.courtswiss://login` |
| `lib/screens/email_verification_pending_screen.dart` | `resend(...)` | `io.courtswiss://login` |
| `lib/screens/forgot_password_screen.dart` | `resetPasswordForEmail(...)` | `io.courtswiss://reset-password` |

These values must match entries in the Supabase **Redirect URLs** allow list.

### Verification

After setup, register a test user. The confirmation email should:
- Come from `info@onewell.ch` (sender name: "Courtswiss")
- Contain a link that, when clicked, opens the app via `io.courtswiss://login#access_token=...`
- The app should establish a session and show the main tabs

---

## 5. Data Migration / Identity Linking Approach

### Approach: Server-side RPC Migration

**Why not Supabase "link identity"?**
Supabase `linkIdentity()` is designed for OAuth providers (Google, Apple, etc.), not for upgrading an anonymous user to email/password. The `updateUser()` method can upgrade an anon user in-place (keeping the same `user_id`), but if a user logs into a *different* existing account, we need data migration.

**Implementation:**

1. When an anon session is created (invite flow), `IdentityLinkService.saveAnonUid()` stores the anon `user_id` in `SharedPreferences`.

2. When `LoggedInScreen` initializes (after any auth state change), `IdentityLinkService.migrateIfNeeded()` checks:
   - Is there a saved anon UID?
   - Is the current user different from the anon UID?
   - If yes → call `migrate_anon_user_data(old_uid, new_uid)` RPC.

3. The RPC (PostgreSQL function, `SECURITY DEFINER`):
   - Validates caller is `new_uid` via `auth.uid()`.
   - Updates all `user_id` references across 15 tables.
   - Handles unique constraint conflicts by deleting old rows.
   - Returns a JSON summary of rows affected per table.

### Deploying the RPC

Run the SQL in `sql/cs_migrate_anon_user_data.sql` against your Supabase database:
```bash
# Via Supabase CLI
supabase db push

# Or via SQL Editor in Supabase Dashboard
# Copy contents of sql/cs_migrate_anon_user_data.sql and run
```

---

## 6. Manual QA Checklist

### Captain Flow (Fresh Registration)
- [ ] Open app → see AuthScreen (Login/Register)
- [ ] Switch to "Registrieren" tab
- [ ] Fill email + password + confirm → tap "Registrieren"
- [ ] See EmailVerificationPendingScreen
- [ ] Check email → click confirmation link
- [ ] App opens → user is logged in → see Teams tab
- [ ] Tap FAB (+) → CreateTeamScreen opens (no gate)
- [ ] Create team → team appears in "Eigene Teams" section

### Login Flow
- [ ] Open app → AuthScreen
- [ ] Enter email + password → "Anmelden"
- [ ] App shows main tabs
- [ ] Sign out from Profil → back to AuthScreen

### Password Reset Flow
- [ ] Open AuthScreen → "Passwort vergessen?"
- [ ] Enter email → "Link senden"
- [ ] See success state
- [ ] Check email → click reset link
- [ ] App opens → ResetPasswordScreen
- [ ] Set new password → success → back to main app

### Invite Flow (No Account)
- [ ] User without account opens invite link `courtswiss://join?token=XYZ`
- [ ] App creates anon session automatically
- [ ] User joins team → ClaimScreen or name dialog
- [ ] Team appears in "Geteilte Teams" section
- [ ] Tap FAB (+) → "Konto erforderlich" gate appears
- [ ] Tap "Registrieren / Anmelden" → AuthScreen

### Migration of Anon Membership
- [ ] User joined team via invite (anon)
- [ ] User registers via AuthScreen
- [ ] After registration: data migrated automatically
- [ ] User's team memberships, claims, etc. are preserved
- [ ] Team still appears in "Geteilte Teams"

### Anon Upgrade (Registration preserves user_id)
- [ ] Open invite link → anon session created → join team
- [ ] Switch to "Registrieren" tab → register with email+password
- [ ] **user_id stays the same** (verify in Supabase dashboard or debug log)
- [ ] **No migration RPC triggered** (check debug prints: "same user_id after upgrade, no migration")
- [ ] Team memberships, claims, etc. still intact without any migration

### Login into Existing Account (Migration triggered)
- [ ] Open invite link → anon session created → join team
- [ ] Switch to "Anmelden" tab → login with an **existing** registered account
- [ ] **user_id changes** (new account)
- [ ] **Migration RPC triggered** (check debug prints: "migrating data from … → …")
- [ ] Team memberships, claims, etc. are now under the logged-in account
- [ ] Old anon memberships no longer orphaned

### Existing Invite/Claim Flow
- [ ] Existing invite links still work
- [ ] ClaimScreen still works for new members
- [ ] Mandatory name dialog still works
- [ ] Captain/member permissions unchanged

### Profil Screen
- [ ] Anon user sees "Registrieren / Anmelden" button
- [ ] Registered user sees email + "Abmelden" button
- [ ] Sign out works → returns to AuthScreen

### Production Config Smoke Test (SendGrid / onewell.ch)

**Registration – Anon Upgrade:**
- [ ] Open invite link → join as anon → navigate to AuthScreen → "Registrieren"
- [ ] Register with email+password → `updateUser` path (check debug log: "upgrading anon user via updateUser")
- [ ] Confirmation email arrives from `info@onewell.ch` (sender name "Courtswiss")
- [ ] Click confirmation link → app opens via `io.courtswiss://login#...`
- [ ] User is now logged in, user_id unchanged, no migration triggered

**Registration – Fresh signUp (no anon session):**
- [ ] Open app (no prior session) → AuthScreen → "Registrieren"
- [ ] Register with email+password → `signUp` path
- [ ] EmailVerificationPendingScreen shown
- [ ] Confirmation email arrives from `info@onewell.ch`
- [ ] Click link → app opens → user logged in → Teams tab

**Password Reset:**
- [ ] AuthScreen → "Passwort vergessen?" → enter email → "Link senden"
- [ ] Reset email arrives from `info@onewell.ch`
- [ ] Click link → app opens via `io.courtswiss://reset-password#...`
- [ ] ResetPasswordScreen is displayed
- [ ] Set new password → success → back to main app
- [ ] Login with new password works

**Invite Flow (no registration required):**
- [ ] User without account opens `courtswiss://join?token=XYZ`
- [ ] Anon session created, team joined
- [ ] No email sent, no confirmation required
- [ ] Team visible in "Geteilte Teams"

---

## 7. Files Changed Summary

### New Files
| File | Purpose |
|---|---|
| `lib/screens/auth_screen.dart` | Login/Register screen (replaced magic-link screen) |
| `lib/screens/email_verification_pending_screen.dart` | Post-registration confirmation pending screen |
| `lib/screens/forgot_password_screen.dart` | Password reset email request |
| `lib/screens/reset_password_screen.dart` | Set new password (deep link target) |
| `lib/services/identity_link_service.dart` | Anon→registered data migration client |
| `sql/cs_migrate_anon_user_data.sql` | PostgreSQL RPC for data migration |

### Modified Files
| File | Changes |
|---|---|
| `lib/main.dart` | Removed forced `signInAnonymously()` on cold start |
| `lib/screens/auth_gate.dart` | AuthScreen when no session; on-demand anon for invites; password recovery handling; migration call |
| `lib/screens/teams_screen.dart` | Anon gate for team creation; "Eigene Teams" / "Geteilte Teams" segmentation |
| `lib/screens/profil_screen.dart` | Register/Login CTA for anon; Sign out for registered |
| `lib/services/deep_link_service.dart` | Auth callback + password reset deep link handling |
| `lib/services/team_service.dart` | `listMyTeams()` returns `my_role` and `is_owner` |
| `android/app/src/main/AndroidManifest.xml` | Added intent filters for `io.courtswiss://login` and `io.courtswiss://reset-password` |

### No Logic Changes
- Existing invite/claim RPC calls unchanged
- Captain/member permission model unchanged
- Match, lineup, roster, expense, carpool logic untouched
- No design color changes
- `flutter analyze` remains at 5 pre-existing info-level issues (no new ones)

---

## 8. Safety Fixes (Robustness)

### A. Prefer "Anon Upgrade" on Registration

**Problem:** When an anonymous session already exists and the user taps "Registrieren", `signUp()` would create a *new* user_id, orphaning all data accumulated under the anon id and requiring a full DB migration.

**Fix (`lib/screens/auth_screen.dart` → `_register()`):**
- Before calling `signUp`, check if the current session is anonymous (`currentUser != null && email == null`).
- If **anon**: use `updateUser(UserAttributes(email: email, password: pw))` instead of `signUp`.
  → The user_id stays the same, no migration needed.
- If **no anon session** (or already registered): fall back to normal `signUp`.
- The `EmailVerificationPendingScreen` is shown in both paths when email confirmation is required.

### B. Tighter Client-side Migration Guard

**Problem:** `IdentityLinkService.migrateIfNeeded()` could theoretically attempt to migrate non-anonymous saved UIDs, e.g. if `SharedPreferences` was corrupted or stale.

**Fix (`lib/services/identity_link_service.dart`):**
- `saveAnonUid()` now additionally stores a boolean flag `cs_anon_uid_was_anon` (= `user.email == null`) at save time.
- `migrateIfNeeded()` now checks **three conditions** before calling the RPC:
  1. `savedAnonUid != null`
  2. `current user_id != savedAnonUid` (i.e. user logged into a *different* account, not upgraded in-place)
  3. `savedAnonUid` was genuinely anon (`wasAnon == true`)
- If any condition fails, migration is skipped and saved prefs are cleaned up.

### C. Server-side Safety in `migrate_anon_user_data` RPC

**Problem:** The RPC only validated `auth.uid() == p_new_uid`, but did not verify that `p_old_uid` was actually an anonymous user. A malicious or buggy client could theoretically migrate data from a real account.

**Fix (`sql/cs_migrate_anon_user_data.sql`):**
- Added a check after the existing validations:
  ```sql
  -- p_old_uid must be anon (auth.users.is_anonymous = true OR email IS NULL)
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_old_uid
      AND (is_anonymous = true OR email IS NULL)
  ) THEN
    -- Fallback: check cs_app_profiles
    IF EXISTS (
      SELECT 1 FROM cs_app_profiles
      WHERE user_id = p_old_uid AND email IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'p_old_uid is not an anonymous user – migration aborted';
    END IF;
  END IF;
  ```
- If `p_old_uid` is a registered user (has email), the function raises an exception and aborts.

---

## 9. Deploying Safety Fixes

1. **SQL migration:** Re-run `sql/cs_migrate_anon_user_data.sql` against the Supabase database (the `CREATE OR REPLACE FUNCTION` will update the existing function in-place).
2. **Flutter code:** Just rebuild the app — no additional configuration needed.
