import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ranking_data.dart';

/// Service for managing pre-created player slots (cs_team_players).
/// Captain creates slots with name + ranking, players claim them after joining.
class TeamPlayerService {
  static final _supabase = Supabase.instance.client;

  /// List all player slots for a team, ordered by ranking.
  static Future<List<Map<String, dynamic>>> listPlayers(String teamId) async {
    final rows = await _supabase
        .from('cs_team_players')
        .select()
        .eq('team_id', teamId)
        .order('ranking', ascending: true, nullsFirst: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// List only unclaimed player slots for a team.
  static Future<List<Map<String, dynamic>>> listUnclaimedPlayers(
    String teamId,
  ) async {
    final rows = await _supabase
        .from('cs_team_players')
        .select()
        .eq('team_id', teamId)
        .isFilter('claimed_by', null)
        .order('ranking', ascending: true, nullsFirst: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Check whether the current user has already claimed a slot in this team.
  static Future<Map<String, dynamic>?> getMyClaimedPlayer(String teamId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    final rows = await _supabase
        .from('cs_team_players')
        .select()
        .eq('team_id', teamId)
        .eq('claimed_by', uid)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  /// Quick check: does this team have any unclaimed player slots?
  static Future<bool> hasUnclaimedPlayers(String teamId) async {
    final rows = await _supabase
        .from('cs_team_players')
        .select('id')
        .eq('team_id', teamId)
        .isFilter('claimed_by', null)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Quick check: does this team have any player slots at all?
  static Future<bool> hasPlayerSlots(String teamId) async {
    final rows = await _supabase
        .from('cs_team_players')
        .select('id')
        .eq('team_id', teamId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Create a new player slot (admin only, via RPC).
  static Future<String> createPlayer({
    required String teamId,
    required String firstName,
    required String lastName,
    int? ranking,
  }) async {
    final result = await _supabase.rpc(
      'create_team_player',
      params: {
        'p_team_id': teamId,
        'p_first_name': firstName,
        'p_last_name': lastName,
        'p_ranking': ranking,
      },
    );
    return result as String; // returns player id
  }

  /// Claim a player slot (via RPC, atomic).
  static Future<Map<String, dynamic>> claimPlayer({
    required String teamId,
    required String playerId,
  }) async {
    final result = await _supabase.rpc(
      'claim_team_player',
      params: {'p_team_id': teamId, 'p_player_id': playerId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Unclaim a player slot (admin only, via RPC).
  static Future<void> unclaimPlayer({
    required String teamId,
    required String playerId,
  }) async {
    await _supabase.rpc(
      'unclaim_team_player',
      params: {'p_team_id': teamId, 'p_player_id': playerId},
    );
  }

  /// Delete a player slot (admin only).
  static Future<void> deletePlayer(String playerId) async {
    await _supabase.from('cs_team_players').delete().eq('id', playerId);
  }

  /// Captain creates / updates their own player slot (auto-claimed).
  /// RPC looks up the captain's name from nickname / profile.
  /// [ranking] is optional – pass `null` to leave ranking empty.
  static Future<Map<String, dynamic>> upsertCaptainSlot({
    required String teamId,
    int? ranking,
  }) async {
    final result = await _supabase.rpc(
      'upsert_captain_player_slot',
      params: {'p_team_id': teamId, 'p_ranking': ranking},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Captain removes their own player slot + sets is_playing = false.
  static Future<void> removeCaptainSlot({required String teamId}) async {
    await _supabase.rpc(
      'remove_captain_player_slot',
      params: {'p_team_id': teamId},
    );
  }

  /// Build a lookup map: user_id → player slot data (for claimed players).
  /// Useful for name/ranking resolution across UI.
  static Map<String, Map<String, dynamic>> buildClaimedMap(
    List<Map<String, dynamic>> players,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final p in players) {
      final claimedBy = p['claimed_by'] as String?;
      if (claimedBy != null) {
        map[claimedBy] = p;
      }
    }
    return map;
  }

  /// Get display name from a player slot: "First Last"
  static String playerDisplayName(Map<String, dynamic> player) {
    final first = player['first_name'] as String? ?? '';
    final last = player['last_name'] as String? ?? '';
    return '$first $last'.trim();
  }

  /// Get ranking label (e.g. "R7", "N3", "LK 12") or "".
  static String rankingLabel(Map<String, dynamic> player) {
    final ranking = player['ranking'];
    if (ranking == null) return '';
    final intVal = ranking is int ? ranking : (ranking as num).toInt();
    return RankingData.label(intVal);
  }
}
