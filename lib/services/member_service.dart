import 'package:supabase_flutter/supabase_flutter.dart';

class MemberService {
  static final _supabase = Supabase.instance.client;

  /// Updates the current user's nickname in a specific team.
  static Future<void> updateMyNickname(String teamId, String nickname) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    await _supabase
        .from('cs_team_members')
        .update({'nickname': nickname})
        .eq('team_id', teamId)
        .eq('user_id', uid);
  }
}
