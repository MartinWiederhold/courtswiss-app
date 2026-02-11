import 'package:supabase_flutter/supabase_flutter.dart';

class InviteService {
  static final _supabase = Supabase.instance.client;

  /// Creates an invite for a team. Returns the token string.
  static Future<String> createInvite(String teamId) async {
    final result = await _supabase.rpc(
      'create_team_invite',
      params: {'p_team_id': teamId},
    );
    return result as String;
  }

  /// Accepts an invite by token.
  /// Returns ({teamId, joined}) – joined=false means user was already a member.
  static Future<({String teamId, bool joined})> acceptInvite(
      String token) async {
    final result = await _supabase.rpc(
      'accept_team_invite',
      params: {'p_token': token},
    );
    final data = result as Map<String, dynamic>;
    return (
      teamId: data['team_id'] as String,
      joined: data['joined'] as bool,
    );
  }

  /// Build the invite deep link (custom scheme)
  static String buildDeepLink(String token) {
    return 'courtswiss://join?token=$token';
  }

  /// Build the universal link placeholder
  static String buildUniversalLink(String token) {
    return 'https://courtswiss.app/join?token=$token';
  }

  /// Build the share text
  static String buildShareText(String token, String teamName) {
    final link = buildDeepLink(token);
    return 'Tritt meinem Interclub-Team "$teamName" bei CourtSwiss bei:\n$link';
  }
}
