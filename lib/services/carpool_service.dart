import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/carpool_offer.dart';

/// Service for the carpool system (cs_carpool_offers + cs_carpool_passengers).
///
/// Flow:
///   1. Driver creates/updates offer via [upsertOffer] (RPC)
///   2. Passengers join via [join] / leave via [leave] (RPCs)
///   3. UI fetches via [listOffers] and listens via Realtime channels
class CarpoolService {
  static final _supabase = Supabase.instance.client;

  // ── RPCs ──────────────────────────────────────────────────

  /// Create or update a carpool offer.
  ///
  /// Returns the offer id on success.
  /// Throws if the RPC fails or returns no valid id.
  static Future<String> upsertOffer({
    required String teamId,
    required String matchId,
    required int seatsTotal,
    String? startLocation,
    String? note,
    DateTime? departAt,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint(
      'CARPOOL_CREATE: uid=$uid matchId=$matchId teamId=$teamId '
      'seats=$seatsTotal location=$startLocation',
    );

    if (uid == null) {
      throw Exception('Nicht eingeloggt – bitte App neu starten.');
    }

    final result = await _supabase.rpc(
      'cs_upsert_carpool_offer',
      params: {
        'p_team_id': teamId,
        'p_match_id': matchId,
        'p_seats_total': seatsTotal,
        'p_start_location': startLocation,
        'p_note': note,
        'p_depart_at': departAt?.toUtc().toIso8601String(),
      },
    );

    // Validate the RPC returned a usable offer id
    final offerId = result?.toString();
    if (offerId == null || offerId.isEmpty) {
      debugPrint('CARPOOL_CREATE ERROR: RPC returned null/empty: $result');
      throw Exception(
        'Fahrgemeinschaft konnte nicht erstellt werden – '
        'Server hat keine ID zurückgegeben. '
        'Mögliche Ursache: RLS-Policy oder fehlende Berechtigung.',
      );
    }

    debugPrint('CARPOOL_CREATE: success, offerId=$offerId');
    return offerId;
  }

  /// Join a carpool offer as passenger.
  static Future<void> join(String offerId) async {
    debugPrint(
      'CARPOOL_JOIN: offerId=$offerId uid=${_supabase.auth.currentUser?.id}',
    );
    await _supabase.rpc('cs_join_carpool', params: {'p_offer_id': offerId});
    debugPrint('CARPOOL_JOIN: success');
  }

  /// Leave a carpool offer.
  static Future<void> leave(String offerId) async {
    debugPrint(
      'CARPOOL_LEAVE: offerId=$offerId uid=${_supabase.auth.currentUser?.id}',
    );
    await _supabase.rpc('cs_leave_carpool', params: {'p_offer_id': offerId});
    debugPrint('CARPOOL_LEAVE: success');
  }

  // ── Queries ───────────────────────────────────────────────

  /// Fetch all offers for a match (one-shot).
  ///
  /// Returns raw rows including embedded passengers.
  /// Throws on query error (does NOT catch internally).
  static Future<List<Map<String, dynamic>>> listOffers(String matchId) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('CARPOOL_QUERY: matchId=$matchId uid=$uid');
    final rows = await _supabase
        .from('cs_carpool_offers')
        .select('*, cs_carpool_passengers(*)')
        .eq('match_id', matchId)
        .order('created_at', ascending: true);
    final result = List<Map<String, dynamic>>.from(rows);
    debugPrint('CARPOOL_QUERY: ${result.length} offers returned');
    return result;
  }

  // ── Model helpers ─────────────────────────────────────────

  /// Parse raw offer maps into [CarpoolOffer] models.
  /// Resolves driver names from the provided claimed-player map and profiles.
  ///
  /// Rows that fail to parse are skipped (logged, not thrown).
  static List<CarpoolOffer> parseOffers(
    List<Map<String, dynamic>> rows, {
    Map<String, Map<String, dynamic>> claimedMap = const {},
    Map<String, Map<String, dynamic>> profiles = const {},
  }) {
    final offers = <CarpoolOffer>[];
    for (final row in rows) {
      try {
        final driverId = row['driver_user_id']?.toString() ?? '';
        final driverName = _resolveUserName(driverId, claimedMap, profiles);
        offers.add(CarpoolOffer.fromMap(row, driverName: driverName));
      } catch (e) {
        debugPrint('CARPOOL_PARSE ERROR: $e — row keys: ${row.keys.toList()}');
      }
    }
    return offers;
  }

  /// Resolve a user_id to a display name.
  static String _resolveUserName(
    String userId,
    Map<String, Map<String, dynamic>> claimedMap,
    Map<String, Map<String, dynamic>> profiles,
  ) {
    // 1. Try claimed player slot
    final claimed = claimedMap[userId];
    if (claimed != null) {
      final first = claimed['first_name'] as String? ?? '';
      final last = claimed['last_name'] as String? ?? '';
      final name = '$first $last'.trim();
      if (name.isNotEmpty) return name;
    }
    // 2. Try profile
    final profile = profiles[userId];
    if (profile != null) {
      final nick =
          profile['display_name'] as String? ?? profile['nickname'] as String?;
      if (nick != null && nick.isNotEmpty) return nick;
    }
    // 3. Fallback
    return userId.length > 8 ? '${userId.substring(0, 8)}…' : userId;
  }

  /// Delete a carpool offer (driver only).
  static Future<void> deleteOffer(String offerId) async {
    debugPrint(
      'CARPOOL_DELETE: offerId=$offerId uid=${_supabase.auth.currentUser?.id}',
    );
    await _supabase.from('cs_carpool_offers').delete().eq('id', offerId);
    debugPrint('CARPOOL_DELETE: success');
  }
}
