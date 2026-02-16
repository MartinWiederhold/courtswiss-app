# Bundle ID Status — Lineup

> Datum: 2026-02-16
> Quelle: Automatisierte Prüfung des Repos (read-only, keine Änderungen)

---

## iOS

### PRODUCT_BUNDLE_IDENTIFIER (project.pbxproj)

| Build Configuration | Identifier | Zeile |
|---|---|---|
| Debug | `com.example.swisscourt` | 711 |
| Release | `com.example.swisscourt` | 687 |
| Profile | `com.example.swisscourt` | 503 |
| RunnerTests (Debug) | `com.example.swisscourt.RunnerTests` | 520 |
| RunnerTests (Release) | `com.example.swisscourt.RunnerTests` | 538 |
| RunnerTests (Profile) | `com.example.swisscourt.RunnerTests` | 554 |

### CFBundleIdentifier (Info.plist)
- **Wert:** `$(PRODUCT_BUNDLE_IDENTIFIER)` (dynamisch aus Build Settings, **nicht** hardcoded)
- Datei: `ios/Runner/Info.plist`, Zeile 12

### CFBundleDisplayName / CFBundleName (Info.plist)
- CFBundleDisplayName: `Lineup`
- CFBundleName: `Lineup`

### Runner.entitlements
- Datei: `ios/Runner/Runner.entitlements`
- Inhalt: nur `aps-environment = production`
- **Keine explizite App-ID referenziert** (korrekt — die App ID wird über Xcode Signing + Bundle ID zugeordnet)

### GoogleService-Info.plist (Firebase iOS)
- BUNDLE_ID: `com.example.swisscourt`
- PROJECT_ID: `courtswiss-65a34`
- GCM_SENDER_ID: `73144175672`
- GOOGLE_APP_ID: `1:73144175672:ios:78df6526f25e93e783aacd`
- STORAGE_BUCKET: `courtswiss-65a34.firebasestorage.app`

### Firebase Initialisierung (Flutter)
- Methode: `Firebase.initializeApp()` **ohne** `DefaultFirebaseOptions` — greift auf `GoogleService-Info.plist` (iOS) bzw. `google-services.json` (Android) zurück
- Kein `firebase_options.dart` im Projekt vorhanden (FlutterFire CLI wurde nicht verwendet)

### URL Schemes (Info.plist)
- `lineup` (für `lineup://join`)
- `io.courtswiss` (für `io.courtswiss://login`, `io.courtswiss://reset-password`)

### Auffälligkeiten / Inkonsistenzen
- ⚠️ **`com.example.swisscourt`** ist eine Platzhalter-Bundle-ID (Xcode Default). Diese **muss** vor einem App Store Release geändert werden.
- ⚠️ Die Bundle ID in `GoogleService-Info.plist` muss mit der neuen Bundle ID übereinstimmen (neues Plist aus Firebase Console herunterladen nach Änderung).
- ⚠️ Firebase-Projekt heißt noch `courtswiss-65a34` — das Projekt selbst muss nicht umbenannt werden, aber eine neue iOS App mit der neuen Bundle ID muss in Firebase angelegt werden.

---

## Android

### applicationId (build.gradle.kts)
- **Wert:** `com.example.swisscourt`
- Datei: `android/app/build.gradle.kts`, Zeile `applicationId = "com.example.swisscourt"`

### namespace (build.gradle.kts)
- **Wert:** `com.example.swisscourt`
- Datei: `android/app/build.gradle.kts`, Zeile `namespace = "com.example.swisscourt"`

### AndroidManifest.xml
- **package Attribut:** ❌ Nicht gesetzt (korrekt für neue AGP-Versionen, namespace in build.gradle.kts wird stattdessen verwendet)
- android:label: `@string/app_name` → aufgelöst zu **`Lineup`** (`android/app/src/main/res/values/strings.xml`)

### MainActivity
- **Dateipfad:** `android/app/src/main/kotlin/com/example/swisscourt/MainActivity.kt`
- **package Deklaration:** `package com.example.swisscourt`
- Klasse: `class MainActivity : FlutterActivity()`

### google-services.json (Firebase Android)
- package_name: `com.example.swisscourt`
- project_id: `courtswiss-65a34`
- mobilesdk_app_id: `1:73144175672:android:6f218e1de41746e383aacd`

### Intent Filter (AndroidManifest.xml)
- `lineup://join` (Invite Deep Link)
- `io.courtswiss://login` (Auth Callback)
- `io.courtswiss://reset-password` (Password Reset Callback)

### Auffälligkeiten / Inkonsistenzen
- ⚠️ **`com.example.swisscourt`** ist eine Platzhalter-applicationId. **Muss** vor Play Store Release geändert werden.
- ⚠️ Bei Änderung der applicationId müssen auch `namespace` und das Kotlin-Verzeichnis (`android/app/src/main/kotlin/com/example/swisscourt/`) umbenannt werden.
- ⚠️ `google-services.json` muss nach Anlegen einer neuen Android App in Firebase Console neu heruntergeladen werden.
- ⚠️ **Kein Release Signing Config** vorhanden — aktuell wird mit Debug-Keystore signiert (`signingConfig = signingConfigs.getByName("debug")`).

---

## Zusammenfassung

| Komponente | Aktueller Wert | Muss geändert werden? |
|---|---|---|
| iOS PRODUCT_BUNDLE_IDENTIFIER | `com.example.swisscourt` | ✅ Ja |
| iOS GoogleService-Info.plist BUNDLE_ID | `com.example.swisscourt` | ✅ Ja (neue Datei aus Firebase) |
| Android applicationId | `com.example.swisscourt` | ✅ Ja |
| Android namespace | `com.example.swisscourt` | ✅ Ja |
| Android Kotlin Package Path | `com/example/swisscourt/` | ✅ Ja |
| Android google-services.json package_name | `com.example.swisscourt` | ✅ Ja (neue Datei aus Firebase) |
| Firebase Projekt-ID | `courtswiss-65a34` | ❌ Bleibt (Projekt umbenennen nicht nötig) |
| iOS URL Schemes | `lineup`, `io.courtswiss` | ❌ Bleiben |
| Android Intent Filter Schemes | `lineup`, `io.courtswiss` | ❌ Bleiben |
| iOS Runner.entitlements | `aps-environment = production` | ❌ Bleibt |
| iOS/Android Display Name | `Lineup` | ❌ Bleibt |
