import 'package:flutter/foundation.dart';

/// Model for a dinner RSVP (cs_dinner_rsvps).
class DinnerRsvp {
  final String id;
  final String matchId;
  final String userId;
  final String status; // 'yes' | 'no' | 'maybe'
  final String? note;
  final DateTime updatedAt;
  final DateTime createdAt;

  DinnerRsvp({
    required this.id,
    required this.matchId,
    required this.userId,
    required this.status,
    this.note,
    required this.updatedAt,
    required this.createdAt,
  });

  /// Parse a Supabase row into a [DinnerRsvp].
  factory DinnerRsvp.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final matchId = map['match_id'];
    final userId = map['user_id'];
    final status = map['status'];

    final missing = <String>[];
    if (id == null) missing.add('id');
    if (matchId == null) missing.add('match_id');
    if (userId == null) missing.add('user_id');
    if (status == null) missing.add('status');

    if (missing.isNotEmpty) {
      debugPrint(
        'DinnerRsvp.fromMap: NULL in required fields $missing. '
        'Row keys: ${map.keys.toList()}',
      );
      throw FormatException('Unvollständige Daten: $missing');
    }

    DateTime updatedAt;
    final uRaw = map['updated_at'];
    if (uRaw is String && uRaw.isNotEmpty) {
      updatedAt = DateTime.tryParse(uRaw) ?? DateTime.now();
    } else {
      updatedAt = DateTime.now();
    }

    DateTime createdAt;
    final cRaw = map['created_at'];
    if (cRaw is String && cRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(cRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    return DinnerRsvp(
      id: id.toString(),
      matchId: matchId.toString(),
      userId: userId.toString(),
      status: status.toString(),
      note: map['note'] as String?,
      updatedAt: updatedAt,
      createdAt: createdAt,
    );
  }

  /// Emoji label for the status.
  String get statusEmoji {
    switch (status) {
      case 'yes':
        return '✅';
      case 'no':
        return '❌';
      case 'maybe':
        return '❓';
      default:
        return '–';
    }
  }

  /// German label for the status.
  String get statusLabel {
    switch (status) {
      case 'yes':
        return 'Zugesagt';
      case 'no':
        return 'Abgesagt';
      case 'maybe':
        return 'Unsicher';
      default:
        return 'Keine Antwort';
    }
  }
}
