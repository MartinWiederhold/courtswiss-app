import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/utils/lineup_reorder.dart';

// ─── Test helpers ────────────────────────────────────────────

/// Build a minimal slot map for testing.
Map<String, dynamic> _slot(String id, String type, int pos) => {
  'id': id,
  'slot_type': type,
  'position': pos,
};

/// Extract ids in order from a list of slot maps.
List<String> _ids(List<Map<String, dynamic>> items) =>
    items.map((m) => m['id'] as String).toList();

/// Extract (slot_type, position) pairs for assertion.
List<String> _typePos(List<Map<String, dynamic>> items) =>
    items.map((m) => '${m['slot_type']}#${m['position']}').toList();

// ─── Fixtures ────────────────────────────────────────────────

/// 5-item list: 3 starters + 2 reserves.
List<Map<String, dynamic>> _fiveItems() => [
  _slot('A', 'starter', 1),
  _slot('B', 'starter', 2),
  _slot('C', 'starter', 3),
  _slot('D', 'reserve', 1),
  _slot('E', 'reserve', 2),
];

/// 3-item list: 2 starters + 1 reserve.
List<Map<String, dynamic>> _threeItems() => [
  _slot('A', 'starter', 1),
  _slot('B', 'starter', 2),
  _slot('C', 'reserve', 1),
];

