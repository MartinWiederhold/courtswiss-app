import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final _supabase = Supabase.instance.client;

  static Future<void> ensureProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final isAnon = user.isAnonymous;

    await _supabase.from('cs_app_profiles').upsert({
      'user_id': user.id,
      'email': user.email, // null for anonymous users
      'display_name': user.email ?? (isAnon ? 'Spieler' : 'Player'),
    });
  }
}
