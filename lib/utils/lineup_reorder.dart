/// Pure utility functions for lineup reorder operations.
/// Extracted for unit-testability – no Flutter/Supabase dependencies.

/// Represents a minimal lineup slot for reorder operations.
class ReorderSlot {
  final String id;
  final String slotType; // 'starter' | 'reserve'
  final int position;

  const ReorderSlot({
    required this.id,
    required this.slotType,
    required this.position,
  });

  /// Create from a raw DB map.
  factory ReorderSlot.fromMap(Map<String, dynamic> map) {
    return ReorderSlot(
      id: map['id'] as String,
      slotType: map['slot_type'] as String,
      position: map['position'] as int,
    );
  }
}

/// Apply a reorder operation on a list of maps (optimistic local update).
///
/// Takes the current ordered list [items], the drag [oldIndex], and the
/// drop [newIndex] **as provided by Flutter's ReorderableListView.onReorder**.
///
/// Flutter convention: when dragging DOWN (oldIndex < newIndex), [newIndex]
/// refers to the position in the list *before* the item is removed.
/// This function applies the adjustment `newIndex -= 1` internally.
/// **Do NOT pre-adjust** newIndex before calling this function.
///
/// Returns a new list with:
/// - The item moved from [oldIndex] to the adjusted target position
/// - Each item's `slot_type` and `position` updated to reflect the new order
///   (first [starterCount] items are starters at position 1..N,
///   remaining items are reserves at position 1..M).
///
/// The original list is NOT mutated (each map is deep-copied).
List<Map<String, dynamic>> applyReorder({
  required List<Map<String, dynamic>> items,
  required int oldIndex,
  required int newIndex,
  required int starterCount,
}) {
  // ── Off-by-one adjustment (Flutter ReorderableListView convention) ──
  // This is the SINGLE place where the adjustment happens.
  int adjustedNew = newIndex;
  if (oldIndex < adjustedNew) adjustedNew -= 1;
  if (oldIndex == adjustedNew) return List.of(items);

  // Deep-copy each map so we don't mutate the originals
  final result = items.map((m) => Map<String, dynamic>.from(m)).toList();

  // Perform the move
  final moved = result.removeAt(oldIndex);
  result.insert(adjustedNew, moved);

  // Re-assign slot_type and position based on new order
  for (int i = 0; i < result.length; i++) {
    if (i < starterCount) {
      result[i]['slot_type'] = 'starter';
      result[i]['position'] = i + 1;
    } else {
      result[i]['slot_type'] = 'reserve';
      result[i]['position'] = i - starterCount + 1;
    }
  }

  return result;
}

/// Compute the single [MoveStep] needed to transition from [before] to [after].
///
/// Identifies the dragged item by finding the element whose linear index
/// changed the most between the two lists.  For a single drag-and-drop this
/// is always unambiguous.  For adjacent swaps (both items move by 1) either
/// item is valid — the server swap is symmetric.
///
/// Returns a list containing exactly ONE [MoveStep], or an empty list if the
/// two lists are identical (no-op).
List<MoveStep> computeMoveSteps({
  required List<Map<String, dynamic>> before,
  required List<Map<String, dynamic>> after,
}) {
  if (before.isEmpty || after.isEmpty || before.length != after.length) {
    return [];
  }

  // Build id → index maps for both lists.
  final beforeIndex = <String, int>{};
  final afterIndex = <String, int>{};
  for (int i = 0; i < before.length; i++) {
    beforeIndex[before[i]['id'] as String] = i;
  }
  for (int i = 0; i < after.length; i++) {
    afterIndex[after[i]['id'] as String] = i;
  }

  // Identify the moved item: the one whose index changed the most.
  String? movedId;
  int maxDist = 0;
  for (final entry in beforeIndex.entries) {
    final dist = (entry.value - afterIndex[entry.key]!).abs();
    if (dist > maxDist) {
      maxDist = dist;
      movedId = entry.key;
    }
  }

  if (movedId == null || maxDist == 0) return []; // No change

  final fromIdx = beforeIndex[movedId]!;
  final toIdx = afterIndex[movedId]!;

  return [
    MoveStep(
      fromType: before[fromIdx]['slot_type'] as String,
      fromPos: before[fromIdx]['position'] as int,
      toType: after[toIdx]['slot_type'] as String,
      toPos: after[toIdx]['position'] as int,
    ),
  ];
}

/// Convert a [MoveStep] + matchId into the parameter map expected by the
/// `move_lineup_slot` RPC.  Pure mapping — no heuristics.
///
/// Returns `null` if the step is a no-op (from == to).
Map<String, dynamic>? moveStepToRpcParams({
  required String matchId,
  required MoveStep step,
}) {
  if (step.fromType == step.toType && step.fromPos == step.toPos) {
    return null; // no-op
  }
  return {
    'p_match_id': matchId,
    'p_from_type': step.fromType,
    'p_from_pos': step.fromPos,
    'p_to_type': step.toType,
    'p_to_pos': step.toPos,
  };
}

/// A single move instruction for the server RPC (`move_lineup_slot`).
class MoveStep {
  final String fromType;
  final int fromPos;
  final String toType;
  final int toPos;

  const MoveStep({
    required this.fromType,
    required this.fromPos,
    required this.toType,
    required this.toPos,
  });

  @override
  String toString() =>
      'MoveStep($fromType#$fromPos → $toType#$toPos)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveStep &&
          fromType == other.fromType &&
          fromPos == other.fromPos &&
          toType == other.toType &&
          toPos == other.toPos;

  @override
  int get hashCode => Object.hash(fromType, fromPos, toType, toPos);
}
