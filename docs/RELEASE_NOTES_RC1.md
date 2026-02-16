# Release Notes — RC1 (Lineup)

> Datum: 2026-02-16

---

## Bundle ID Migration

- **Bundle ID migrated to `ch.onewell.lineup` (code-only). Firebase config pending.**
- Alte ID: `com.example.swisscourt`
- Neue ID: `ch.onewell.lineup`

### Geänderte Dateien

| Datei | Änderung |
|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` → `ch.onewell.lineup` (Debug/Release/Profile) |
| `ios/Runner.xcodeproj/project.pbxproj` | RunnerTests → `ch.onewell.lineup.RunnerTests` |
| `android/app/build.gradle.kts` | `applicationId` → `ch.onewell.lineup` |
| `android/app/build.gradle.kts` | `namespace` → `ch.onewell.lineup` |
| `android/app/src/main/kotlin/ch/onewell/lineup/MainActivity.kt` | Neu (verschoben von `com/example/swisscourt/`) |

### Nicht geändert (bewusst)

| Datei | Grund |
|---|---|
| `ios/Runner/Info.plist` | `CFBundleIdentifier` ist dynamisch `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| `ios/Runner/Runner.entitlements` | Enthält nur `aps-environment`, keine Bundle ID |
| `android/app/src/main/AndroidManifest.xml` | Kein `package`-Attribut (namespace aus Gradle), Intent-Filter unverändert |
| `ios/Runner/GoogleService-Info.plist` | ⚠️ Enthält noch `com.example.swisscourt` — muss nach Firebase-Umstellung neu heruntergeladen werden |
| `android/app/google-services.json` | ⚠️ Enthält noch `com.example.swisscourt` — muss nach Firebase-Umstellung neu heruntergeladen werden |

### Offene Portal-Schritte (manuell)

1. **Apple Developer Portal**: App ID `ch.onewell.lineup` erstellen, Push Notification Capability aktivieren
2. **Firebase Console (iOS)**: Neue iOS App mit Bundle ID `ch.onewell.lineup` anlegen → `GoogleService-Info.plist` herunterladen → nach `ios/Runner/` kopieren
3. **Firebase Console (Android)**: Neue Android App mit Package `ch.onewell.lineup` anlegen → `google-services.json` herunterladen → nach `android/app/` kopieren
4. **Firebase Console (iOS)**: APNs Auth Key (.p8) der neuen iOS App zuordnen
5. **Supabase Dashboard**: Redirect URL Allowlist prüfen (falls Bundle ID in Auth-Callbacks referenziert wird)

### Verifizierung

- `flutter analyze`: ✅ 0 Errors, 0 Warnings (12 pre-existing info lints)
- URL Schemes intakt: `lineup://join`, `io.courtswiss://login`, `io.courtswiss://reset-password`
- iOS Entitlements intakt: `aps-environment = production`

---

## CocoaPods Base Configuration Fix

- **Fix: CocoaPods base configuration warning eliminated.**
- Ursache: Runner Target Profile-Config nutzte `Release.xcconfig` als Base, dadurch wurde `Pods-Runner.profile.xcconfig` nie inkludiert.
- CocoaPods konnte die Base-Config nicht setzen → Warning beim `pod install`.

### Geänderte Dateien

| Datei | Änderung |
|---|---|
| `ios/Flutter/Profile.xcconfig` | **Neu erstellt** — inkludiert `Pods-Runner.profile.xcconfig` + `Generated.xcconfig` |
| `ios/Runner.xcodeproj/project.pbxproj` | PBXFileReference für `Profile.xcconfig` hinzugefügt |
| `ios/Runner.xcodeproj/project.pbxproj` | Flutter-Gruppe: `Profile.xcconfig` zu children hinzugefügt |
| `ios/Runner.xcodeproj/project.pbxproj` | Runner Target Profile: `baseConfigurationReference` → `Profile.xcconfig` (vorher: `Release.xcconfig`) |

### Verifizierung

- `pod install`: ✅ Keine Warnings mehr
- Runner Target Base Configs korrekt:
  - Debug → `Debug.xcconfig` (#include Pods-Runner.debug)
  - Release → `Release.xcconfig` (#include Pods-Runner.release)
  - Profile → `Profile.xcconfig` (#include Pods-Runner.profile)
