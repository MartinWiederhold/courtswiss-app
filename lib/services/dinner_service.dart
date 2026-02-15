import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dinner_rsvp.dart';

/// Service for dinner RSVPs (cs_dinner_rsvps).
///
/// Each user can have exactly one RSVP per match (yes / no / maybe + optional note).
class DinnerService {
  static final _supabase = Supabase.instance.client;

  // ── Queries ─────────────────────────────────────────────────

  /// Fetch all dinner RSVPs for a match.
  static Future<List<DinnerRsvp>> getRsvps(String matchId) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('DINNER_LOAD: matchId=$matchId uid=$uid');

    final rows = await _supabase
        .from('cs_dinner_rsvps')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: true);

    final result = <DinnerRsvp>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      try {
        result.add(DinnerRsvp.fromMap(row));
      } catch (e) {
        debugPrint('DINNER_PARSE ERROR: $e — row keys: ${row.keys.toList()}');
      }
    }

    debugPrint('DINNER_LOAD: ${result.length} rsvps returned');
    return result;
  }

  /// Get the current user's RSVP for a match (or null).
  static Future<DinnerRsvp?> getMyRsvp(String matchId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    final rows = await _supabase
        .from('cs_dinner_rsvps')
        .select()
        .eq('match_id', matchId)
        .eq('user_id', uid)
        .limit(1);

    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;

    try {
      return DinnerRsvp.fromMap(list.first);
    } catch (e) {
      debugPrint('DINNER_MY_RSVP PARSE ERROR: $e');
      return null;
    }
  }

  // ── Mutations ───────────────────────────────────────────────

  /// Create or update the current user's RSVP for a match.
  ///
  /// Uses Supabase upsert on the (match_id, user_id) unique constraint.
  static Future<void> upsertRsvp({
    required String matchId,
    required String status,
    String? note,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('DINNER_UPSERT: matchId=$matchId uid=$uid status=$status');

    if (uid == null) {
      throw Exception('Nicht eingeloggt – bitte App neu starten.');
    }

    if (!['yes', 'no', 'maybe'].contains(status)) {
      throw ArgumentError('Ungültiger Status: $status');
    }

    await _supabase.from('cs_dinner_rsvps').upsert({
      'match_id': matchId,
      'user_id': uid,
      'status': status,
      'note': note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'match_id,user_id');

    debugPrint('DINNER_UPSERT: success');
  }
}
