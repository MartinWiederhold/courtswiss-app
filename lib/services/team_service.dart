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

  static Future<void> createTeam({
    required String name,
    String? clubName,
    String? league,
    required int seasonYear,
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
    };

    // Debug: im Console-Log sichtbar
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
      await _supabase.from('cs_team_members').upsert(
        {
          'team_id': teamId,
          'user_id': user.id,
          'role': 'captain',
        },
        onConflict: 'team_id,user_id',
      );
      // ignore: avoid_print
      print('createTeam captain member inserted/upserted OK');
    } catch (e) {
      // ignore: avoid_print
      print('createTeam member insert FAILED: $e');
      // Re-throw mit Kontext, damit der UI-Layer den Fehler anzeigen kann
      throw Exception(
        'Team erstellt (id=$teamId), aber Captain-Eintrag fehlgeschlagen: $e',
      );
    }
  }
}
