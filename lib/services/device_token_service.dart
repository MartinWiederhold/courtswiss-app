import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Service for managing device tokens (FCM/APNs registration).
///
/// Currently only handles DB registration (cs_device_tokens via RPC).
/// Actual FCM/APNs token retrieval is NOT implemented yet – call
/// [registerToken] with the token once FCM is integrated.
class DeviceTokenService {
  static final _supabase = Supabase.instance.client;
  static const _deviceIdKey = 'cs_device_id';

  /// Returns a stable device identifier.
  /// Generated once via UUID v4 and persisted in SharedPreferences.
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// Detect current platform as the string expected by cs_device_tokens.
  static String get currentPlatform {
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Register (or update) a push token for the current device.
  ///
  /// [token] – the FCM/APNs token string.
  /// [platform] – 'ios' or 'android'. Auto-detected if omitted.
  /// [enabled] – whether push is enabled for this device.
  static Future<void> registerToken({
    required String token,
    String? platform,
    bool enabled = true,
  }) async {
    final deviceId = await getOrCreateDeviceId();
    final plat = platform ?? currentPlatform;

    try {
      await _supabase.rpc('cs_upsert_device_token', params: {
        'p_platform': plat,
        'p_token': token,
        'p_device_id': deviceId,
        'p_enabled': enabled,
      });
    } catch (e) {
      debugPrint('DeviceTokenService.registerToken error: $e');
      rethrow;
    }
  }

  /// Convenience: mark the current device as disabled (e.g. on logout).
  static Future<void> disableCurrentDevice() async {
    final deviceId = await getOrCreateDeviceId();
    try {
      await _supabase.rpc('cs_upsert_device_token', params: {
        'p_platform': currentPlatform,
        'p_token': '', // empty token – device disabled
        'p_device_id': deviceId,
        'p_enabled': false,
      });
    } catch (e) {
      debugPrint('DeviceTokenService.disableCurrentDevice error: $e');
    }
  }
}
