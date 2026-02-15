// ── DEV NOTE ──────────────────────────────────────────────────────
// New service: Handles linking anonymous identities to registered accounts.
//
// Strategy:
//   Supabase supports upgrading an anonymous user to an email/password
//   user via `updateUser(email, password)`. When this works, no data
//   migration is needed because the user_id stays the same.
//
//   However, if the user already has a *different* existing account
//   and logs in instead of upgrading, the old anon user_id is abandoned.
//   In that case, we call the RPC `migrate_anon_user_data(old_uid, new_uid)`
//   to move all data references.
//
// Created as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for linking anonymous sessions to registered identities.
///
/// Usage:
///   - Call [saveAnonUid] whenever an anonymous session is created.
///   - Call [migrateIfNeeded] after a successful sign-up or login when the
///     active session is no longer anonymous.
///
/// Safety guarantees:
///   - Migration only runs when `savedAnonUid != null` **and**
///     `current user_id != savedAnonUid` **and** the saved session was
///     genuinely anonymous (`_prefKeyWasAnon` flag is `true`).
///   - Server-side: the RPC additionally verifies `p_old_uid` is anon
///     (auth.users.is_anonymous = true OR email IS NULL).
class IdentityLinkService {
  static const _prefKey = 'cs_anon_uid';
  static const _prefKeyWasAnon = 'cs_anon_uid_was_anon';
  static final _supabase = Supabase.instance.client;

  /// Persist the current anonymous user_id so we can migrate later.
  ///
  /// Also stores a boolean flag confirming the user was anonymous
  /// (email == null) at the time of saving.
  static Future<void> saveAnonUid() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    if (user.isAnonymous != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, user.id);
    // Record that the user was genuinely anonymous (no email)
    await prefs.setBool(_prefKeyWasAnon, user.email == null);
    debugPrint('IdentityLinkService: saved anon uid=${user.id}');
  }

  /// If there was a previous anonymous session, migrate its data
  /// to the current (newly registered/logged-in) user.
  ///
  /// Returns `true` if a migration was performed.
  ///
  /// Conditions for migration to run:
  ///   a) savedAnonUid != null
  ///   b) current user_id != savedAnonUid (different user → login, not upgrade)
  ///   c) the saved user was anon (email == null at time of save)
  static Future<bool> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final oldUid = prefs.getString(_prefKey);
    if (oldUid == null) return false;

    final newUser = _supabase.auth.currentUser;
    if (newUser == null) return false;
    if (newUser.isAnonymous == true) return false; // still anon, skip

    if (newUser.id == oldUid) {
      // Same user (upgraded in-place via updateUser), no migration needed
      debugPrint('IdentityLinkService: same user_id after upgrade, no migration');
      await _clearPrefs(prefs);
      return false;
    }

    // ── Safety check: was the saved session genuinely anonymous? ──
    final wasAnon = prefs.getBool(_prefKeyWasAnon) ?? false;
    if (!wasAnon) {
      debugPrint(
        'IdentityLinkService: saved UID was not anon (wasAnon=$wasAnon), '
        'skipping migration',
      );
      await _clearPrefs(prefs);
      return false;
    }

    debugPrint(
      'IdentityLinkService: migrating data from $oldUid → ${newUser.id}',
    );

    try {
      final result = await _supabase.rpc(
        'migrate_anon_user_data',
        params: {
          'p_old_uid': oldUid,
          'p_new_uid': newUser.id,
        },
      );
      debugPrint('IdentityLinkService: migration result=$result');

      // Clean up
      await _clearPrefs(prefs);
      return true;
    } catch (e) {
      debugPrint('IdentityLinkService: migration failed: $e');
      // Don't remove the key — we'll retry next time
      return false;
    }
  }

  /// Clear any saved anon UID (e.g. on explicit sign-out or after migration).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPrefs(prefs);
  }

  static Future<void> _clearPrefs(SharedPreferences prefs) async {
    await prefs.remove(_prefKey);
    await prefs.remove(_prefKeyWasAnon);
  }
}
