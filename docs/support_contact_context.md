# Support Contact Context (Analyse Only)

## 1) App Stack

- **Plattformen (Repo-Struktur):**
  - `ios/` vorhanden
  - `android/` vorhanden
  - `web/` vorhanden
  - Zusätzlich: `macos/`, `linux/`, `windows/`
- **Framework:** Flutter (`pubspec.yaml`)
- **Programmiersprachen:**
  - Dart (App-Code unter `lib/`)
  - TypeScript/Deno (Supabase Edge Functions unter `supabase/functions/*/index.ts`)
  - SQL (Migrationen/Funktionen unter `sql/*.sql`)
- **State Management (vorhanden):**
  - `StatefulWidget` + `setState` in Screens (z. B. `lib/screens/profil_screen.dart`)
  - `StreamBuilder` für Auth-State (z. B. `lib/screens/auth_gate.dart`)
  - Service-Klassen mit statischen Methoden (z. B. `lib/services/*`)
  - **Nicht vorhanden:** Provider, Riverpod, Bloc/Cubit (keine entsprechenden Dependencies in `pubspec.yaml`)
- **Networking Layer:**
  - Primär Supabase Client via `supabase_flutter`:
    - `Supabase.instance.client.from(...)`
    - `Supabase.instance.client.rpc(...)`
  - Initialisierung in `lib/main.dart` mit ENV (`SUPABASE_URL`, `SUPABASE_ANON_KEY`)
  - **Nicht vorhanden:** eigener REST-HTTP-Client im Flutter-App-Code

## 2) Profil-Screen

- **Dateipfade:**
  - `lib/screens/profil_screen.dart` (Profil-Tab UI)
  - `lib/screens/main_tab_screen.dart` (Bottom-Tab-Navigation inkl. Profil-Tab)
- **UI-Aufbau (`profil_screen.dart`):**
  - `CsScaffoldList` + `CsGlassAppBar`
  - Body als `ListView` mit mehreren `CsLightCard`-Sektionen
  - Vorhandene Sektionen: User-Info, Sprache, Push-Einstellungen, Kontoaktionen, App-Version
- **Navigation Pattern (im Profil-Screen):**
  - **Push:** `Navigator.push(...)` zu `AuthScreen` (anonymer User)
  - **Dialog/Modal:** `showDialog<bool>(...)` für Account-Löschung
  - **Sheet/BottomSheet:** im Profil-Screen aktuell **nicht vorhanden**
- **Beste Stelle für neue "Kontakt"-Sektion:**
  - In `lib/screens/profil_screen.dart` als zusätzliche `CsLightCard`-Sektion in der bestehenden `ListView`
  - Konsistente Position gemäß bestehendem Aufbau: zwischen Konto-Aktionen und App-Version

## 3) Backend / API

- **Bestehendes Backend:** Supabase
  - DB/RPC-Zugriffe aus Flutter über `supabase_flutter`
  - Edge Functions unter `supabase/functions/`
- **Speicherort bestehender API-Endpunkte:**
  - **Clientseitig aufgerufen (RPC/DB):** `lib/services/*.dart`
  - **Serverless Endpoints:** `supabase/functions/*/index.ts`
    - `supabase/functions/send-push/index.ts`
    - `supabase/functions/match-reminders/index.ts`
    - `supabase/functions/expire-sub-requests/index.ts`
    - `supabase/functions/invite-redirect/index.ts`
- **ENV-Handling:**
  - Flutter-App: `.env` via `flutter_dotenv` in `lib/main.dart`
  - Edge Functions: `Deno.env.get(...)` (z. B. `SUPABASE_SERVICE_ROLE_KEY`, `GOOGLE_SERVICE_ACCOUNT_JSON`)
  - Supabase-Config: `supabase/config.toml`
- **SendGrid/Mail-Code vorhanden?**
  - **Direkter SendGrid-Sende-Code im Repo: nicht vorhanden**
  - In `supabase/config.toml` gibt es nur auskommentierte SMTP-Beispiele (`smtp.sendgrid.net`)
  - Kein bestehender Kontaktformular-Endpunkt für Mailversand gefunden

