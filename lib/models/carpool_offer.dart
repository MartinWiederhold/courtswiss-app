import 'package:flutter/foundation.dart';

/// Model for a carpool offer (cs_carpool_offers + driver info).
class CarpoolOffer {
  final String id;
  final String matchId;
  final String teamId;
  final String driverUserId;
  final int seatsTotal;
  final String? startLocation;
  final String? note;
  final DateTime? departAt;
  final DateTime createdAt;

  /// Joined passengers
  final List<CarpoolPassenger> passengers;

  /// Resolved driver display name (filled by service).
  final String driverName;

  CarpoolOffer({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.driverUserId,
    required this.seatsTotal,
    this.startLocation,
    this.note,
    this.departAt,
    required this.createdAt,
    this.passengers = const [],
    this.driverName = '?',
  });

  int get seatsTaken => passengers.length;
  int get seatsAvailable => seatsTotal - seatsTaken;
  bool get isFull => seatsAvailable <= 0;

  /// Check whether a specific user is a passenger in this offer.
  bool hasPassenger(String userId) => passengers.any((p) => p.userId == userId);

  /// Parse a Supabase row into a [CarpoolOffer].
  ///
  /// Required fields (id, match_id, team_id, driver_user_id) are validated.
  /// If any required field is null, a [FormatException] is thrown with
  /// diagnostic info (column keys only, no sensitive data).
  factory CarpoolOffer.fromMap(
    Map<String, dynamic> map, {
    String driverName = '?',
  }) {
    // ── Validate required fields ──
    final id = map['id'];
    final matchId = map['match_id'];
    final teamId = map['team_id'];
    final driverUserId = map['driver_user_id'];

    final missing = <String>[];
    if (id == null) missing.add('id');
    if (matchId == null) missing.add('match_id');
    if (teamId == null) missing.add('team_id');
    if (driverUserId == null) missing.add('driver_user_id');

    if (missing.isNotEmpty) {
      debugPrint(
        'CarpoolOffer.fromMap: NULL in required fields $missing. '
        'Row keys: ${map.keys.toList()}, '
        'row snippet: {id: $id, match_id: $matchId, '
        'team_id: $teamId, driver_user_id: $driverUserId}',
      );
      throw FormatException('CarpoolOffer: Pflichtfelder fehlen: $missing');
    }

    // ── Parse passengers (nullable embed) ──
    final passengerList = <CarpoolPassenger>[];
    final rawPassengers = map['cs_carpool_passengers'];
    if (rawPassengers is List) {
      for (final p in rawPassengers) {
        if (p is Map<String, dynamic>) {
          try {
            passengerList.add(CarpoolPassenger.fromMap(p));
          } catch (e) {
            debugPrint('CarpoolPassenger.fromMap skipped: $e');
          }
        }
      }
    }

    // ── Nullable fields: safe parsing ──
    final departAtRaw = map['depart_at'];
    DateTime? departAt;
    if (departAtRaw != null &&
        departAtRaw is String &&
        departAtRaw.isNotEmpty) {
      departAt = DateTime.tryParse(departAtRaw);
    }

    final createdAtRaw = map['created_at'];
    DateTime createdAt;
    if (createdAtRaw is String && createdAtRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    return CarpoolOffer(
      id: id.toString(),
      matchId: matchId.toString(),
      teamId: teamId.toString(),
      driverUserId: driverUserId.toString(),
      seatsTotal: (map['seats_total'] as num?)?.toInt() ?? 4,
      startLocation: map['start_location'] as String?,
      note: map['note'] as String?,
      departAt: departAt,
      createdAt: createdAt,
      passengers: passengerList,
      driverName: driverName,
    );
  }
}

/// Model for a carpool passenger (cs_carpool_passengers).
///
/// DB schema columns: offer_id, passenger_user_id, created_at.
/// Note: The table may NOT have a dedicated `id` column – in that case
/// a synthetic id is built from `offer_id` + `passenger_user_id`.
class CarpoolPassenger {
  final String id;
  final String offerId;
  final String userId;
  final DateTime createdAt;

  CarpoolPassenger({
    required this.id,
    required this.offerId,
    required this.userId,
    required this.createdAt,
  });

  /// Parse a Supabase row into a [CarpoolPassenger].
  ///
  /// Accepts both DB naming conventions:
  ///   - `passenger_user_id` (actual DB column)
  ///   - `user_id` (fallback / legacy)
  /// The `id` column is optional: if absent, a synthetic id is generated.
  factory CarpoolPassenger.fromMap(Map<String, dynamic> map) {
    final offerId = map['offer_id'];

    // Accept both "passenger_user_id" (DB) and "user_id" (legacy/alias)
    final userId = map['passenger_user_id'] ?? map['user_id'];

    // Validate required fields
    final missing = <String>[];
    if (offerId == null) missing.add('offer_id');
    if (userId == null) missing.add('passenger_user_id/user_id');

    if (missing.isNotEmpty) {
      debugPrint(
        'CarpoolPassenger.fromMap: NULL in required fields $missing. '
        'Row keys: ${map.keys.toList()}',
      );
      throw FormatException('CarpoolPassenger: Pflichtfelder fehlen: $missing');
    }

    // id is optional – generate synthetic if absent
    final id =
        map['id']?.toString() ?? '${offerId.toString()}_${userId.toString()}';

    final createdAtRaw = map['created_at'];
    DateTime createdAt;
    if (createdAtRaw is String && createdAtRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    return CarpoolPassenger(
      id: id,
      offerId: offerId.toString(),
      userId: userId.toString(),
      createdAt: createdAt,
    );
  }
}
