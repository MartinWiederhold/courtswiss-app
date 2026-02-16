import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../utils/lineup_reorder.dart';
import 'ui/cs_toast.dart';

/// Callback signature for persisting a reorder operation.
///
/// [reorderedSlots] is the new ordered list (already with updated
/// slot_type / position), [moveStep] is the server instruction.
///
/// **Error contract**: completes normally on success; THROWS on failure.
/// The widget catches the exception and rolls back the optimistic UI.
typedef PersistReorderCallback =
    Future<void> Function(
      List<Map<String, dynamic>> reorderedSlots,
      MoveStep moveStep,
    );

/// Stable, self-contained Drag & Drop lineup list.
///
/// Design decisions:
/// - Uses [ReorderableListView.builder] with explicit drag handles.
/// - Optimistic UI: items reorder instantly; on server error the old
///   state is restored and a SnackBar is shown.
/// - Debounces rapid drags: a second drag is blocked until the first
///   persist completes (via [_persisting] guard).
/// - All keys are [ValueKey<String>] based on slot id → no flicker.
///
/// **Hook for rule-violation warnings (future):**
/// After a successful reorder, consumers can inspect the new list and
/// show warnings (e.g. ranking order violated).  Attach logic to
/// [onReorderComplete] or wrap this widget with a listener.
class LineupReorderList extends StatefulWidget {
  /// Ordered lineup items (starters first, then reserves).
  /// Each map MUST contain at least: `id`, `slot_type`, `position`,
  /// and optionally `user_id`, `cs_team_players`, etc.
  final List<Map<String, dynamic>> items;

  /// Number of starter slots (items[0..starterCount-1] are starters).
  final int starterCount;

  /// Whether drag & drop is enabled.
  /// Set to `false` when:  loading, generating, publishing, or non-admin.
  final bool canReorder;

  /// Called to persist the reorder on the server.
  final PersistReorderCallback onPersistReorder;

  /// Called after a successful reorder to allow rule-violation checks.
  /// The parameter is the new ordered list.
  final ValueChanged<List<Map<String, dynamic>>>? onReorderComplete;

  /// Builder for each slot tile.  Receives the slot map and the linear
  /// index in the combined (starter+reserve) list.
  final Widget Function(
    BuildContext context,
    Map<String, dynamic> slot,
    int index,
  )
  itemBuilder;

  /// Optional label shown above the list.
  final String? headerHint;

  const LineupReorderList({
    super.key,
    required this.items,
    required this.starterCount,
    required this.canReorder,
    required this.onPersistReorder,
    required this.itemBuilder,
    this.onReorderComplete,
    this.headerHint,
  });

  @override
  State<LineupReorderList> createState() => _LineupReorderListState();
}

class _LineupReorderListState extends State<LineupReorderList> {
  /// Local working copy for optimistic UI.
  late List<Map<String, dynamic>> _currentItems;

  /// Guard against concurrent reorder persists.
  bool _persisting = false;

  @override
  void initState() {
    super.initState();
    _currentItems = _deepCopyItems(widget.items);
  }

  @override
  void didUpdateWidget(covariant LineupReorderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Accept new items from parent ONLY when we're not mid-persist
    // (otherwise we'd overwrite our optimistic state).
    if (!_persisting) {
      _currentItems = _deepCopyItems(widget.items);
    }
  }

  /// Deep-copy the list AND each map inside so rollback snapshots are
  /// completely independent from the original data.
  static List<Map<String, dynamic>> _deepCopyItems(
    List<Map<String, dynamic>> items,
  ) {
    return items.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (!widget.canReorder || _persisting) return;
    if (oldIndex == newIndex) return;

    // Deep-copy snapshot BEFORE the drag for guaranteed rollback.
    final before = _deepCopyItems(_currentItems);

    // Compute new order (pure function – off-by-one is handled inside).
    final after = applyReorder(
      items: _currentItems,
      oldIndex: oldIndex,
      newIndex: newIndex,
      starterCount: widget.starterCount,
    );

    // Compute the server move instruction.
    final steps = computeMoveSteps(before: before, after: after);
    if (steps.isEmpty) return;

    // Haptic feedback on drag
    HapticFeedback.mediumImpact();

    // Optimistic UI update
    setState(() => _currentItems = after);

    // Persist asynchronously
    _persistReorder(before, after, steps.first);
  }

  Future<void> _persistReorder(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
    MoveStep step,
  ) async {
    _persisting = true;
    try {
      // Single await — completes normally on success, throws on failure.
      await widget.onPersistReorder(after, step);
      if (!mounted) return; // Widget disposed during async gap

      // Notify consumer for post-reorder checks
      // (e.g. rule-violation warnings can hook here)
      widget.onReorderComplete?.call(after);
    } catch (e) {
      if (!mounted) return; // Widget disposed during async gap

      // Rollback optimistic update to the guaranteed deep-copy snapshot.
      setState(() => _currentItems = before);
      CsToast.error(context, AppLocalizations.of(context)!.changeSaveError);
    } finally {
      if (mounted) {
        _persisting = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final starters = _currentItems
        .where((s) => s['slot_type'] == 'starter')
        .length;
    final reserves = _currentItems.length - starters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section header
        Row(
          children: [
            Text(
              l.starterCountHeader('$starters'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (reserves > 0) ...[
              const SizedBox(width: 12),
              Text(
                '· ${l.reserveCountHeader('$reserves')}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ],
        ),
        if (widget.canReorder) ...[
          const SizedBox(height: 2),
          Text(
            widget.headerHint ?? l.lineupReorderHint,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 8),

        // The reorderable list
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _currentItems.length,
          onReorder: _onReorder,
          proxyDecorator: (child, index, animation) {
            // Elevated card effect while dragging
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final elevation = Tween<double>(
                  begin: 0,
                  end: 6,
                ).animate(animation).value;
                return Material(
                  elevation: elevation,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  shadowColor: Colors.black26,
                  child: child,
                );
              },
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final slot = _currentItems[index];
            final slotId = slot['id'] as String;

            return Material(
              key: ValueKey<String>(slotId),
              color: Colors.transparent,
              child: Row(
                children: [
                  // Drag handle (only when reorder is enabled)
                  if (widget.canReorder)
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Icon(
                          Icons.drag_handle,
                          color: _persisting
                              ? Colors.grey.shade300
                              : Colors.grey.shade600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 12),

                  // Slot content from consumer's builder
                  Expanded(child: widget.itemBuilder(context, slot, index)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