void main() {
  // ═════════════════════════════════════════════════════════════
  //  applyReorder
  // ═════════════════════════════════════════════════════════════

  group('applyReorder', () {
    test('off-by-one: drag index 0 to newIndex 2 → item lands at index 1', () {
      // Flutter's ReorderableListView: onReorder(0, 2) means
      // "drag item 0 to the slot BEFORE index 2 (after removal)".
      // Expected: [A,B,C] → [B,A,C] (A moves from 0 to 1)
      final items = _threeItems();
      final result = applyReorder(
        items: items,
        oldIndex: 0,
        newIndex: 2,
        starterCount: 2,
      );

      expect(_ids(result), ['B', 'A', 'C']);
      // slot_type and position are reassigned:
      expect(_typePos(result), ['starter#1', 'starter#2', 'reserve#1']);
    });

    test('drag DOWN: index 0 to 3 in 5-item list', () {
      final items = _fiveItems(); // A B C D E
      final result = applyReorder(
        items: items,
        oldIndex: 0,
        newIndex: 3, // after adjustment: 2
        starterCount: 3,
      );

      // A removed → [B,C,D,E] → insert A at 2 → [B,C,A,D,E]
      expect(_ids(result), ['B', 'C', 'A', 'D', 'E']);
      expect(_typePos(result), [
        'starter#1',
        'starter#2',
        'starter#3',
        'reserve#1',
        'reserve#2',
      ]);
    });

    test('drag UP: index 2 to 0 in 3-item list', () {
      final items = _threeItems(); // A B C
      final result = applyReorder(
        items: items,
        oldIndex: 2,
        newIndex: 0,
        starterCount: 2,
      );

      // C removed → [A,B] → insert C at 0 → [C,A,B]
      expect(_ids(result), ['C', 'A', 'B']);
      expect(_typePos(result), ['starter#1', 'starter#2', 'reserve#1']);
    });

    test('drag UP: index 4 to 1 in 5-item list', () {
      final items = _fiveItems(); // A B C D E
      final result = applyReorder(
        items: items,
        oldIndex: 4,
        newIndex: 1,
        starterCount: 3,
      );

      // E removed → [A,B,C,D] → insert E at 1 → [A,E,B,C,D]
      expect(_ids(result), ['A', 'E', 'B', 'C', 'D']);
      expect(_typePos(result), [
        'starter#1',
        'starter#2',
        'starter#3',
        'reserve#1',
        'reserve#2',
      ]);
    });

    test('no-op: same index returns copy, not mutated original', () {
      final items = _threeItems();
      final result = applyReorder(
        items: items,
        oldIndex: 1,
        newIndex: 1,
        starterCount: 2,
      );

      expect(_ids(result), ['A', 'B', 'C']);
      // Must be a different list instance (not same reference)
      expect(identical(result, items), isFalse);
    });

    test('no-op after adjustment: drag index 1 to newIndex 2 '
        '→ adjustedNew becomes 1 → same position', () {
      // onReorder(1, 2): adjustedNew = 2 - 1 = 1 == oldIndex → no-op
      final items = _threeItems();
      final result = applyReorder(
        items: items,
        oldIndex: 1,
        newIndex: 2,
        starterCount: 2,
      );

      expect(_ids(result), ['A', 'B', 'C']);
    });

    test('cross boundary: starter → reserve and vice versa', () {
      // Move last starter into reserve zone
      final items = _threeItems(); // [A(s1), B(s2), C(r1)] starterCount=2
      final result = applyReorder(
        items: items,
        oldIndex: 1,
        newIndex: 3, // adjusted: 2
        starterCount: 2,
      );

      // B removed → [A,C] → insert B at 2 → [A,C,B]
      expect(_ids(result), ['A', 'C', 'B']);
      // A=starter#1, C=starter#2, B=reserve#1
      expect(_typePos(result), ['starter#1', 'starter#2', 'reserve#1']);
    });

    test('does not mutate original items', () {
      final items = _threeItems();
      final originalA = Map<String, dynamic>.from(items[0]);

      applyReorder(items: items, oldIndex: 2, newIndex: 0, starterCount: 2);

      // Original list and maps must be unchanged
      expect(items[0]['id'], originalA['id']);
      expect(items[0]['slot_type'], originalA['slot_type']);
      expect(items[0]['position'], originalA['position']);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  computeMoveSteps
  // ═════════════════════════════════════════════════════════════

  group('computeMoveSteps', () {
    test('no-op: identical lists → empty steps', () {
      final before = _threeItems();
      final after = _threeItems(); // same content, different instances

      final steps = computeMoveSteps(before: before, after: after);

      expect(steps, isEmpty);
    });

    test('move DOWN: A from index 0 to index 1', () {
      final before = _threeItems(); // [A(s1), B(s2), C(r1)]
      final after = applyReorder(
        items: before,
        oldIndex: 0,
        newIndex: 2,
        starterCount: 2,
      ); // [B(s1), A(s2), C(r1)]

      final steps = computeMoveSteps(before: before, after: after);

      expect(steps.length, 1);
      final step = steps.first;
      // A was at starter#1, now at starter#2
      expect(step.fromType, 'starter');
      expect(step.fromPos, 1);
      expect(step.toType, 'starter');
      expect(step.toPos, 2);
    });

    test('move UP: C from index 2 to index 0', () {
      final before = _threeItems(); // [A(s1), B(s2), C(r1)]
      final after = applyReorder(
        items: before,
        oldIndex: 2,
        newIndex: 0,
        starterCount: 2,
      ); // [C(s1), A(s2), B(r1)]

      final steps = computeMoveSteps(before: before, after: after);

      expect(steps.length, 1);
      final step = steps.first;
      // C was at reserve#1, now at starter#1
      expect(step.fromType, 'reserve');
      expect(step.fromPos, 1);
      expect(step.toType, 'starter');
      expect(step.toPos, 1);
    });

    test('move DOWN in 5-item list: A from index 0 to index 3', () {
      final before = _fiveItems(); // [A(s1), B(s2), C(s3), D(r1), E(r2)]
      final after = applyReorder(
        items: before,
        oldIndex: 0,
        newIndex: 4, // adjusted: 3
        starterCount: 3,
      ); // [B(s1), C(s2), D(s3), A(r1), E(r2)]

      final steps = computeMoveSteps(before: before, after: after);

      expect(steps.length, 1);
      final step = steps.first;
      // A was at starter#1, now at reserve#1
      expect(step.fromType, 'starter');
      expect(step.fromPos, 1);
      expect(step.toType, 'reserve');
      expect(step.toPos, 1);
    });

    test('move UP in 5-item list: E from index 4 to index 1', () {
      final before = _fiveItems(); // [A(s1), B(s2), C(s3), D(r1), E(r2)]
      final after = applyReorder(
        items: before,
        oldIndex: 4,
        newIndex: 1,
        starterCount: 3,
      ); // [A(s1), E(s2), B(s3), C(r1), D(r2)]

      final steps = computeMoveSteps(before: before, after: after);

      expect(steps.length, 1);
      final step = steps.first;
      // E was at reserve#2, now at starter#2
      expect(step.fromType, 'reserve');
      expect(step.fromPos, 2);
      expect(step.toType, 'starter');
      expect(step.toPos, 2);
    });

    test('empty lists → empty steps', () {
      expect(computeMoveSteps(before: [], after: []), isEmpty);
    });

    test('mismatched lengths → empty steps', () {
      final before = _threeItems();
      final after = _fiveItems();
      expect(computeMoveSteps(before: before, after: after), isEmpty);
    });

    test('deterministic: same input always produces same output', () {
      final before = _fiveItems();
      final after = applyReorder(
        items: before,
        oldIndex: 3,
        newIndex: 1,
        starterCount: 3,
      );

      final steps1 = computeMoveSteps(before: before, after: after);
      final steps2 = computeMoveSteps(before: before, after: after);

      expect(steps1.length, 1);
      expect(steps2.length, 1);
      expect(steps1.first, steps2.first);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  moveStepToRpcParams
  // ═════════════════════════════════════════════════════════════

  group('moveStepToRpcParams', () {
    test('maps MoveStep to correct RPC params', () {
      const step = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'reserve',
        toPos: 2,
      );
      final params = moveStepToRpcParams(matchId: 'match-1', step: step);

      expect(params, {
        'p_match_id': 'match-1',
        'p_from_type': 'starter',
        'p_from_pos': 1,
        'p_to_type': 'reserve',
        'p_to_pos': 2,
      });
    });

    test('same-type same-pos (no-op) returns null', () {
      const step = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'starter',
        toPos: 1,
      );
      expect(moveStepToRpcParams(matchId: 'match-1', step: step), isNull);
    });

    test('same-type different-pos maps correctly', () {
      const step = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'starter',
        toPos: 3,
      );
      final params = moveStepToRpcParams(matchId: 'match-2', step: step);

      expect(params, {
        'p_match_id': 'match-2',
        'p_from_type': 'starter',
        'p_from_pos': 1,
        'p_to_type': 'starter',
        'p_to_pos': 3,
      });
    });

    test('cross-boundary move maps correctly', () {
      const step = MoveStep(
        fromType: 'reserve',
        fromPos: 2,
        toType: 'starter',
        toPos: 1,
      );
      final params = moveStepToRpcParams(matchId: 'match-3', step: step);

      expect(params, {
        'p_match_id': 'match-3',
        'p_from_type': 'reserve',
        'p_from_pos': 2,
        'p_to_type': 'starter',
        'p_to_pos': 1,
      });
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  End-to-end pipeline: drag → applyReorder → computeMoveSteps
  //    → moveStepToRpcParams
  // ═════════════════════════════════════════════════════════════

  group('end-to-end pipeline', () {
    test('drag down in 3-item list → correct RPC params', () {
      final before = _threeItems(); // [A(s1), B(s2), C(r1)]
      final after = applyReorder(
        items: before,
        oldIndex: 0,
        newIndex: 2,
        starterCount: 2,
      ); // [B(s1), A(s2), C(r1)]

      final steps = computeMoveSteps(before: before, after: after);
      expect(steps.length, 1);

      final params = moveStepToRpcParams(matchId: 'test', step: steps.first);
      expect(params, isNotNull);
      expect(params!['p_from_type'], 'starter');
      expect(params['p_from_pos'], 1);
      expect(params['p_to_type'], 'starter');
      expect(params['p_to_pos'], 2);
    });

    test('drag up across boundary in 5-item list → correct RPC params', () {
      final before = _fiveItems(); // [A(s1), B(s2), C(s3), D(r1), E(r2)]
      final after = applyReorder(
        items: before,
        oldIndex: 4,
        newIndex: 1,
        starterCount: 3,
      ); // [A(s1), E(s2), B(s3), C(r1), D(r2)]

      final steps = computeMoveSteps(before: before, after: after);
      expect(steps.length, 1);

      final params = moveStepToRpcParams(matchId: 'test', step: steps.first);
      expect(params, isNotNull);
      expect(params!['p_from_type'], 'reserve');
      expect(params['p_from_pos'], 2);
      expect(params['p_to_type'], 'starter');
      expect(params['p_to_pos'], 2);
    });

    test(
      'no-op drag → computeMoveSteps returns empty → no RPC call needed',
      () {
        final before = _threeItems();
        // Same items, no actual move
        final after = applyReorder(
          items: before,
          oldIndex: 1,
          newIndex: 2, // adjustedNew = 1 == oldIndex → no-op
          starterCount: 2,
        );

        final steps = computeMoveSteps(before: before, after: after);
        expect(steps, isEmpty);
        // No moveStepToRpcParams call needed → no server request
      },
    );
  });

  // ═════════════════════════════════════════════════════════════
  //  ReorderSlot
  // ═════════════════════════════════════════════════════════════

  group('ReorderSlot', () {
    test('fromMap parses correctly', () {
      final slot = ReorderSlot.fromMap({
        'id': 'slot-1',
        'slot_type': 'starter',
        'position': 3,
      });

      expect(slot.id, 'slot-1');
      expect(slot.slotType, 'starter');
      expect(slot.position, 3);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  MoveStep
  // ═════════════════════════════════════════════════════════════

  group('MoveStep', () {
    test('equality and hashCode', () {
      const a = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'reserve',
        toPos: 2,
      );
      const b = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'reserve',
        toPos: 2,
      );
      const c = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'starter',
        toPos: 2,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('toString', () {
      const step = MoveStep(
        fromType: 'starter',
        fromPos: 1,
        toType: 'reserve',
        toPos: 3,
      );
      expect(step.toString(), 'MoveStep(starter#1 → reserve#3)');
    });
  });
}
