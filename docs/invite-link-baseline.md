# Invite Link System – Technical Baseline Report

> **Date:** 2026-02-20
> **Status:** Documentation only – no code changes

---

## 1. Invitation Link Creation

### Where is the link generated?

The invitation link is created in **`lib/services/invite_service.dart`** via two steps:

1. **Token generation:** `InviteService.createInvite(teamId)` calls the Supabase RPC function `create_team_invite` with the parameter `p_team_id`. The RPC returns a UUID token string.
2. **Link construction:** `InviteService.buildShareLink(token)` constructs the HTTPS link.

### Exact link format currently used

The **share link** (sent to recipients) is:

```
https://courtswiss.netlify.app/join?token=<UUID>
```

There is also a **deep link** format used internally by the app:

```
lineup://join?token=<UUID>
```

### Parameters included

- `token` — a UUID string identifying the invitation (the only parameter)
- No `teamId` is included in the link; the backend resolves team membership from the token

### HTTPS vs. Custom Scheme

Both formats exist in the codebase:

| Method | Format | Used for |
|---|---|---|
| `buildShareLink(token)` | `https://courtswiss.netlify.app/join?token=<UUID>` | Share text sent to WhatsApp / Share Sheet |
| `buildDeepLink(token)` | `lineup://join?token=<UUID>` | Internal reference; printed to debug console |

The `buildShareText()` method currently calls `buildShareLink()`, meaning the **HTTPS format** is what users receive.

---

## 2. Invitation Sharing Flow

### How is the link shared?

The share flow is triggered in **`lib/screens/team_detail_screen.dart`**:

1. User taps the **share icon** (top app bar) or the **"Link versenden"** button on the Einladungslink card (Overview tab).
2. Both call `_shareInviteLink()`.
3. This method:
   - Calls `InviteService.createInvite(widget.teamId)` → gets token
   - Calls `InviteService.buildShareText(token, teamName)` → builds message
   - Shows a success toast (`inviteLinkCreated`)
   - Opens the native **Share Sheet** via `Share.share(shareText, subject: ...)` (from `share_plus` package)

### Who can share?

The **Einladungslink card** on the Overview tab is only visible to admins (`_isAdmin` — captain or team creator). However, the **share icon** in the app bar is always visible.

### Share text format

```
Tritt meinem Interclub-Team "<TeamName>" bei Lineup bei:
https://courtswiss.netlify.app/join?token=<UUID>
```

### Known issues

- **WhatsApp in-app browser:** When a user clicks the HTTPS link in WhatsApp, it opens in WhatsApp's built-in browser (SFSafariViewController on iOS, Chrome Custom Tab on Android). The Netlify page then attempts to redirect to `lineup://join?token=...` via JavaScript (`window.location.href`). This redirect is **blocked** by WhatsApp's in-app browser on iOS because it does not allow JavaScript-initiated navigation to custom URL schemes.
- **Fallback not yet functional:** Without Apple Universal Links / Android App Links properly configured on the hosting domain, the HTTPS link always opens in the browser first, never directly in the app.

---

## 3. Flutter App Link Handling

### Which Dart files handle incoming links?

| File | Responsibility |
|---|---|
| `lib/services/deep_link_service.dart` | Listens for incoming URIs, parses invite tokens |
| `lib/screens/auth_gate.dart` | Processes invite tokens (with or without active session) |
| `lib/main.dart` | Initializes `DeepLinkService.instance.init()` before `runApp()` |

### How are incoming links parsed?

`DeepLinkService` uses the `app_links` package (`AppLinks`):

1. **Cold start:** `_appLinks.getInitialLink()` checks if the app was launched via a deep link.
2. **Foreground:** `_appLinks.uriLinkStream` listens for links arriving while the app is running.
3. **Parsing:** `_handleUri(Uri uri)` extracts `uri.queryParameters['token']`. If a non-empty token is found, it is stored as `_pendingToken` and emitted via `_tokenController` (broadcast stream).
4. The handler is **scheme-agnostic** — it works for both `lineup://join?token=XYZ` and `https://courtswiss.netlify.app/join?token=XYZ` because it only checks for the `token` query parameter.

### How is the token processed?

In `auth_gate.dart`:

