import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support_platform_stub.dart'
    if (dart.library.io) 'support_platform_io.dart' as support_platform;

class SupportService {
  static final _supabase = Supabase.instance.client;

  static const categories = <String>{
    'TECHNICAL',
    'GENERAL',
    'FEEDBACK',
  };

  static bool isValidCategory(String? category) {
    if (category == null) return false;
    return categories.contains(category);
  }

  static bool isValidMessage(String message) {
    final len = message.trim().length;
    return len >= 10 && len <= 4000;
  }

  static bool isValidEmail(String? email) {
    if (email == null || email.trim().isEmpty) return true;
    final value = email.trim();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(value);
  }

  static String? _normalizeOptional(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static Future<void> sendContactMessage({
    required String category, // TECHNICAL|GENERAL|FEEDBACK
    String? subject,
    required String message,
    String? email,
  }) async {
    if (!isValidCategory(category)) {
      throw ArgumentError('Invalid support category');
    }
    if (!isValidMessage(message)) {
      throw ArgumentError('Message must be between 10 and 4000 characters');
    }
    if (!isValidEmail(email)) {
      throw ArgumentError('Invalid email format');
    }

    final user = _supabase.auth.currentUser;
    final userId = user?.id;
    final userEmail = user?.email;
    final platform = kIsWeb ? 'web' : support_platform.detectSupportPlatform();

    final payload = <String, dynamic>{
      'category': category,
      'subject': _normalizeOptional(subject),
      'message': message.trim(),
      'email': _normalizeOptional(email),
      'userId': userId,
      'userEmail': userEmail,
      'platform': platform,
      'appVersion': 'unknown',
    };

    try {
      final response = await _supabase.functions.invoke(
        'support-contact',
        body: payload,
      );

      if (response.status < 200 || response.status >= 300) {
        throw Exception(
          'support-contact failed with status ${response.status}',
        );
      }

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final ok = data['ok'] == true;
        if (!ok) {
          throw Exception(
            'support-contact returned error: ${data['error'] ?? 'unknown'}',
          );
        }
      }
    } catch (e) {
      rethrow;
    }
  }
}
