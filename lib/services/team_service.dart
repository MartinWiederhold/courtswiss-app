import 'package:supabase_flutter/supabase_flutter.dart';

class TeamService {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> listMyTeams() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final memberships = await _supabase
        .from('cs_team_members')
        .select('team_id')
        .eq('user_id', user.id);

    final teamIds = (memberships as List)
        .map((m) => m['team_id'] as String)
        .toList();

    if (teamIds.isEmpty) return [];

    final teams = await _supabase
        .from('cs_teams')
        .select()
        .inFilter('id', teamIds)
        .order('created_at', ascending: false);

    return (teams as List).cast<Map<String, dynamic>>();
  }

  /// Creates a new team and inserts the current user as captain.
  ///
  /// [captainNickname] – optional display name for the captain member row.
  /// The captain is **never** auto-created as a player; set [is_playing]
  /// explicitly via the "Ich spiele selbst" toggle + upsertCaptainSlot.
  ///
  /// Returns the new team's ID.
  static Future<String> createTeam({
    required String name,
    String? clubName,
    String? league,
    required int seasonYear,
    String? sportKey,
    String? captainNickname,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not logged in (currentUser is null)');
    }

    final payload = {
      'name': name,
      'club_name': clubName,
      'league': league,
      'season_year': seasonYear,
      'created_by': user.id,
      if (sportKey != null) 'sport_key': sportKey,
    };

    // ignore: avoid_print
    print('createTeam user.id=${user.id}');
    // ignore: avoid_print
    print('createTeam payload=$payload');

    final inserted = await _supabase
        .from('cs_teams')
        .insert(payload)
        .select()
        .single();

    final teamId = inserted['id'] as String;

    // ignore: avoid_print
    print('createTeam teamId=$teamId, userId=${user.id}');

    try {
      final memberPayload = <String, dynamic>{
        'team_id': teamId,
        'user_id': user.id,
        'role': 'captain',
        'is_playing': false, // Captain is NOT a player by default
      };
      if (captainNickname != null && captainNickname.trim().isNotEmpty) {
        memberPayload['nickname'] = captainNickname.trim();
      }

      await _supabase.from('cs_team_members').upsert(
        memberPayload,
        onConflict: 'team_id,user_id',
      );
      // ignore: avoid_print
      print('createTeam captain member inserted/upserted OK '
          '(is_playing=false, nickname=${captainNickname ?? "null"})');
    } catch (e) {
      // ignore: avoid_print
      print('createTeam member insert FAILED: $e');
      throw Exception(
        'Team erstellt (id=$teamId), aber Captain-Eintrag fehlgeschlagen: $e',
      );
    }

    return teamId;
  }

  /// Delete a team by ID. Only the creator / captain should call this
  /// (RLS enforces the permission on the DB side).
  static Future<void> deleteTeam(String teamId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not logged in (currentUser is null)');
    }

    // ignore: avoid_print
    print('TEAM_DELETE_TAP teamId=$teamId userId=${user.id}');

    try {
      await _supabase.from('cs_teams').delete().eq('id', teamId);
      // ignore: avoid_print
      print('TEAM_DELETE success teamId=$teamId');
    } catch (e) {
      // ignore: avoid_print
      print('TEAM_DELETE error teamId=$teamId err=$e');
      rethrow;
    }
  }
}