- **`AuthGate._listenForInviteWithoutSession()`**: If no session exists when a token arrives, an anonymous session is created on-demand. The token is stored as `pendingToken` for later processing.
- **`LoggedInScreen._init()`**: On initialization, checks for `pendingToken` and calls `_acceptInviteToken(token)`.
- **`LoggedInScreen._listenForInviteTokens()`**: Subscribes to `onInviteToken` stream for tokens arriving while logged in.
- **`_acceptInviteToken(token)`**: Calls `InviteService.acceptInvite(token)` (RPC `accept_team_invite`). On success, navigates to the team detail screen and optionally presents the ClaimScreen.

### Cold start vs. foreground

Both are supported:

- **Cold start:** `getInitialLink()` in `DeepLinkService.init()` (called from `main()`)
- **Foreground:** `uriLinkStream` subscription in `DeepLinkService.init()`
- A `_processingInvite` guard prevents concurrent processing if the link fires twice.

---

## 4. Platform Configuration

### Android

**Relevant files:**
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts` → `applicationId = "ch.onewell.lineup"`

**Current intent-filters:**

| Intent Filter | Scheme | Host | autoVerify | Status |
|---|---|---|---|---|
| Deep Link | `lineup` | `join` | `false` | ✅ Active |
| Auth callback | `io.courtswiss` | `login` | `false` | ✅ Active |
| Auth callback | `io.courtswiss` | `reset-password` | `false` | ✅ Active |
| App Link (HTTPS) | `https` | `courtswiss.netlify.app` | `true` | ⚠️ Active in manifest, but **not verified** |

The HTTPS App Link intent-filter for `courtswiss.netlify.app` is present with `android:autoVerify="true"`, but **verification will fail** because the required `/.well-known/assetlinks.json` file does not exist on the Netlify domain. Without successful verification, Android will not open the app directly — it will show a disambiguation dialog or open the browser.

### iOS

**Relevant files:**
- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`

**Info.plist – URL Schemes:**

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>io.courtswiss</string>
      <string>lineup</string>
    </array>
  </dict>
</array>
<key>FlutterDeepLinkingEnabled</key>
<true/>
```

Both `io.courtswiss` and `lineup` custom schemes are registered.

**Runner.entitlements – Associated Domains:**

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:courtswiss.netlify.app</string>
</array>
```

The Associated Domains entitlement is present for `courtswiss.netlify.app`, but **Universal Links will not work** because the required `/.well-known/apple-app-site-association` file does not exist on the Netlify domain. Without this file, iOS will not intercept HTTPS links and will open them in Safari instead.

**Bundle ID:** `ch.onewell.lineup`

---

## 5. Web / Netlify / GitHub

### Netlify domain

The domain `https://courtswiss.netlify.app` is owned and deployed via Netlify (connected to a GitHub repository).

### Current state of `/join` page

The user has deployed a basic `join/index.html` page on Netlify. Its current content displays the token text but **does not redirect to the app**. An updated version with JavaScript redirect logic (`window.location.href = 'lineup://...'`) was prepared but has not been confirmed as deployed.

### `.well-known` files

| File | Path | Status |
|---|---|---|
| `apple-app-site-association` | `/.well-known/apple-app-site-association` | ❌ **Missing** |
| `assetlinks.json` | `/.well-known/assetlinks.json` | ❌ **Missing** |

Neither file exists on the Netlify domain. Without these files, neither Apple Universal Links nor Android App Links can function.

### Supabase Edge Function

A Supabase Edge Function `invite-redirect` exists at `supabase/functions/invite-redirect/index.ts`. It serves an HTML page that attempts to redirect to `lineup://join?token=...`. This function is **not currently used** by the share flow — the share text points to Netlify, not to the Supabase function URL.

---

## 6. Current End-to-End Behavior

### App installed → user clicks invite link

