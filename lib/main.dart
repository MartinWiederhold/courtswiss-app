// ── DEV NOTE ──────────────────────────────────────────────────────
// UPDATED: Removed forced signInAnonymously on cold start.
// Anonymous sessions are now created on-demand only for invite flows.
// Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:swisscourt/screens/auth_gate.dart';
import 'package:swisscourt/services/deep_link_service.dart';
import 'package:swisscourt/services/local_notification_service.dart';
import 'package:swisscourt/services/push_service.dart';
import 'package:swisscourt/theme/cs_theme.dart';
import 'package:swisscourt/widgets/ui/cs_splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildCsTheme(),
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
