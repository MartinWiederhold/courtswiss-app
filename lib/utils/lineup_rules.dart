// Pure utility functions for detecting lineup rule violations.
// No Flutter/Supabase dependencies – unit-testable with plain Dart.
import '../models/ranking_data.dart';

/// A single detected rule violation.
class LineupViolation {
  /// Machine-readable code for programmatic handling.
  final LineupViolationCode code;

  /// Human-readable message (German, ready for UI display).
  final String message;

  /// Optional metadata for further context.
  final String? slotId;
  final String? userId;

  const LineupViolation({
    required this.code,
    required this.message,
    this.slotId,
    this.userId,
  });

  @override
  String toString() => 'LineupViolation($code: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineupViolation &&
          code == other.code &&
          message == other.message &&
          slotId == other.slotId &&
          userId == other.userId;

  @override
  int get hashCode => Object.hash(code, message, slotId, userId);
}

/// Enumeration of violation codes.
enum LineupViolationCode {
  /// A starter slot has no assigned player.
  missingStarter,

  /// The same player appears in multiple slots.
  duplicatePlayer,

  /// Starter ranking order is violated (better-ranked player behind weaker).
  rankingOrder,
}

/// Detect all lineup rule violations for the given [slots].
///
/// [slots] is the ordered list of lineup slot maps as returned by
/// `LineupService.getSlots` / `LineupService.buildOrderedSlots`.
///
/// Each map is expected to contain at least:
///   - `id` (String)
///   - `slot_type` ('starter' | 'reserve')
///   - `position` (int)
///   - `user_id` (String?) – null if slot is unassigned
///   - `cs_team_players` (Map?) – optional embedded player data with `ranking`
///
/// Returns an empty list when no violations are found.
List<LineupViolation> detectLineupViolations(List<Map<String, dynamic>> slots) {
  final violations = <LineupViolation>[];

  // ── A) Missing starter ──────────────────────────────────────
  _checkMissingStarters(slots, violations);

  // ── B) Duplicate player ─────────────────────────────────────
  _checkDuplicatePlayers(slots, violations);

  // ── C) Ranking order ────────────────────────────────────────
  _checkRankingOrder(slots, violations);

  return violations;
}

// ─────────────────────────────────────────────────────────────────
//  Internal checkers
// ─────────────────────────────────────────────────────────────────

/// WARN when a starter slot has no player assigned.
void _checkMissingStarters(
  List<Map<String, dynamic>> slots,
  List<LineupViolation> out,
) {
  for (final slot in slots) {
    if (slot['slot_type'] != 'starter') continue;
    final userId = slot['user_id'];
    if (userId == null || (userId is String && userId.isEmpty)) {
      final pos = slot['position'] as int;
      out.add(
        LineupViolation(
          code: LineupViolationCode.missingStarter,
          message: 'Starter Position $pos hat keinen Spieler.',
          slotId: slot['id'] as String?,
        ),
      );
    }
  }
}

/// WARN when the same user_id appears in multiple slots.
void _checkDuplicatePlayers(
  List<Map<String, dynamic>> slots,
  List<LineupViolation> out,
) {
  final seen = <String, String>{}; // user_id → first slot id
  for (final slot in slots) {
    final userId = slot['user_id'] as String?;
    if (userId == null || userId.isEmpty) continue;

    if (seen.containsKey(userId)) {
      out.add(
        LineupViolation(
          code: LineupViolationCode.duplicatePlayer,
          message: 'Spieler ist mehrfach in der Aufstellung.',
          slotId: slot['id'] as String?,
          userId: userId,
        ),
      );
    } else {
      seen[userId] = slot['id'] as String? ?? '';
    }
  }
}

/// WARN when starter ranking order is violated.
///
/// "Ranking" is an integer from `cs_team_players.ranking` (lower = better).
/// Position 1 should have the best (lowest) ranking, position 2 the next, etc.
///
/// If ANY starter has no ranking data available, we skip the entire check
/// (graceful degradation — don't warn when data is incomplete).
void _checkRankingOrder(
  List<Map<String, dynamic>> slots,
  List<LineupViolation> out,
) {
  // Collect starters sorted by their position.
  final starters = slots.where((s) => s['slot_type'] == 'starter').toList()
    ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

  if (starters.length < 2) return;

  // Extract rankings; bail if any starter lacks ranking data.
  final rankings = <int>[];
  for (final s in starters) {
    final rank = _extractRanking(s);
    if (rank == null) return; // incomplete data → skip check
    rankings.add(rank);
  }

  // Check that rankings are non-decreasing (lower = better = earlier).
  for (int i = 1; i < rankings.length; i++) {
    if (rankings[i] < rankings[i - 1]) {
      final pos = starters[i]['position'] as int;
      final prevPos = starters[i - 1]['position'] as int;
      out.add(
        LineupViolation(
          code: LineupViolationCode.rankingOrder,
          message:
              'Ranking-Reihenfolge verletzt: '
              'Position $pos (${RankingData.label(rankings[i])}) ist stärker als '
              'Position $prevPos (${RankingData.label(rankings[i - 1])}).',
          slotId: starters[i]['id'] as String?,
        ),
      );
    }
  }
}

/// Extract the integer ranking from a slot's embedded `cs_team_players`.
/// Returns `null` if no ranking data is available.
int? _extractRanking(Map<String, dynamic> slot) {
  final player = slot['cs_team_players'];
  if (player is Map<String, dynamic>) {
    final r = player['ranking'];
    if (r is int) return r;
    if (r is num) return r.toInt();
  }
  return null;
}
