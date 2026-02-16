// ── DEV NOTE ──────────────────────────────────────────────────────
// UPDATED: Removed forced signInAnonymously on cold start.
// Anonymous sessions are now created on-demand only for invite flows.
// Auth/Onboarding v2 rework.
// UPDATED: Added localization infrastructure (de/en) with reactive
// locale switching via LocaleController.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:swisscourt/l10n/app_localizations.dart';
import 'package:swisscourt/screens/auth_gate.dart';
import 'package:swisscourt/services/deep_link_service.dart';
import 'package:swisscourt/services/locale_controller.dart';
import 'package:swisscourt/services/local_notification_service.dart';
import 'package:swisscourt/services/push_service.dart';
import 'package:swisscourt/theme/cs_theme.dart';
import 'package:swisscourt/widgets/ui/cs_splash_overlay.dart';

/// Global locale controller – accessible from any screen (e.g. ProfilScreen).
final localeController = LocaleController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──────────────────────────────────────
  // Log Flutter framework errors (assertions, layout, build) to the
  // console instead of showing the red error screen in debug mode.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('┌── FlutterError ──────────────────────────────────');
      debugPrint('│ ${details.exceptionAsString()}');
      debugPrint('│ ${details.stack}');
      debugPrint('└─────────────────────────────────────────────────');
    }
  };

  // Catch async errors that aren't caught by Flutter framework.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('┌── PlatformDispatcher.onError ────────────────────');
      debugPrint('│ $error');
      debugPrint('│ $stack');
      debugPrint('└─────────────────────────────────────────────────');
    }
    return true; // handled — don't crash the app
  };

  await dotenv.load(fileName: ".env");

  // Firebase must be initialised before any Firebase service is used.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase.initializeApp failed: $e');
  }

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // ── No longer auto-creating anonymous session on cold start ──
  // Anonymous sessions are created on-demand ONLY when an invite link
  // is opened without an existing session (see AuthGate._handleInviteAnon).
  // ignore: avoid_print
  print('APP_START userId=${Supabase.instance.client.auth.currentUser?.id}');

  await DeepLinkService.instance.init();

  // Initialise local push notifications (degrades gracefully)
  await LocalNotificationService.init();
  await LocalNotificationService.requestPermission();

  // Load persisted locale before building the widget tree
  await localeController.loadSavedLocale();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    localeController.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    localeController.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildCsTheme(),

      // ── Localization ──────────────────────────────────
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeController.locale, // null → follow system

      builder: (context, child) {
        return Stack(
          children: [
            child!,
            if (_showSplash)
              CsSplashOverlay(
                onFinished: () {
                  if (mounted) setState(() => _showSplash = false);
                },
              ),
          ],
        );
      },
      home: const AuthGate(),
    );
  }
}
