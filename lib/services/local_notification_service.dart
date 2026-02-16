import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications.
/// Initialisation is safe to call multiple times and degrades gracefully
/// if platform config is incomplete.
class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Initialise the plugin. Must be called once, ideally in main().
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      final ok = await _plugin.initialize(settings);
      _initialized = ok ?? false;
      debugPrint('LocalNotificationService init: $_initialized');
    } catch (e) {
      debugPrint('LocalNotificationService init failed: $e');
    }
  }

  /// Show a local notification.
  static Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'lineup_default', // channel id
      'Lineup', // channel name
      channelDescription: 'Lineup Benachrichtigungen',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('LocalNotificationService show failed: $e');
    }
  }

  /// Request notification permissions (Android 13+ / iOS).
  static Future<bool> requestPermission() async {
    if (!_initialized) return false;
    try {
      // Android 13+
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      // iOS permissions are requested during init
      return true;
    } catch (e) {
      debugPrint('requestPermission failed: $e');
      return false;
    }
  }
}
