import 'package:supabase_flutter/supabase_flutter.dart';

class MatchService {
  static final _supabase = Supabase.instance.client;

  /// Lists all matches across ALL teams the current user belongs to.
  ///
  /// Each returned row includes the original match columns plus a joined
  /// `team_name` field resolved from `cs_teams.name`.
  /// Results are ordered by `match_at` ascending (next game first).
  static Future<List<Map<String, dynamic>>> listAllMyMatches() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    // 1. Fetch team IDs the user belongs to
    final memberships = await _supabase
        .from('cs_team_members')
        .select('team_id')
        .eq('user_id', user.id);

    final teamIds =
        (memberships as List).map((m) => m['team_id'] as String).toList();
    if (teamIds.isEmpty) return [];

    // 2. Fetch matches for those teams, joined with team name
    final rows = await _supabase
        .from('cs_matches')
        .select('*, cs_teams!inner(name)')
        .inFilter('team_id', teamIds)
        .order('match_at', ascending: true);

    // Flatten the joined team name into each row for easy access
    return List<Map<String, dynamic>>.from(rows).map((row) {
      final team = row['cs_teams'];
      final teamName =
          (team is Map<String, dynamic>) ? team['name'] as String? : null;
      return {...row, 'team_name': teamName ?? '–'};
    }).toList();
  }

  /// Lists all matches for a team, ordered by date ascending.
  static Future<List<Map<String, dynamic>>> listMatches(String teamId) async {
    final rows = await _supabase
        .from('cs_matches')
        .select()
        .eq('team_id', teamId)
        .order('match_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Creates a new match. Only team admins (captain/creator) may call this.
  static Future<void> createMatch({
    required String teamId,
    required String opponent,
    required DateTime matchAt,
    required bool isHome,
    String? location,
    String? note,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    await _supabase.from('cs_matches').insert({
      'team_id': teamId,
      'opponent': opponent,
      'match_at': matchAt.toUtc().toIso8601String(),
      'is_home': isHome,
      'location': location,
      'note': note,
      'created_by': uid,
    });
  }

  /// Loads all availability rows for a single match.
  static Future<List<Map<String, dynamic>>> listAvailability(
    String matchId,
  ) async {
    final rows = await _supabase
        .from('cs_match_availability')
        .select()
        .eq('match_id', matchId);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Loads availability rows for multiple matches in one call.
  static Future<List<Map<String, dynamic>>> listAvailabilityBatch(
    List<String> matchIds,
  ) async {
    if (matchIds.isEmpty) return [];
    final rows = await _supabase
        .from('cs_match_availability')
        .select('match_id, user_id, status')
        .inFilter('match_id', matchIds);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Updates an existing match (only admins via RLS).
  static Future<void> updateMatch(
    String matchId,
    Map<String, dynamic> patch,
  ) async {
    await _supabase.from('cs_matches').update(patch).eq('id', matchId);
  }

  /// Deletes a match (only admins via RLS). Cascades to availability.
  static Future<void> deleteMatch(String matchId) async {
    await _supabase.from('cs_matches').delete().eq('id', matchId);
  }

  /// Sets (upserts) the current user's availability for a match.
  static Future<void> setAvailability({
    required String matchId,
    required String status,
    String? comment,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    // ignore: avoid_print
    print('SET_AVAILABILITY userId=$uid matchId=$matchId status=$status');

    await _supabase.from('cs_match_availability').upsert({
      'match_id': matchId,
      'user_id': uid,
      'status': status,
      'comment': comment,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'match_id,user_id');
  }
}
