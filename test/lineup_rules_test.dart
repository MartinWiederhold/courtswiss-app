import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/utils/lineup_rules.dart';

// ─── Test helpers ────────────────────────────────────────────

/// Build a minimal slot map.
Map<String, dynamic> _slot(
  String id,
  String type,
  int pos, {
  String? userId,
  int? ranking,
}) => {
  'id': id,
  'slot_type': type,
  'position': pos,
  'user_id': userId,
  if (ranking != null)
    'cs_team_players': {'first_name': 'P', 'last_name': id, 'ranking': ranking},
};

/// Shorthand: starter slot with user + ranking.
Map<String, dynamic> _starter(
  String id,
  int pos, {
  String? userId,
  int? ranking,
}) => _slot(id, 'starter', pos, userId: userId, ranking: ranking);

/// Shorthand: reserve slot with user + ranking.
Map<String, dynamic> _reserve(
  String id,
  int pos, {
  String? userId,
  int? ranking,
}) => _slot(id, 'reserve', pos, userId: userId, ranking: ranking);

/// Extract violation codes from result.
List<LineupViolationCode> _codes(List<LineupViolation> vs) =>
    vs.map((v) => v.code).toList();

void main() {
  // ═════════════════════════════════════════════════════════════
  //  No violations
  // ═════════════════════════════════════════════════════════════

  group('no violations', () {
    test('valid lineup: all starters assigned, correct ranking order', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 1),
        _starter('s2', 2, userId: 'u2', ranking: 3),
        _starter('s3', 3, userId: 'u3', ranking: 5),
        _reserve('r1', 1, userId: 'u4', ranking: 7),
      ];

      expect(detectLineupViolations(slots), isEmpty);
    });

    test('empty slots list → no violations', () {
      expect(detectLineupViolations([]), isEmpty);
    });

    test('single starter with user → no violations', () {
      final slots = [_starter('s1', 1, userId: 'u1', ranking: 3)];
      expect(detectLineupViolations(slots), isEmpty);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  Missing starter
  // ═════════════════════════════════════════════════════════════

  group('missingStarter', () {
    test('starter with null userId → violation', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 1),
        _starter('s2', 2, userId: null, ranking: null),
        _reserve('r1', 1, userId: 'u3'),
      ];

      final vs = detectLineupViolations(slots);
      expect(_codes(vs), contains(LineupViolationCode.missingStarter));

      final missing = vs.firstWhere(
        (v) => v.code == LineupViolationCode.missingStarter,
      );
      expect(missing.slotId, 's2');
      expect(missing.message, contains('Position 2'));
    });

    test('multiple missing starters → multiple violations', () {
      final slots = [
        _starter('s1', 1, userId: null),
        _starter('s2', 2, userId: null),
        _reserve('r1', 1, userId: 'u1'),
      ];

      final vs = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.missingStarter).toList();
      expect(vs.length, 2);
    });

    test('reserve with null userId → no missing-starter violation', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 1),
        _reserve('r1', 1, userId: null),
      ];

      final vs = detectLineupViolations(slots);
      final missing = vs
          .where((v) => v.code == LineupViolationCode.missingStarter)
          .toList();
      expect(missing, isEmpty);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  Duplicate player
  // ═════════════════════════════════════════════════════════════

  group('duplicatePlayer', () {
    test('same userId in two slots → violation', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 1),
        _starter('s2', 2, userId: 'u1', ranking: 3), // duplicate
        _reserve('r1', 1, userId: 'u2'),
      ];

      final vs = detectLineupViolations(slots);
      expect(_codes(vs), contains(LineupViolationCode.duplicatePlayer));

      final dup = vs.firstWhere(
        (v) => v.code == LineupViolationCode.duplicatePlayer,
      );
      expect(dup.userId, 'u1');
      expect(dup.slotId, 's2'); // second occurrence flagged
    });

    test('same userId three times → two violations', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 1),
        _starter('s2', 2, userId: 'u1', ranking: 3),
        _starter('s3', 3, userId: 'u1', ranking: 5),
      ];

      final dups = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.duplicatePlayer).toList();
      expect(dups.length, 2);
    });

    test('null userIds are not duplicates', () {
      final slots = [
        _starter('s1', 1, userId: null),
        _starter('s2', 2, userId: null),
      ];

      final dups = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.duplicatePlayer).toList();
      expect(dups, isEmpty);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  Ranking order
  // ═════════════════════════════════════════════════════════════

  group('rankingOrder', () {
    test(
      'ranking violation: position 2 has better ranking than position 1',
      () {
        final slots = [
          _starter('s1', 1, userId: 'u1', ranking: 5), // R5
          _starter(
            's2',
            2,
            userId: 'u2',
            ranking: 2,
          ), // R2 (better!) → violation
          _reserve('r1', 1, userId: 'u3', ranking: 8),
        ];

        final vs = detectLineupViolations(slots);
        expect(_codes(vs), contains(LineupViolationCode.rankingOrder));

        final rank = vs.firstWhere(
          (v) => v.code == LineupViolationCode.rankingOrder,
        );
        expect(rank.message, contains('Position 2'));
        expect(rank.message, contains('R2'));
        expect(rank.message, contains('R5'));
      },
    );

    test('multiple ranking violations detected', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 5),
        _starter('s2', 2, userId: 'u2', ranking: 2), // violation
        _starter('s3', 3, userId: 'u3', ranking: 1), // violation
      ];

      final ranks = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.rankingOrder).toList();
      expect(ranks.length, 2);
    });

    test('equal rankings are ok (non-decreasing)', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 3),
        _starter('s2', 2, userId: 'u2', ranking: 3),
        _starter('s3', 3, userId: 'u3', ranking: 5),
      ];

      final ranks = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.rankingOrder).toList();
      expect(ranks, isEmpty);
    });

    test(
      'missing ranking data on any starter → skip ranking check entirely',
      () {
        final slots = [
          _starter('s1', 1, userId: 'u1', ranking: 5),
          _starter('s2', 2, userId: 'u2'), // no ranking
          _starter('s3', 3, userId: 'u3', ranking: 1), // would be violation
        ];

        final ranks = detectLineupViolations(
          slots,
        ).where((v) => v.code == LineupViolationCode.rankingOrder).toList();
        expect(
          ranks,
          isEmpty,
          reason: 'Should skip when ranking data incomplete',
        );
      },
    );

    test('no ranking data at all → skip ranking check', () {
      final slots = [
        _starter('s1', 1, userId: 'u1'),
        _starter('s2', 2, userId: 'u2'),
      ];

      final ranks = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.rankingOrder).toList();
      expect(ranks, isEmpty);
    });

    test('reserves are not included in ranking order check', () {
      // Starters are in correct order, reserve has better ranking — that's fine
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 3),
        _starter('s2', 2, userId: 'u2', ranking: 5),
        _reserve('r1', 1, userId: 'u3', ranking: 1), // better than starters
      ];

      final ranks = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.rankingOrder).toList();
      expect(ranks, isEmpty);
    });

    test('starters out of position order still checked by position', () {
      // Slots arrive in arbitrary order but position determines the check
      final slots = [
        _starter('s2', 2, userId: 'u2', ranking: 1), // position 2, R1
        _starter('s1', 1, userId: 'u1', ranking: 5), // position 1, R5
      ];

      // After sorting by position: pos1=R5, pos2=R1 → R1 < R5 → violation
      final ranks = detectLineupViolations(
        slots,
      ).where((v) => v.code == LineupViolationCode.rankingOrder).toList();
      expect(ranks.length, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  Combined scenarios
  // ═════════════════════════════════════════════════════════════

  group('combined', () {
    test('multiple violation types at once', () {
      final slots = [
        _starter('s1', 1, userId: 'u1', ranking: 5),
        _starter('s2', 2, userId: 'u1', ranking: 2), // duplicate + ranking
        _starter('s3', 3, userId: null, ranking: null), // missing starter
      ];

      final vs = detectLineupViolations(slots);
      final codes = _codes(vs);
      expect(codes, contains(LineupViolationCode.missingStarter));
      expect(codes, contains(LineupViolationCode.duplicatePlayer));
      // Ranking check skipped because s3 has no ranking
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  LineupViolation model
  // ═════════════════════════════════════════════════════════════

  group('LineupViolation', () {
    test('equality', () {
      const a = LineupViolation(
        code: LineupViolationCode.missingStarter,
        message: 'test',
        slotId: 's1',
      );
      const b = LineupViolation(
        code: LineupViolationCode.missingStarter,
        message: 'test',
        slotId: 's1',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString', () {
      const v = LineupViolation(
        code: LineupViolationCode.duplicatePlayer,
        message: 'dup',
      );
      expect(v.toString(), contains('duplicatePlayer'));
      expect(v.toString(), contains('dup'));
    });
  });
}
