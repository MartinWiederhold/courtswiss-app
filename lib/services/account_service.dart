import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles account-level operations such as permanent account deletion.
class AccountService {
  static final _supabase = Supabase.instance.client;

  /// Calls the `cs_delete_account` RPC which:
  ///   1. Deletes all user data across every cs_* table
  ///   2. Deletes the auth.users row
  ///
  /// After the RPC succeeds the local session is signed out and all
  /// SharedPreferences are cleared.
  ///
  /// Throws on any failure so the caller can show an error toast.
  static Future<void> deleteAccount() async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('DELETE_ACCOUNT: starting for uid=$uid');

    try {
      // 1. Call the SECURITY DEFINER RPC (bypasses RLS, deletes auth user).
      await _supabase.rpc('cs_delete_account');
      debugPrint('DELETE_ACCOUNT: RPC succeeded');
    } on PostgrestException catch (e) {
      debugPrint('DELETE_ACCOUNT PostgrestException: '
          'code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}');
      rethrow;
    } on AuthException catch (e) {
      debugPrint('DELETE_ACCOUNT AuthException: '
          'statusCode=${e.statusCode} message=${e.message}');
      rethrow;
    } catch (e, st) {
      debugPrint('DELETE_ACCOUNT unexpected error: $e\n$st');
      rethrow;
    }

    // 2. Sign out locally (session is already invalid server-side).
    try {
      await _supabase.auth.signOut();
      debugPrint('DELETE_ACCOUNT: signed out');
    } catch (e) {
      // Best-effort – user is already gone server-side.
      debugPrint('DELETE_ACCOUNT: signOut after delete failed (ok): $e');
    }

    // 3. Clear all SharedPreferences (locale, push prefs, etc.)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('DELETE_ACCOUNT: prefs cleared');
    } catch (e) {
      debugPrint('DELETE_ACCOUNT: prefs.clear failed (ok): $e');
    }
  }
}
