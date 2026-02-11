import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for reading/writing notification preferences
/// (global + per-team overrides) via cs_notification_prefs RPCs.
///
/// No actual push sending – just the preference layer.
class PushPrefsService {
  static final _supabase = Supabase.instance.client;

  /// Known event types that users can individually disable.
  static const List<String> allEventTypes = [
    'lineup_published',
    'replacement_promoted',
    'no_reserve_available',
  ];

  /// Human-readable labels for event types (German).
  static String eventTypeLabel(String type) {
    switch (type) {
      case 'lineup_published':
        return 'Aufstellung veröffentlicht';
      case 'replacement_promoted':
        return 'Ersatz nachgerückt';
      case 'no_reserve_available':
        return 'Kein Ersatz verfügbar';
      default:
        return type;
    }
  }

  /// Fetch notification prefs for a specific team or global (teamId=null).
  /// Returns a map with keys: `push_enabled` (bool), `types_disabled` (List of String).
  static Future<Map<String, dynamic>> getPrefs({String? teamId}) async {
    try {
      final result = await _supabase.rpc(
        'cs_get_notification_prefs',
        params: {'p_team_id': teamId},
      );

      if (result is Map<String, dynamic>) {
        return {
          'push_enabled': result['push_enabled'] as bool? ?? true,
          'types_disabled': _parseTypesDisabled(result['types_disabled']),
        };
      }
      return _defaults();
    } catch (e) {
      debugPrint('PushPrefsService.getPrefs error: $e');
      return _defaults();
    }
  }

  /// Save notification prefs (upsert).
  static Future<void> setPrefs({
    String? teamId,
    required bool pushEnabled,
    required List<String> typesDisabled,
  }) async {
    await _supabase.rpc('cs_set_notification_prefs', params: {
      'p_team_id': teamId,
      'p_push_enabled': pushEnabled,
      'p_types_disabled': typesDisabled,
    });
  }

  // ── Internal ──────────────────────────────────────────────────

  static Map<String, dynamic> _defaults() => {
        'push_enabled': true,
        'types_disabled': <String>[],
      };

  /// Parse the types_disabled field which may come as List or JSON array.
  static List<String> _parseTypesDisabled(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return <String>[];
  }
}
