import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/match_detail_screen.dart';
import 'device_token_service.dart';
import 'local_notification_service.dart';

/// Top-level handler for background/terminated FCM messages.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Minimal: just log. Heavy work (navigation) is not possible here.
  debugPrint('PushService [background] ${message.messageId} '
      'data=${message.data}');
}

/// Global navigator key – set on MaterialApp so PushService can navigate
/// when the user taps a push notification.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Service that wires up Firebase Cloud Messaging:
///   1. Request permission (iOS)
///   2. Get FCM token → store in cs_device_tokens
///   3. Listen for token refresh → update in DB
///   4. Handle foreground messages (show local notification)
///   5. Handle notification tap → navigate to MatchDetailScreen
///
/// Call [initPush] once after the user has an auth session
/// (so auth.uid() is available for the token upsert).
class PushService {
  static bool _initialized = false;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Last known FCM token (for debug display in UI).
  static String? lastToken;

  /// Initialise FCM. Safe to call multiple times (no-op after first).
  /// Must be called AFTER Firebase.initializeApp() and AFTER Supabase auth.
  static Future<void> initPush() async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ── 1. Request permission ────────────────────────────────────
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
          'PushService permission: ${settings.authorizationStatus.name}');
    } catch (e) {
      debugPrint('PushService requestPermission error: $e');
    }

    // ── 2. Get current FCM token and register it ─────────────────
    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        lastToken = token;
        // ignore: avoid_print
        print('FCM_TOKEN: $token');
        await _registerToken(token);
      }
    } catch (e) {
      debugPrint('PushService getToken error: $e');
    }

    // ── 3. Listen for token refresh ──────────────────────────────
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      lastToken = newToken;
      // ignore: avoid_print
      print('FCM_TOKEN (refreshed): $newToken');
      await _registerToken(newToken);
    });

    // ── 4. Foreground messages → show local notification ─────────
    _fgSub?.cancel();
    _fgSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // ── 5. Notification tap (app was in background) ──────────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // ── 6. Cold start: app opened via notification tap ───────────
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _handleNotificationTap(initial);
      }
    } catch (e) {
      debugPrint('PushService getInitialMessage error: $e');
    }
  }

  /// Clean up subscriptions (e.g. on logout).
  static void dispose() {
    _fgSub?.cancel();
    _tokenRefreshSub?.cancel();
    _fgSub = null;
    _tokenRefreshSub = null;
    _initialized = false;
  }

  // ── Internal ──────────────────────────────────────────────────

  /// Store FCM token in Supabase via DeviceTokenService.
  static Future<void> _registerToken(String token) async {
    try {
      await DeviceTokenService.registerToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } catch (e) {
      debugPrint('PushService _registerToken error: $e');
    }
  }

  /// Show a local notification for foreground FCM messages.
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('PushService [foreground] ${message.messageId} '
        'title=${message.notification?.title} '
        'data=${message.data}');

    final notification = message.notification;
    if (notification != null) {
      LocalNotificationService.show(
        title: notification.title ?? 'CourtSwiss',
        body: notification.body ?? '',
        payload: message.data['match_id'] as String?,
      );
    }
  }

  /// Handle a tap on a push notification.
  /// If data contains match_id + team_id, navigate to MatchDetailScreen.
  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint('PushService [tap] data=${message.data}');

    final matchId = message.data['match_id'] as String?;
    final teamId = message.data['team_id'] as String?;

    if (matchId != null && teamId != null) {
      _navigateToMatch(matchId: matchId, teamId: teamId);
    }
  }

  /// Navigate to MatchDetailScreen using the global [navigatorKey].
  static Future<void> _navigateToMatch({
    required String matchId,
    required String teamId,
  }) async {
    // Wait briefly so that the widget tree is ready after cold start.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint('PushService: navigatorKey not available, '
          'cannot navigate to match $matchId');
      return;
    }

    try {
      final match = await Supabase.instance.client
          .from('cs_matches')
          .select()
          .eq('id', matchId)
          .maybeSingle();

      if (match == null) {
        debugPrint('PushService: match $matchId not found or deleted');
        return;
      }

      nav.push(
        MaterialPageRoute(
          builder: (_) => MatchDetailScreen(
            matchId: matchId,
            teamId: teamId,
            match: match,
          ),
        ),
      );
    } catch (e) {
      debugPrint('PushService _navigateToMatch error: $e');
    }
  }
}
