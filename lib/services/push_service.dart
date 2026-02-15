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
  debugPrint(
    'PushService [background] ${message.messageId} '
    'data=${message.data}',
  );
}

/// Global navigator key – set on MaterialApp so PushService can navigate
/// when the user taps a push notification.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Service that wires up Firebase Cloud Messaging:
///   1. Request permission (iOS + Android 13+)
///   2. Get FCM token → store in cs_device_tokens
///   3. Listen for token refresh → update in DB
///   4. Listen for auth changes → re-register token under new user_id
///   5. Handle foreground messages (show local notification)
///   6. Handle notification tap → navigate to MatchDetailScreen
///
/// Call [initPush] once after the user has an auth session
/// (so auth.uid() is available for the token upsert).
class PushService {
  static bool _initialized = false;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<AuthState>? _authSub;

  /// Last known FCM token (for debug display in UI).
  static String? lastToken;

  /// The user_id we last registered the token for.
  /// Used to detect session changes and avoid duplicate registrations.
  static String? _lastRegisteredUserId;

  // ── Public API ──────────────────────────────────────────────────

  /// Initialise FCM. Safe to call multiple times (no-op after first).
  /// Must be called AFTER Firebase.initializeApp() and AFTER Supabase auth.
  static Future<void> initPush() async {
    if (_initialized) return;
    _initialized = true;

    // ignore: avoid_print
    print('PUSH_INIT userId=${Supabase.instance.client.auth.currentUser?.id}');

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
        'PushService permission: ${settings.authorizationStatus.name}',
      );
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
        await _registerTokenForCurrentUser(token);
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
      await _registerTokenForCurrentUser(newToken);
    });

    // ── 4. Listen for auth changes → re-register token ───────────
    _authSub?.cancel();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      _onAuthStateChanged,
    );

    // ── 5. Foreground messages → show local notification ─────────
    _fgSub?.cancel();
    _fgSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // ── 6. Notification tap (app was in background) ──────────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // ── 7. Cold start: app opened via notification tap ───────────
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
    _authSub?.cancel();
    _fgSub = null;
    _tokenRefreshSub = null;
    _authSub = null;
    _initialized = false;
    _lastRegisteredUserId = null;
  }

  // ── Internal: token registration ───────────────────────────────

  /// Called when the Supabase auth state changes.
  /// If the user_id differs from the last registration, re-register the
  /// FCM token so it belongs to the current session.
  static void _onAuthStateChanged(AuthState authState) {
    final newUserId = Supabase.instance.client.auth.currentUser?.id;
    if (newUserId == null) {
      // No session → nothing to register
      debugPrint('PushService [auth] session cleared, skip re-register');
      return;
    }

    // Only re-register if user actually changed
    if (newUserId == _lastRegisteredUserId) return;

    final token = lastToken;
    if (token == null || token.isEmpty) {
      debugPrint(
        'PushService [auth] user changed to '
        '${newUserId.substring(0, 8)}… but no FCM token yet',
      );
      return;
    }

    // ignore: avoid_print
    print(
      'PushService [auth] user changed: '
      '${_lastRegisteredUserId?.substring(0, 8) ?? 'null'}… → '
      '${newUserId.substring(0, 8)}… – re-registering token',
    );

    _registerTokenForCurrentUser(token);
  }

  /// Register the FCM [token] in cs_device_tokens for the current
  /// Supabase auth.uid().  Guards against null user and duplicate calls.
  static Future<void> _registerTokenForCurrentUser(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('PushService _registerToken: currentUser is null, skipping');
      return;
    }

    // Avoid duplicate registrations for the same user + same token
    if (userId == _lastRegisteredUserId && token == lastToken) {
      // Already registered exactly this combination → skip
      // (but still allow if token is new even if userId is same)
    }

    final tokenPrefix = token.length > 12 ? token.substring(0, 12) : token;
    // ignore: avoid_print
    print(
      'PushService REGISTER userId=${userId.substring(0, 8)}… '
      'token=$tokenPrefix…',
    );

    try {
      await DeviceTokenService.registerToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      _lastRegisteredUserId = userId;
      // ignore: avoid_print
      print('PushService REGISTER OK for ${userId.substring(0, 8)}…');
    } catch (e) {
      debugPrint('PushService _registerToken error: $e');
    }
  }

  // ── Internal: message handling ─────────────────────────────────

  /// Show a local notification for foreground FCM messages.
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      'PushService [foreground] ${message.messageId} '
      'title=${message.notification?.title} '
      'data=${message.data}',
    );

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
      debugPrint(
        'PushService: navigatorKey not available, '
        'cannot navigate to match $matchId',
      );
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
          builder: (_) =>
              MatchDetailScreen(matchId: matchId, teamId: teamId, match: match),
        ),
      );
    } catch (e) {
      debugPrint('PushService _navigateToMatch error: $e');
    }
  }
}
