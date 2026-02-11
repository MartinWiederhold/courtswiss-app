import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for the lineup system (cs_match_lineups + cs_match_lineup_slots).
///
/// Key design rule: generate_lineup creates a DRAFT only (no notifications).
/// Captain can manually reorder via move/set.  Only publish_lineup sends
/// notifications to the team.
///
/// After publish, when a starter sets availability to 'no', a DB trigger
/// calls auto_handle_absence which promotes the best reserve automatically
/// and creates targeted notifications.
class LineupService {
  static final _supabase = Supabase.instance.client;

  // ── Generate (DRAFT only, NO notifications) ────────────────

  /// Generate a draft lineup for a match (admin only, via RPC).
  /// Existing lineup is overwritten.
  static Future<Map<String, dynamic>> generateLineup({
    required String matchId,
    int starters = 6,
    int reserves = 3,
    bool includeMaybe = false,
  }) async {
    final result = await _supabase.rpc('generate_lineup', params: {
      'p_match_id': matchId,
      'p_starters': starters,
      'p_reserves': reserves,
      'p_include_maybe': includeMaybe,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Read ───────────────────────────────────────────────────

  /// Load the lineup master record.
  static Future<Map<String, dynamic>?> getLineup(String matchId) async {
    final rows = await _supabase
        .from('cs_match_lineups')
        .select()
        .eq('match_id', matchId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// Load all lineup slots with embedded player-slot data.
  /// Now also returns the `locked` flag.
  static Future<List<Map<String, dynamic>>> getSlots(String matchId) async {
    try {
      final rows = await _supabase
          .from('cs_match_lineup_slots')
          .select(
              'id, match_id, slot_type, position, player_slot_id, user_id, locked, '
              'cs_team_players(first_name, last_name, ranking)')
          .eq('match_id', matchId)
          .order('position', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      // Fallback without FK embed
      final rows = await _supabase
          .from('cs_match_lineup_slots')
          .select()
          .eq('match_id', matchId)
          .order('position', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    }
  }

  /// Load lineup event log for a match (audit trail).
  static Future<List<Map<String, dynamic>>> getEvents(String matchId) async {
    try {
      final rows = await _supabase
          .from('cs_lineup_events')
          .select()
          .eq('match_id', matchId)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  // ── Manual reorder (captain only) ──────────────────────────

  /// Swap / move two slots in the lineup (via RPC, atomic).
  /// Works within the same type and across starter↔reserve boundary.
  static Future<Map<String, dynamic>> moveSlot({
    required String matchId,
    required String fromType,
    required int fromPos,
    required String toType,
    required int toPos,
  }) async {
    final result = await _supabase.rpc('move_lineup_slot', params: {
      'p_match_id': matchId,
      'p_from_type': fromType,
      'p_from_pos': fromPos,
      'p_to_type': toType,
      'p_to_pos': toPos,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Replace / swap a player at a specific slot position (via RPC).
  static Future<Map<String, dynamic>> setSlot({
    required String matchId,
    required String slotType,
    required int position,
    required String playerSlotId,
  }) async {
    final result = await _supabase.rpc('set_lineup_slot', params: {
      'p_match_id': matchId,
      'p_slot_type': slotType,
      'p_position': position,
      'p_player_slot_id': playerSlotId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Lock / Unlock slot (captain only) ──────────────────────

  /// Toggle the `locked` flag on a lineup slot.
  /// Locked slots are skipped by auto-promotion (neither source nor candidate).
  static Future<void> toggleSlotLock({
    required String slotId,
    required bool locked,
  }) async {
    await _supabase
        .from('cs_match_lineup_slots')
        .update({'locked': locked})
        .eq('id', slotId);
  }

  // ── Publish (sends notifications to team) ──────────────────

  /// Publish the lineup and notify all team members (via RPC).
  static Future<Map<String, dynamic>> publishLineup(String matchId) async {
    final result = await _supabase.rpc('publish_lineup', params: {
      'p_match_id': matchId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Manual auto-promotion trigger (captain debug) ──────────

  /// Manually trigger auto-promotion for a specific absent user.
  /// Usually the DB trigger handles this automatically when availability
  /// changes to 'no', but captains can also trigger it explicitly.
  static Future<Map<String, dynamic>> triggerAutoPromotion({
    required String matchId,
    required String absentUserId,
  }) async {
    final result = await _supabase.rpc('auto_handle_absence', params: {
      'p_match_id': matchId,
      'p_absent_user_id': absentUserId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Display helpers ────────────────────────────────────────

  /// Build a unified ordered list: starters first, then reserves,
  /// each sorted by position ASC.  Returns the combined list.
  static List<Map<String, dynamic>> buildOrderedSlots(
      List<Map<String, dynamic>> slots) {
    final starters = slots.where((s) => s['slot_type'] == 'starter').toList()
      ..sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int));
    final reserves = slots.where((s) => s['slot_type'] == 'reserve').toList()
      ..sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return [...starters, ...reserves];
  }

  /// Display name from embedded cs_team_players or '?'.
  static String slotDisplayName(Map<String, dynamic> slot) {
    final player = slot['cs_team_players'];
    if (player is Map<String, dynamic>) {
      final first = player['first_name'] as String? ?? '';
      final last = player['last_name'] as String? ?? '';
      return '$first $last'.trim();
    }
    return '?';
  }

  /// Ranking label from embedded cs_team_players.
  static String slotRanking(Map<String, dynamic> slot) {
    final player = slot['cs_team_players'];
    if (player is Map<String, dynamic>) {
      final r = player['ranking'];
      if (r != null) return 'R$r';
    }
    return '';
  }

  /// Full label: "Name · R7".
  static String slotLabel(Map<String, dynamic> slot) {
    final name = slotDisplayName(slot);
    final rank = slotRanking(slot);
    return rank.isNotEmpty ? '$name · $rank' : name;
  }
}
