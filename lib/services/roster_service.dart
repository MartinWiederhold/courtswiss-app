import 'package:supabase_flutter/supabase_flutter.dart';

class RosterService {
  static final _supabase = Supabase.instance.client;

  /// Generate roster for a match (admin only, via RPC).
  static Future<Map<String, dynamic>> generateRoster(String matchId) async {
    final result = await _supabase.rpc(
      'generate_match_roster',
      params: {'p_match_id': matchId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Load roster rows for a match, ordered by role then position.
  static Future<List<Map<String, dynamic>>> getRoster(String matchId) async {
    final rows = await _supabase
        .from('cs_match_roster')
        .select('match_id, user_id, role, position, status, updated_at')
        .eq('match_id', matchId)
        .order('position', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Set current user's roster status (confirm / decline) via RPC.
  /// If declining as starter → RPC auto-promotes first substitute.
  static Future<Map<String, dynamic>> setMyStatus(
      String matchId, String status) async {
    final result = await _supabase.rpc(
      'set_roster_status',
      params: {'p_match_id': matchId, 'p_status': status},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Load match settings (starter count, sub count, include maybe).
  static Future<Map<String, dynamic>?> getSettings(String matchId) async {
    final rows = await _supabase
        .from('cs_match_settings')
        .select()
        .eq('match_id', matchId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// Save/upsert match settings.
  static Future<void> upsertSettings({
    required String matchId,
    required int starterCount,
    required int substituteCount,
    required bool includeMaybe,
  }) async {
    await _supabase.from('cs_match_settings').upsert({
      'match_id': matchId,
      'starter_count': starterCount,
      'substitute_count': substituteCount,
      'include_maybe': includeMaybe,
    });
  }
}