1. User receives WhatsApp message with `https://courtswiss.netlify.app/join?token=<UUID>`.
2. WhatsApp recognizes the HTTPS link as clickable ✅.
3. User taps the link.
4. **iOS:** Safari (or WhatsApp in-app browser) opens the Netlify page. Universal Links do not fire because `apple-app-site-association` is missing. The JavaScript on the page attempts `window.location.href = 'lineup://...'` — this is **blocked** in WhatsApp's in-app browser on iOS. If opened in Safari directly, it **may** trigger the custom scheme.
5. **Android:** Chrome (or WhatsApp in-app browser) opens the Netlify page. App Links do not fire because `assetlinks.json` is missing. The JavaScript redirect to `lineup://` **may or may not work** depending on the browser context.
6. **Result:** User lands on the Netlify webpage. The app does **not** open automatically.

### App not installed → user clicks invite link

1. User taps the link in WhatsApp.
2. Browser opens the Netlify page.
3. The JavaScript redirect to `lineup://` silently fails (no app registered for the scheme).
4. User stays on the Netlify webpage.
5. **Result:** No redirect to App Store / Play Store occurs (not implemented on the current Netlify page).

---

## 7. Gaps, Assumptions, and Risks

### Missing for a fully professional invite flow

1. **`/.well-known/apple-app-site-association`** — required for iOS Universal Links. Must contain the Apple Team ID and the app's bundle ID. Must be served with `Content-Type: application/json` and no redirects.
2. **`/.well-known/assetlinks.json`** — required for Android App Links. Must contain the app's package name and SHA-256 signing certificate fingerprint.
3. **Apple Developer Portal configuration** — the Associated Domains capability must be enabled for the App ID `ch.onewell.lineup` in the Apple Developer portal, not just in the entitlements file.
4. **Netlify MIME type configuration** — `apple-app-site-association` must be served without a file extension but with `Content-Type: application/json`. Netlify may require a `_headers` file to configure this.
5. **Fallback page with App Store links** — the `join/index.html` page does not currently redirect to the App Store or Play Store if the app is not installed. The App Store ID is not yet known.

### Assumptions

- The Supabase RPC functions `create_team_invite` and `accept_team_invite` are assumed to exist and function correctly in the database. No SQL migration files for these functions are present in the local `sql/` directory.
- The `app_links` Flutter package is assumed to support both custom schemes and HTTPS App Links / Universal Links. This is the case for `app_links` v3+.
- The Netlify GitHub repository is separate from the Flutter project repository.
- The app has not yet been published to the App Store (no App Store ID available).

### Likely to break

1. **iOS Universal Links will not work** until `apple-app-site-association` is deployed to `courtswiss.netlify.app/.well-known/` AND the Apple Developer Portal has Associated Domains enabled for the app's provisioning profile.
2. **Android App Links will not work** until `assetlinks.json` is deployed with the correct SHA-256 fingerprint. Additionally, `autoVerify="true"` causes Android to check the file at install time — if verification fails, the app must be reinstalled after fixing the file.
3. **WhatsApp in-app browser** — even with a JavaScript fallback, custom scheme redirects (`lineup://`) are unreliable in WhatsApp's embedded browser on both platforms. Universal Links / App Links are the only reliable solution.
4. **Debug vs. Release signing** — the SHA-256 fingerprint differs between debug and release builds. Both may need to be listed in `assetlinks.json` during development.

---

## Baseline Summary

The invitation link system currently generates a valid HTTPS link (`https://courtswiss.netlify.app/join?token=<UUID>`) that is clickable in messaging apps like WhatsApp. The Flutter app has the Dart-side infrastructure fully in place: `DeepLinkService` handles both custom scheme and HTTPS URIs, `AuthGate` processes invite tokens on cold start and in the foreground, and `InviteService` provides clean methods for token creation, link building, and sharing via the native Share Sheet.

However, the platform-level configuration for direct app opening is **incomplete on both iOS and Android**. While the `Runner.entitlements` file declares `applinks:courtswiss.netlify.app` and the `AndroidManifest.xml` includes an `autoVerify="true"` intent-filter for the same domain, the required server-side verification files (`apple-app-site-association` and `assetlinks.json`) do not exist on the Netlify domain. As a result, clicking the HTTPS link always opens the browser first — the app never intercepts the link directly. Until these two files are deployed with the correct credentials (Apple Team ID and Android SHA-256 fingerprint), the invite flow will rely on a JavaScript-based fallback redirect from the Netlify webpage, which is unreliable in embedded browsers like WhatsApp's.