## 4) Auth / User Context

- **User-ID vorhanden:** Ja
  - Quelle: `Supabase.instance.client.auth.currentUser?.id`
  - Beispiele: `lib/screens/profil_screen.dart`, `lib/main.dart`, diverse `lib/services/*.dart`
- **Verfügbare User-Daten im bestehenden Code:**
  - `userId`: vorhanden (siehe oben)
  - `email`: vorhanden über `currentUser?.email` (kann bei anonymen Usern `null` sein)
    - Beispiel: `lib/screens/profil_screen.dart`, `lib/services/profile_service.dart`
  - `appVersion`: derzeit als statischer lokalisierter String (`l.appVersion`)
    - Quelle: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, Anzeige in `lib/screens/profil_screen.dart`
    - **Hinweis:** Keine dynamische Ermittlung via `package_info_plus` im aktuellen Code
  - `platform`: vorhanden über `dart:io Platform` in Push/Device-Kontext
    - Beispiele: `lib/services/device_token_service.dart`, `lib/services/push_service.dart`

## 5) Error / Toast / Alert System

- **Globales Toast-System:** vorhanden
  - `lib/widgets/ui/cs_toast.dart`
  - API: `CsToast.success(...)`, `CsToast.error(...)`, `CsToast.info(...)`
  - Intern via `ScaffoldMessenger` + `SnackBar`
- **Alerts/Dialoge:** vorhanden
  - `showDialog(...)` z. B. in `lib/screens/profil_screen.dart` (Delete Account)
- **BottomSheet-Komponente:** vorhanden (global), aber nicht im Profil verwendet
  - Export in `lib/widgets/ui/ui.dart`
  - Komponente: `lib/widgets/ui/cs_bottom_sheet_form.dart`

## 6) Analytics / Logging

- **Analytics in App (Firebase Analytics/PostHog/Segment/Amplitude):**
  - **Nicht vorhanden** (keine entsprechenden Dependencies/Usage im Flutter-App-Code)
- **Logging:**
  - App-seitig: `debugPrint(...)` / `print(...)` verteilt in `lib/main.dart`, `lib/services/*`, `lib/screens/*`
  - Edge Functions: `console.log(...)` / `console.error(...)` in `supabase/functions/*/index.ts`

## 7) Testing Setup

- **App Test-Framework:** `flutter_test` (siehe `pubspec.yaml`)
- **Test-Speicherort (App):** `test/*.dart`
  - Beispiele: `test/widget_test.dart`, `test/lineup_rules_test.dart`, `test/expense_split_test.dart`, `test/dinner_rsvp_test.dart`
- **Integration-Tests (`integration_test/`):** **nicht vorhanden**
- **Zusätzliche Tooling-Tests:** `bmad/test/*` (Node/JS-basiert, nicht App-Feature-Tests)

## 8) Empfehlungen (technisch, minimal, auf bestehender Architektur)

- **Client-Code ergänzen (Profil):**
  - Kontakt-UI als neue Card-Sektion in `lib/screens/profil_screen.dart`
  - Feedback über bestehendes `CsToast`-System
  - Nutzerkontext aus bestehender Session ziehen (`currentUser?.id`, `currentUser?.email`)
- **Server/Serverless Endpoint (Mailversand):**
  - Neuer Supabase Edge Function Endpoint unter `supabase/functions/<contact-function>/index.ts`
  - Begründung: Edge-Functions sind bereits etabliert und nutzen Secret-Handling via `Deno.env`
  - SendGrid API Key ausschließlich serverseitig als Secret; kein Versand direkt aus Flutter
- **Architektur-Patterns beibehalten:**
  - Service-orientierter Client (analog `lib/services/*`)
  - Keine iOS-spezifischen Änderungen erforderlich
  - Kein Bruch bestehender Auth/Push/Team-Flows; bestehende Supabase-Session und UI-Patterns wiederverwenden

