import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamService {
  static final _supabase = Supabase.instance.client;

  /// Fires whenever a team is deleted (or otherwise structurally changed).
  /// Other screens (e.g. SpieleOverviewScreen) can listen to this to
  /// know when they should reload their data.
  static final ValueNotifier<int> teamChangeNotifier = ValueNotifier<int>(0);

  /// Lists all teams the current user belongs to.
  ///
  /// Each returned map includes all team columns plus:
  ///   - `my_role`: the user's role in this team (`captain` or `member`).
  ///
  /// Results are ordered by `created_at` descending (newest first).
  static Future<List<Map<String, dynamic>>> listMyTeams() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final memberships = await _supabase
        .from('cs_team_members')
        .select('team_id, role')
        .eq('user_id', user.id);

    final memberList = List<Map<String, dynamic>>.from(memberships as List);
    final teamIds = memberList.map((m) => m['team_id'] as String).toList();
    if (teamIds.isEmpty) return [];

    // Build role lookup: teamId → role
    final roleMap = <String, String>{};
    for (final m in memberList) {
      roleMap[m['team_id'] as String] = (m['role'] as String?) ?? 'member';
    }

    final teams = await _supabase
        .from('cs_teams')
        .select()
        .inFilter('id', teamIds)
        .order('created_at', ascending: false);

    final uid = user.id;
    return (teams as List).cast<Map<String, dynamic>>().map((t) {
      final teamId = t['id'] as String;
      final createdBy = t['created_by'] as String?;
      final role = roleMap[teamId] ?? 'member';
      // "Eigene Teams" if captain OR creator; else "Geteilte Teams"
      final isOwner = role == 'captain' || createdBy == uid;
      return {...t, 'my_role': role, 'is_owner': isOwner};
    }).toList();
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

      await _supabase
          .from('cs_team_members')
          .upsert(memberPayload, onConflict: 'team_id,user_id');
      // ignore: avoid_print
      print(
        'createTeam captain member inserted/upserted OK '
        '(is_playing=false, nickname=${captainNickname ?? "null"})',
      );
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
      // Notify listeners (e.g. SpieleOverviewScreen) to refresh
      teamChangeNotifier.value++;
    } catch (e) {
      // ignore: avoid_print
      print('TEAM_DELETE error teamId=$teamId err=$e');
      rethrow;
    }
  }

  /// Leave a team by deleting the current user's membership row.
  /// The team itself is NOT deleted – it stays for the captain and
  /// other members. Only the caller's own `cs_team_members` row is removed.
  static Future<void> leaveTeam(String teamId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not logged in (currentUser is null)');
    }

    // ignore: avoid_print
    print('TEAM_LEAVE teamId=$teamId userId=${user.id}');

    try {
      await _supabase
          .from('cs_team_members')
          .delete()
          .eq('team_id', teamId)
          .eq('user_id', user.id);
      // ignore: avoid_print
      print('TEAM_LEAVE success teamId=$teamId');
      // Notify listeners (e.g. SpieleOverviewScreen) to refresh
      teamChangeNotifier.value++;
    } catch (e) {
      // ignore: avoid_print
      print('TEAM_LEAVE error teamId=$teamId err=$e');
      rethrow;
    }
  }
}
