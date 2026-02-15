import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/carpool_offer.dart';
import '../models/dinner_rsvp.dart';
import '../models/expense.dart';
import '../services/avatar_service.dart';
import '../services/carpool_service.dart';
import '../services/dinner_service.dart';
import '../services/expense_service.dart';
import '../services/match_service.dart';
import '../services/lineup_service.dart';
import '../services/sub_request_service.dart';
import '../services/team_player_service.dart';
import '../theme/cs_theme.dart';
import '../utils/lineup_reorder.dart';
import '../utils/lineup_rules.dart';
import '../utils/sub_request_timeout.dart';
import '../widgets/lineup_reorder_list.dart';
import '../widgets/ui/ui.dart';
import 'create_match_screen.dart';

class MatchDetailScreen extends StatefulWidget {
  final String matchId;
  final String teamId;
  final Map<String, dynamic> match;

  const MatchDetailScreen({
    super.key,
    required this.matchId,
    required this.teamId,
    required this.match,
  });

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  static final _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _availability = [];
  List<Map<String, dynamic>> _members = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  String? _myStatus;

  // ── Player slots (for name/ranking resolution) ──
  Map<String, Map<String, dynamic>> _claimedMap = {};

  // ── Avatar resolution ──
  Map<String, String> _avatarUrls = {};

  // ── Lineup state ──
  Map<String, dynamic>? _lineup; // cs_match_lineups row (or null)
  List<Map<String, dynamic>> _lineupSlots = [];
  bool _lineupGenerating = false;
  bool _lineupPublishing = false;
  List<LineupViolation> _lineupViolations = [];

  // ── Sub-request state ──
  List<Map<String, dynamic>> _subRequests = [];
  List<Map<String, dynamic>> _myPendingSubRequests = [];

  // ── Carpool state ──
  List<CarpoolOffer> _carpoolOffers = [];
  final Set<String> _expandedCarpoolOffers = {};
  RealtimeChannel? _carpoolOffersChannel;
  RealtimeChannel? _carpoolPassengersChannel;

  // ── Dinner RSVP state ──
  List<DinnerRsvp> _dinnerRsvps = [];
  String? _myDinnerStatus; // 'yes' | 'no' | 'maybe' | null
  bool _dinnerExpanded = false;
  bool _dinnerUpdating = false;

  // ── Expenses state ──
  List<Expense> _expenses = [];

  // ── Realtime subscription for lineup changes ──
  RealtimeChannel? _lineupChannel;

  // ── Generate-dialog defaults (overridden from lineup row if exists) ──
  int _starterCount = 6;
  int _reserveCount = 3;
  bool _includeMaybe = false;

  /// Tab index for segment tabs.
  int _tabIndex = 0;

  /// Live match data (may be updated after edit).
  late Map<String, dynamic> _match;

  @override
  void initState() {
    super.initState();
    _match = Map.of(widget.match);
    _load();
    _subscribeLineupChanges();
    _subscribeCarpoolChanges();
  }

  @override
  void dispose() {
    _lineupChannel?.unsubscribe();
    _carpoolOffersChannel?.unsubscribe();
    _carpoolPassengersChannel?.unsubscribe();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  Realtime: auto-reload lineup when slots change (auto-promotion)
  // ═══════════════════════════════════════════════════════════

  void _subscribeLineupChanges() {
    _lineupChannel = _supabase
        .channel('lineup_slots:${widget.matchId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cs_match_lineup_slots',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: widget.matchId,
          ),
          callback: (payload) {
            debugPrint('LINEUP_REALTIME: slot change detected, reloading…');
            _reloadLineup();
          },
        )
        .subscribe();
  }

  /// Reload only lineup data (not the full page).
  Future<void> _reloadLineup() async {
    try {
      final lineup = await LineupService.getLineup(widget.matchId);
      List<Map<String, dynamic>> slots = [];
      if (lineup != null) {
        slots = await LineupService.getSlots(widget.matchId);
      }
      if (!mounted) return;
      setState(() {
        _lineup = lineup;
        _lineupSlots = slots;
        if (lineup != null) {
          _starterCount = (lineup['starters_count'] as int?) ?? 6;
          _reserveCount = (lineup['reserves_count'] as int?) ?? 3;
          _includeMaybe = (lineup['include_maybe'] as bool?) ?? false;
        }
      });
      _recomputeLineupViolations(slots);
    } catch (e) {
      debugPrint('Lineup reload error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Realtime: carpool (offers + passengers)
  // ═══════════════════════════════════════════════════════════

  void _subscribeCarpoolChanges() {
    _carpoolOffersChannel = _supabase
        .channel('carpool_offers:${widget.matchId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cs_carpool_offers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: widget.matchId,
          ),
          callback: (_) {
            debugPrint('CARPOOL_RT: offer change, reloading…');
            _reloadCarpool();
          },
        )
        .subscribe();

    _carpoolPassengersChannel = _supabase
        .channel('carpool_passengers:${widget.matchId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cs_carpool_passengers',
          callback: (_) {
            debugPrint('CARPOOL_RT: passenger change, reloading…');
            _reloadCarpool();
          },
        )
        .subscribe();
  }

  Future<void> _reloadCarpool({bool rethrow_ = false}) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('CARPOOL_LOAD: matchId=${widget.matchId} uid=$uid');
    try {
      final fullRows = await CarpoolService.listOffers(widget.matchId);
      debugPrint('CARPOOL_LOAD: ${fullRows.length} offers returned');
      if (!mounted) return;
      setState(() {
        _carpoolOffers = CarpoolService.parseOffers(
          fullRows,
          claimedMap: _claimedMap,
          profiles: _profiles,
        );
      });
    } catch (e) {
      debugPrint('CARPOOL_LOAD ERROR: $e');
      if (rethrow_) rethrow;
    }
  }

  Future<void> _reloadDinner() async {
    try {
      final rsvps = await DinnerService.getRsvps(widget.matchId);
      if (!mounted) return;
      final uid = _supabase.auth.currentUser?.id;
      String? myStatus;
      for (final r in rsvps) {
        if (r.userId == uid) {
          myStatus = r.status;
          break;
        }
      }
      setState(() {
        _dinnerRsvps = rsvps;
        _myDinnerStatus = myStatus;
      });
    } catch (e) {
      debugPrint('DINNER_LOAD ERROR: $e');
    }
  }

  Future<void> _reloadExpenses() async {
    try {
      final expenses = await ExpenseService.listExpenses(widget.matchId);
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
      });
    } catch (e) {
      debugPrint('EXPENSE_LOAD ERROR: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Data loading
  // ═══════════════════════════════════════════════════════════

  bool get _isAdmin {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    return _members.any((m) => m['user_id'] == uid && m['role'] == 'captain');
  }

  bool get _canReorderLineup =>
      !_loading &&
      _lineupSlots.isNotEmpty &&
      _lineup?['status'] == 'draft' &&
      _isAdmin &&
      !_lineupGenerating &&
      !_lineupPublishing;

  bool _loadInProgress = false;

  Future<void> _load() async {
    if (_loadInProgress) {
      debugPrint('MATCH_DETAIL _load skipped (already in progress)');
      return;
    }
    _loadInProgress = true;
    setState(() => _loading = true);
    try {
      // 1. Availability
      final avail = await MatchService.listAvailability(widget.matchId);

      // 2. Team members (with profile embed fallback)
      List<Map<String, dynamic>> members;
      Map<String, Map<String, dynamic>> profileMap = {};
      try {
        final rows = await _supabase
            .from('cs_team_members')
            .select(
              'user_id, role, nickname, is_playing, ranking, '
              'cs_app_profiles(display_name, email, avatar_path)',
            )
            .eq('team_id', widget.teamId)
            .order('created_at', ascending: true);
        members = List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        final rows = await _supabase
            .from('cs_team_members')
            .select('user_id, role, nickname, is_playing, ranking, created_at')
            .eq('team_id', widget.teamId)
            .order('created_at', ascending: true);
        members = List<Map<String, dynamic>>.from(rows);

        final uids = members
            .map((m) => m['user_id'] as String)
            .toSet()
            .toList();
        if (uids.isNotEmpty) {
          final pRows = await _supabase
              .from('cs_app_profiles')
              .select('user_id, display_name, email, avatar_path')
              .inFilter('user_id', uids);
          for (final p in List<Map<String, dynamic>>.from(pRows)) {
            profileMap[p['user_id'] as String] = p;
          }
        }
      }

      // 3. Player slots for name/ranking resolution
      Map<String, Map<String, dynamic>> claimedMap = {};
      try {
        final slots = await TeamPlayerService.listPlayers(widget.teamId);
        claimedMap = TeamPlayerService.buildClaimedMap(slots);
      } catch (_) {}

      // 4. My availability status
      final uid = _supabase.auth.currentUser?.id;
      String? myStatus;
      for (final a in avail) {
        if (a['user_id'] == uid) {
          myStatus = a['status'] as String?;
          break;
        }
      }

      // 5. Lineup + slots
      Map<String, dynamic>? lineup;
      List<Map<String, dynamic>> lineupSlots = [];
      try {
        lineup = await LineupService.getLineup(widget.matchId);
        if (lineup != null) {
          lineupSlots = await LineupService.getSlots(widget.matchId);
          _starterCount = (lineup['starters_count'] as int?) ?? 6;
          _reserveCount = (lineup['reserves_count'] as int?) ?? 3;
          _includeMaybe = (lineup['include_maybe'] as bool?) ?? false;
        }
      } catch (e) {
        debugPrint('Lineup load error: $e');
      }

      // 6. Sub requests
      List<Map<String, dynamic>> subRequests = [];
      List<Map<String, dynamic>> myPendingSubRequests = [];
      try {
        await SubRequestService.expireStale();
        subRequests = await SubRequestService.listForMatch(widget.matchId);
        myPendingSubRequests = await SubRequestService.listMyPendingRequests();
        myPendingSubRequests = myPendingSubRequests
            .where((r) => r['match_id'] == widget.matchId)
            .toList();
      } catch (e) {
        debugPrint('Sub requests load error: $e');
      }

      if (!mounted) return;
      setState(() {
        _availability = avail;
        _members = members;
        _profiles = profileMap;
        _claimedMap = claimedMap;
        _myStatus = myStatus;
        _lineup = lineup;
        _lineupSlots = lineupSlots;
        _subRequests = subRequests;
        _myPendingSubRequests = myPendingSubRequests;
        _loading = false;
      });

      _recomputeLineupViolations(lineupSlots);

      _reloadCarpool();
      _reloadDinner();
      _reloadExpenses();
      _resolveAvatarUrls();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    } finally {
      _loadInProgress = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Avatar resolution
  // ═══════════════════════════════════════════════════════════

  Future<void> _resolveAvatarUrls() async {
    final allUserIds = <String>{};
    for (final m in _members) {
      final uid = m['user_id'] as String?;
      if (uid != null) allUserIds.add(uid);
    }
    for (final entry in _claimedMap.entries) {
      allUserIds.add(entry.key);
    }

    if (allUserIds.isEmpty) {
      if (mounted) setState(() => _avatarUrls = {});
      return;
    }

    try {
      final profileRows = await _supabase
          .from('cs_app_profiles')
          .select('user_id, avatar_path')
          .inFilter('user_id', allUserIds.toList());

      final pathsByUid = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(profileRows)) {
        final uid = row['user_id'] as String?;
        final path = row['avatar_path'] as String?;
        if (uid != null && path != null && path.isNotEmpty) {
          pathsByUid[uid] = path;
        }
      }

      if (pathsByUid.isEmpty) {
        if (mounted) setState(() => _avatarUrls = {});
        return;
      }

      final uniquePaths = pathsByUid.values.toSet().toList();
      final signedMap = await AvatarService.createSignedUrls(uniquePaths);

      final result = <String, String>{};
      for (final entry in pathsByUid.entries) {
        final signed = signedMap[entry.value];
        if (signed != null) result[entry.key] = signed;
      }

      if (mounted) setState(() => _avatarUrls = result);
    } catch (e) {
      debugPrint('Avatar resolve error: $e');
    }
  }

  String? _avatarUrlForUser(String userId) => _avatarUrls[userId];

  String _initialsForUser(String userId) {
    final claimed = _claimedMap[userId];
    if (claimed != null) {
      final f = (claimed['first_name'] as String? ?? '');
      final l = (claimed['last_name'] as String? ?? '');
      if (f.isNotEmpty && l.isNotEmpty) {
        return '${f[0]}${l[0]}'.toUpperCase();
      }
      if (f.isNotEmpty) return f[0].toUpperCase();
    }
    final profile = _profiles[userId];
    if (profile != null) {
      final name = profile['display_name'] as String? ?? '';
      if (name.isNotEmpty && name != 'Spieler') {
        final parts = name.trim().split(' ');
        if (parts.length >= 2) {
          return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
        }
        return name[0].toUpperCase();
      }
    }
    final member = _members.where((m) => m['user_id'] == userId).firstOrNull;
    if (member != null) {
      final nick = member['nickname'] as String?;
      if (nick != null && nick.isNotEmpty) return nick[0].toUpperCase();
      final embedded = member['cs_app_profiles'];
      if (embedded is Map<String, dynamic>) {
        final dn = embedded['display_name'] as String?;
        if (dn != null && dn.isNotEmpty && dn != 'Spieler') {
          return dn[0].toUpperCase();
        }
      }
    }
    return '?';
  }

  Widget _userAvatar(String userId, {double radius = 16}) {
    final url = _avatarUrlForUser(userId);
    final initials = _initialsForUser(userId);

    return CircleAvatar(
      radius: radius,
      backgroundColor: CsColors.gray200,
      backgroundImage: url != null ? NetworkImage(url) : null,
      onBackgroundImageError: url != null
          ? (e, s) {
              setState(() => _avatarUrls.remove(userId));
            }
          : null,
      child: url == null
          ? Text(
              initials,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.75,
                color: CsColors.gray600,
              ),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Availability
  // ═══════════════════════════════════════════════════════════

  /// In-flight flag to disable buttons while the API call runs.
  bool _availUpdating = false;

  Future<void> _setAvailability(String status) async {
    if (_availUpdating) return;
    final old = _myStatus;

    // Haptic feedback (selection click).
    HapticFeedback.selectionClick();

    // Optimistic UI update — instant.
    setState(() {
      _myStatus = status;
      _availUpdating = true;
    });

    try {
      await MatchService.setAvailability(
        matchId: widget.matchId,
        status: status,
      );
      // Lightweight reload: only availability list (no full-page _load).
      final avail = await MatchService.listAvailability(widget.matchId);
      if (!mounted) return;
      final uid = _supabase.auth.currentUser?.id;
      String? confirmed;
      for (final a in avail) {
        if (a['user_id'] == uid) {
          confirmed = a['status'] as String?;
          break;
        }
      }
      setState(() {
        _availability = avail;
        _myStatus = confirmed ?? status;
        _availUpdating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _myStatus = old;
        _availUpdating = false;
      });
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Generate (draft only, no notifications)
  // ═══════════════════════════════════════════════════════════

  Future<void> _generateLineup() async {
    int tmpStarters = _starterCount;
    int tmpReserves = _reserveCount;
    bool tmpMaybe = _includeMaybe;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return CsBottomSheetForm(
            title: 'Aufstellung generieren',
            ctaLabel: 'Generieren',
            onCta: () => Navigator.pop(ctx, true),
            secondaryLabel: 'Abbrechen',
            onSecondary: () => Navigator.pop(ctx, false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Die Aufstellung wird anhand des Rankings und '
                  'der Verfügbarkeiten erstellt.\n'
                  'Du kannst danach manuell tauschen.\n\n'
                  'Eine bestehende Aufstellung wird überschrieben.',
                  style: CsTextStyles.bodySmall,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Starter',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: tmpStarters > 1
                          ? () => setD(() => tmpStarters--)
                          : null,
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$tmpStarters',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: tmpStarters < 12
                          ? () => setD(() => tmpStarters++)
                          : null,
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Ersatz',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: tmpReserves > 0
                          ? () => setD(() => tmpReserves--)
                          : null,
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$tmpReserves',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: tmpReserves < 6
                          ? () => setD(() => tmpReserves++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                title: const Text('Unsichere berücksichtigen'),
                subtitle: const Text(
                    'Spieler mit „Unsicher" werden ergänzend aufgestellt.',
                  ),
                  value: tmpMaybe,
                  onChanged: (v) => setD(() => tmpMaybe = v),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (confirm != true) return;

    setState(() {
      _lineupGenerating = true;
      _starterCount = tmpStarters;
      _reserveCount = tmpReserves;
      _includeMaybe = tmpMaybe;
    });

    try {
      final result = await LineupService.generateLineup(
        matchId: widget.matchId,
        starters: tmpStarters,
        reserves: tmpReserves,
        includeMaybe: tmpMaybe,
      );
      if (!mounted) return;
      CsToast.success(context,
        'Aufstellung erstellt: '
        '${result['starters']} Starter, '
        '${result['reserves']} Ersatz',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    } finally {
      if (mounted) setState(() => _lineupGenerating = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Manual move (up/down arrows)
  // ═══════════════════════════════════════════════════════════

  List<Map<String, dynamic>> get _orderedSlots =>
      LineupService.buildOrderedSlots(_lineupSlots);

  Future<void> _moveUp(int linearIndex) async {
    final ordered = _orderedSlots;
    if (linearIndex <= 0) return;
    final from = ordered[linearIndex];
    final to = ordered[linearIndex - 1];
    await _swapSlots(from, to);
  }

  Future<void> _moveDown(int linearIndex) async {
    final ordered = _orderedSlots;
    if (linearIndex >= ordered.length - 1) return;
    final from = ordered[linearIndex];
    final to = ordered[linearIndex + 1];
    await _swapSlots(from, to);
  }

  Future<void> _swapSlots(
    Map<String, dynamic> from,
    Map<String, dynamic> to,
  ) async {
    try {
      await LineupService.moveSlot(
        matchId: widget.matchId,
        fromType: from['slot_type'] as String,
        fromPos: from['position'] as int,
        toType: to['slot_type'] as String,
        toPos: to['position'] as int,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Drag & Drop reorder (via LineupReorderList widget)
  // ═══════════════════════════════════════════════════════════

  Future<void> _onPersistReorder(
    List<Map<String, dynamic>> reorderedSlots,
    MoveStep step,
  ) async {
    if (!_canReorderLineup) {
      debugPrint(
        'LINEUP_REORDER skip: canReorder=false '
        '(state changed during drag)',
      );
      return;
    }

    await LineupService.reorderLineup(
      matchId: widget.matchId,
      fromType: step.fromType,
      fromPos: step.fromPos,
      toType: step.toType,
      toPos: step.toPos,
    );

    if (mounted) await _reloadLineup();
  }

  void _onReorderComplete(List<Map<String, dynamic>> newOrder) {
    debugPrint('LINEUP_REORDER_COMPLETE: ${newOrder.length} slots');
    _recomputeLineupViolations(newOrder);
  }

  void _recomputeLineupViolations([List<Map<String, dynamic>>? slots]) {
    final source = slots ?? _lineupSlots;
    final ordered = LineupService.buildOrderedSlots(source);
    final vs = detectLineupViolations(ordered);
    if (mounted) {
      setState(() => _lineupViolations = vs);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Lock / Unlock slot
  // ═══════════════════════════════════════════════════════════

  Future<void> _toggleLock(Map<String, dynamic> slot) async {
    final slotId = slot['id'] as String;
    final currentLocked = slot['locked'] == true;
    final newLocked = !currentLocked;

    setState(() => slot['locked'] = newLocked);

    try {
      await LineupService.toggleSlotLock(slotId: slotId, locked: newLocked);
    } catch (e) {
      if (!mounted) return;
      setState(() => slot['locked'] = currentLocked);
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Publish → sends notifications
  // ═══════════════════════════════════════════════════════════

  Future<void> _publishLineup() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: 'Aufstellung veröffentlichen?',
        ctaLabel: 'Senden',
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Abbrechen',
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.send, size: 40, color: CsColors.blue),
            const SizedBox(height: 12),
            Text(
              'Alle Team-Mitglieder werden über die '
              'Aufstellung informiert (In-App + Push).',
              style: CsTextStyles.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Möchtest du die Aufstellung jetzt senden?',
              style: CsTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _lineupPublishing = true);
    try {
      final result = await LineupService.publishLineup(widget.matchId);
      if (!mounted) return;
      final recipients = result['recipients'] ?? 0;
      CsToast.success(context,
        'Aufstellung veröffentlicht – $recipients Benachrichtigungen gesendet',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    } finally {
      if (mounted) setState(() => _lineupPublishing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Sub-request actions
  // ═══════════════════════════════════════════════════════════

  Future<void> _createSubRequest(String originalUserId) async {
    try {
      final result = await SubRequestService.createRequest(
        matchId: widget.matchId,
        originalUserId: originalUserId,
      );
      if (!mounted) return;
      final success = result['success'] == true;
      if (success) {
        CsToast.success(context, 'Ersatzanfrage an ${result['substitute_name']} gesendet');
      } else {
        CsToast.info(context,
          result['message'] as String? ?? 'Kein verfügbarer Ersatzspieler gefunden.',
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  Future<void> _respondSubRequest(String requestId, String response) async {
    try {
      final result = await SubRequestService.respond(
        requestId: requestId,
        response: response,
      );
      if (!mounted) return;
      final success = result['success'] == true;
      if (success) {
        final msg = response == 'accepted'
            ? 'Ersatzanfrage angenommen'
            : 'Ersatzanfrage abgelehnt';
        CsToast.success(context, msg);
      } else {
        CsToast.error(context,
          result['message'] as String? ?? 'Etwas ist schiefgelaufen.',
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Admin match actions
  // ═══════════════════════════════════════════════════════════

  Future<void> _editMatch() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreateMatchScreen(teamId: widget.teamId, existingMatch: _match),
      ),
    );
    if (changed == true) {
      try {
        final rows = await _supabase
            .from('cs_matches')
            .select()
            .eq('id', widget.matchId)
            .limit(1);
        if (rows.isNotEmpty && mounted) {
          setState(() => _match = Map<String, dynamic>.from(rows.first));
        }
      } catch (_) {}
      _load();
    }
  }

  Future<void> _deleteMatch() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: 'Spiel löschen?',
        ctaLabel: 'Löschen',
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Abbrechen',
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_forever, size: 40, color: CsColors.error),
            const SizedBox(height: 12),
            Text(
              'Möchtest du das Spiel gegen '
              '"${_match['opponent'] ?? '?'}" wirklich löschen?\n\n'
              'Alle Verfügbarkeiten und Aufstellungen gehen verloren.',
              style: CsTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await MatchService.deleteMatch(widget.matchId);
      if (!mounted) return;
      CsToast.success(context, 'Spiel gelöscht');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Name resolution helpers
  // ═══════════════════════════════════════════════════════════

  String _memberName(Map<String, dynamic> member) {
    final userId = member['user_id'] as String?;

    if (userId != null && _claimedMap.containsKey(userId)) {
      return TeamPlayerService.playerDisplayName(_claimedMap[userId]!);
    }

    final nickname = member['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;

    final embedded = member['cs_app_profiles'];
    if (embedded is Map<String, dynamic>) {
      final name = embedded['display_name'] as String?;
      if (name != null && name.isNotEmpty && name != 'Spieler') return name;
      final email = embedded['email'] as String?;
      if (email != null && email.isNotEmpty) return email;
    }

    if (userId != null && _profiles.containsKey(userId)) {
      final p = _profiles[userId]!;
      final n = p['display_name'] as String?;
      if (n != null && n.isNotEmpty && n != 'Spieler') return n;
      final e = p['email'] as String?;
      if (e != null && e.isNotEmpty) return e;
    }

    if (userId != null && userId.length > 8) {
      return '${userId.substring(0, 8)}…';
    }
    return userId ?? '–';
  }

  String _slotUserName(Map<String, dynamic> slot) {
    final label = LineupService.slotLabel(slot);
    if (label != '?') return label;

    final userId = slot['user_id'] as String?;
    if (userId != null) {
      if (_claimedMap.containsKey(userId)) {
        final s = _claimedMap[userId]!;
        final n = TeamPlayerService.playerDisplayName(s);
        final r = TeamPlayerService.rankingLabel(s);
        return r.isNotEmpty ? '$n · $r' : n;
      }
      final member = _members.where((m) => m['user_id'] == userId).firstOrNull;
      if (member != null) return _memberName(member);
      return userId.length > 8 ? '${userId.substring(0, 8)}…' : userId;
    }
    return '–';
  }

  String _availStatusForUser(String userId) {
    for (final a in _availability) {
      if (a['user_id'] == userId) return a['status'] as String? ?? '–';
    }
    return '–';
  }

  String _roleTag(Map<String, dynamic> member) {
    final role = member['role'] as String?;
    if (role == 'captain') return ' (Captain)';
    return '';
  }

  String _rankingStr(String userId) {
    if (_claimedMap.containsKey(userId)) {
      return TeamPlayerService.rankingLabel(_claimedMap[userId]!);
    }
    return '';
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  // ── Tab labels for segment tabs ──
  static const _tabLabels = [
    'Übersicht',
    'Aufstellung',
    'Mehr',
  ];

  @override
  Widget build(BuildContext context) {
    final m = _match;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: 'vs ${m['opponent'] ?? '?'}',
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          if (!_loading && _isAdmin)
            PopupMenuButton<String>(
              popUpAnimationStyle: CsMotion.dialog,
              onSelected: (value) {
                if (value == 'edit') _editMatch();
                if (value == 'delete') _deleteMatch();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18, color: CsColors.gray900),
                      SizedBox(width: 8),
                      Text('Bearbeiten'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: CsColors.error),
                      SizedBox(width: 8),
                      Text('Löschen'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? _buildLoadingSkeleton()
          : Column(
              children: [
                // ── Segment tabs ──
                CsSegmentTabs(
                  labels: _tabLabels,
                  selectedIndex: _tabIndex,
                  onChanged: (i) => setState(() => _tabIndex = i),
                ),
                // ── Tab content ──
                Expanded(
                  child: AnimatedSwitcher(
                    duration: CsDurations.normal,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _buildTabContent(_tabIndex),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabContent(int index) {
    return switch (index) {
      0 => _buildOverviewTab(),
      1 => _buildLineupTab(),
      2 => _buildMoreTab(),
      _ => const SizedBox.shrink(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 0 — Overview
  // ═══════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    final m = _match;
    final isHome = m['is_home'] == true;
    final matchAt = DateTime.tryParse(m['match_at'] ?? '')?.toLocal();
    final dateStr = matchAt != null
        ? '${matchAt.day.toString().padLeft(2, '0')}.'
              '${matchAt.month.toString().padLeft(2, '0')}.'
              '${matchAt.year}'
        : '–';
    final timeStr = matchAt != null
        ? '${matchAt.hour.toString().padLeft(2, '0')}:'
              '${matchAt.minute.toString().padLeft(2, '0')}'
        : '';

    int yes = 0, no = 0, maybe = 0;
    for (final a in _availability) {
      switch (a['status']) {
        case 'yes':
          yes++;
        case 'no':
          no++;
        case 'maybe':
          maybe++;
      }
    }
    final noResponse = _members.length - yes - no - maybe;
    final total = _members.length;

    return ListView(
      key: const ValueKey('tab_overview'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Match info card ──
        CsAnimatedEntrance(
          child: CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sports_tennis, color: CsColors.gray900, size: 20),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: CsColors.black,
                        borderRadius: BorderRadius.circular(CsRadii.full),
                      ),
                      child: Text(
                        isHome ? 'Heim' : 'Auswärts',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CsColors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  m['opponent'] ?? '?',
                  style: CsTextStyles.titleMedium.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 8),
                _cardInfoRow(Icons.calendar_today, '$dateStr  $timeStr'),
                if (m['location'] != null &&
                    (m['location'] as String).isNotEmpty)
                  _cardInfoRow(Icons.location_on, m['location'] as String),
                if (m['note'] != null && (m['note'] as String).isNotEmpty)
                  _cardInfoRow(Icons.notes, m['note'] as String),
                const SizedBox(height: 10),
                CsProgressRow(
                  label: '$yes von $total zugesagt',
                  value: '$yes / $total',
                  progress: total > 0 ? yes / total : 0,
                  color: CsColors.emerald,
                  onDark: false,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── My availability ──
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 80),
          child: CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meine Verfügbarkeit',
                  style: CsTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _availButton('yes', 'Zugesagt', CsColors.success, Icons.check_circle_outline),
                    const SizedBox(width: 6),
                    _availButton('no', 'Abgesagt', CsColors.error, Icons.cancel_outlined),
                    const SizedBox(width: 6),
                    _availButton(
                      'maybe',
                      'Unsicher',
                      CsColors.warning,
                      Icons.help_outline,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Availability summary card ──
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 120),
          child: CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verfügbarkeiten',
                  style: CsTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _neutralCount(Icons.check_circle_outline, yes),
                    const SizedBox(width: 12),
                    _neutralCount(Icons.cancel_outlined, no),
                    const SizedBox(width: 12),
                    _neutralCount(Icons.help_outline, maybe),
                    const SizedBox(width: 12),
                    _neutralCount(Icons.remove_circle_outline, noResponse),
                  ],
                ),
                const SizedBox(height: 10),
                CsProgressRow(
                  label: '${yes + no + maybe} von $total haben geantwortet',
                  value: '${yes + no + maybe} / $total',
                  progress: total > 0 ? (yes + no + maybe) / total : 0,
                  color: CsColors.emerald,
                  onDark: false,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Player status list ──
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 160),
          child: CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Verfügbarkeiten der Spieler',
                    style: CsTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: CsColors.gray900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ..._members.asMap().entries.map((entry) {
                  return _buildPlayerStatusTile(entry.value);
                }),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── Ersatz section (moved from "Mehr" tab) ──
        _sectionHeader(Icons.swap_horiz, 'Ersatz'),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 200),
          child: (_myPendingSubRequests.isNotEmpty || _subRequests.isNotEmpty)
              ? _buildSubRequestSection()
              : _compactEmptyState('Keine Ersatzanfragen vorhanden. Bei Absagen kannst du hier Ersatz anfragen.'),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 1 — Lineup
  // ═══════════════════════════════════════════════════════════

  Widget _buildLineupTab() {
    final lineupStatus = _lineup?['status'] as String?;
    return ListView(
      key: const ValueKey('tab_lineup'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        CsAnimatedEntrance(
          child: _buildLineupSection(lineupStatus),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 2 — Mehr (Fahrten / Essen / Spesen)
  // ═══════════════════════════════════════════════════════════

  Widget _buildMoreTab() {
    return ListView(
      key: const ValueKey('tab_more'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Section: Fahrten ──
        _sectionHeader(Icons.directions_car, 'Fahrten'),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 60),
          child: _buildCarpoolSection(),
        ),

        const SizedBox(height: 14),

        // ── Section: Essen ──
        _sectionHeader(Icons.restaurant, 'Essen'),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 120),
          child: _buildDinnerSection(),
        ),

        const SizedBox(height: 14),

        // ── Section: Spesen ──
        _sectionHeader(Icons.payments, 'Spesen'),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 180),
          child: _buildExpensesSection(),
        ),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CsColors.gray500),
          const SizedBox(width: 8),
          Text(
            label,
            style: CsTextStyles.titleSmall.copyWith(
              color: CsColors.gray700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CsSkeletonMatchHeader(),
          const SizedBox(height: 14),
          const CsSkeletonCard(),
          const SizedBox(height: 14),
          const CsSkeletonSection(itemCount: 4),
        ],
      ),
    );
  }

  Widget _compactEmptyState(String text) {
    return CsLightCard(
      color: CsColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: CsColors.gray400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: CsTextStyles.bodySmall.copyWith(
                color: CsColors.gray500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Aufstellung section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildLineupSection(String? lineupStatus) {
    final ordered = _orderedSlots;
    final starters = ordered.where((s) => s['slot_type'] == 'starter').toList();
    final reserves = ordered.where((s) => s['slot_type'] == 'reserve').toList();

    final isPublished = lineupStatus == 'published';
    final isDraft = lineupStatus == 'draft';
    final totalNeeded = _starterCount + _reserveCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main lineup card ──
        CsCard(
          backgroundColor: CsColors.white,
          borderColor: CsColors.gray200,
          boxShadow: CsShadows.soft,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──
              Row(
                children: [
                  Icon(Icons.format_list_numbered, color: CsColors.gray900, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aufstellung',
                          style: CsTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: CsColors.gray900,
                          ),
                        ),
                        if (lineupStatus != null)
                          Text(
                            isDraft ? 'Entwurf' : 'Veröffentlicht',
                            style: CsTextStyles.bodySmall.copyWith(
                              fontSize: 12,
                              color: CsColors.gray500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (lineupStatus != null) _lineupStatusBadge(lineupStatus),
                ],
              ),

              if (_lineupSlots.isNotEmpty) ...[
                const SizedBox(height: 10),
                CsProgressRow(
                  label: (starters.length + reserves.length) >= totalNeeded
                      ? 'Alle Plätze besetzt'
                      : '${totalNeeded - (starters.length + reserves.length)} ${(totalNeeded - (starters.length + reserves.length)) == 1 ? 'Platz' : 'Plätze'} frei',
                  value: '${starters.length + reserves.length} / $totalNeeded',
                  progress: totalNeeded > 0
                      ? (starters.length + reserves.length) / totalNeeded
                      : 0,
                  color: CsColors.emerald,
                  onDark: false,
                ),
              ],

              if (_isAdmin) ...[
                const SizedBox(height: 12),
                CsPrimaryButton(
                  onPressed: _lineupGenerating ? null : _generateLineup,
                  loading: _lineupGenerating,
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: _lineupSlots.isEmpty ? 'Generieren' : 'Neu generieren',
                ),
              ],
            ],
          ),
        ),

        // ── Content ──
        if (_lineupSlots.isEmpty) ...[
          const SizedBox(height: 8),
          if (!_isAdmin)
            CsLightCard(
              color: CsColors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: CsColors.gray400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Noch keine Aufstellung vorhanden.',
                      style: CsTextStyles.bodySmall.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            CsLightCard(
              color: CsColors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: CsColors.gray400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Noch keine Aufstellung vorhanden.\n'
                      'Tippe auf „Generieren", um eine zu erstellen.',
                      style: CsTextStyles.bodySmall.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ] else ...[
          if (!_isAdmin && isDraft) ...[
            const SizedBox(height: 8),
            _premiumBanner(
              icon: Icons.hourglass_top,
              text: 'Captain erstellt gerade die Aufstellung …',
              color: CsColors.warning,
            ),
          ] else ...[
            if (isPublished) ...[
              const SizedBox(height: 8),
              _premiumBanner(
                icon: Icons.auto_mode,
                text:
                    'Ersatzkette aktiv: Bei Absage rückt der nächste Ersatz automatisch nach.',
                color: CsColors.info,
              ),
            ],

            if (_isAdmin && _lineupViolations.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildViolationBanner(),
            ],

            if (_isAdmin && isDraft) ...[
              const SizedBox(height: 8),
              _buildReorderableSlots(ordered, starters.length, reserves.length),
            ] else ...[
              const SizedBox(height: 8),
              CsCard(
                backgroundColor: CsColors.white,
                borderColor: CsColors.gray200,
                boxShadow: CsShadows.soft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Starter (${starters.length})',
                        style: CsTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: CsColors.gray900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(starters.length, (i) {
                      return _buildSlotTile(starters[i], i, ordered.length);
                    }),
                    if (reserves.isNotEmpty) ...[
                      Divider(
                        color: CsColors.gray200,
                        height: 16,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Ersatz (${reserves.length})',
                          style: CsTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: CsColors.gray900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...List.generate(reserves.length, (j) {
                        final linearIdx = starters.length + j;
                        return _buildSlotTile(
                          reserves[j],
                          linearIdx,
                          ordered.length,
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],

            if (_isAdmin && isDraft) ...[
              const SizedBox(height: 12),
              CsPrimaryButton(
                onPressed: _lineupPublishing ? null : _publishLineup,
                loading: _lineupPublishing,
                icon: const Icon(Icons.send, size: 18),
                label: 'Info an Team senden',
              ),
            ],

            if (isPublished && _isAdmin) ...[
              const SizedBox(height: 12),
              _premiumBanner(
                icon: Icons.check_circle,
                text:
                    'Aufstellung veröffentlicht. Absagen lösen automatisches Nachrücken aus.',
                color: CsColors.success,
              ),
            ],
          ],
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Rule-violation warning banner
  // ═══════════════════════════════════════════════════════════

  Widget _buildViolationBanner() {
    final count = _lineupViolations.length;
    final title = count == 1
        ? '⚠️ 1 Regelverstoss erkannt'
        : '⚠️ $count Regelverstösse erkannt';

    return CsLightCard(
      color: CsColors.warning.withValues(alpha: 0.08),
      border: Border.all(color: CsColors.warning.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: CsColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: CsTextStyles.labelLarge.copyWith(
                    color: CsColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...(_lineupViolations.length <= 5
                  ? _lineupViolations
                  : _lineupViolations.take(5))
              .map(
                (v) => Padding(
                  padding: const EdgeInsets.only(left: 28, bottom: 2),
                  child: Text(
                    '• ${v.message}',
                    style: CsTextStyles.bodySmall.copyWith(
                      color: CsColors.warning,
                    ),
                  ),
                ),
              ),
          if (_lineupViolations.length > 5)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                '… und ${_lineupViolations.length - 5} weitere',
                style: CsTextStyles.labelSmall.copyWith(
                  fontStyle: FontStyle.italic,
                  color: CsColors.warning,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              'Veröffentlichung trotzdem möglich.',
              style: CsTextStyles.labelSmall.copyWith(
                fontStyle: FontStyle.italic,
                color: CsColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Slot tile (with availability chip, lock, up/down arrows)
  // ═══════════════════════════════════════════════════════════

  Widget _buildSlotTile(
    Map<String, dynamic> slot,
    int linearIndex,
    int totalCount,
  ) {
    final pos = slot['position'] as int;
    final slotType = slot['slot_type'] as String;
    final userId = slot['user_id'] as String?;
    final isMe = userId == _supabase.auth.currentUser?.id;
    final isFirst = linearIndex == 0;
    final isLast = linearIndex == totalCount - 1;
    final isDraft = _lineup?['status'] == 'draft';
    final isPublished = _lineup?['status'] == 'published';
    final isLocked = slot['locked'] == true;

    final avail = userId != null ? _availStatusForUser(userId) : '–';
    final posColor = slotType == 'starter' ? CsColors.info : CsColors.warning;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: posColor.withValues(alpha: 0.15),
        child: Text(
          '$pos',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: posColor,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _slotUserName(slot),
              style: TextStyle(
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (userId != null) ...[const SizedBox(width: 4), _availChip(avail)],
          if (_isAdmin && isPublished) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: () => _toggleLock(slot),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  isLocked ? Icons.lock : Icons.lock_open,
                  size: 16,
                  color: isLocked
                      ? CsColors.error.withValues(alpha: 0.7)
                      : CsColors.gray400,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: isMe
          ? Text(
              slotType == 'starter' ? 'Du · Starter' : 'Du · Ersatz',
              style: CsTextStyles.labelSmall.copyWith(color: CsColors.info),
            )
          : null,
      trailing: (_isAdmin && isDraft)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_upward,
                    size: 18,
                    color: isFirst ? CsColors.gray200 : null,
                  ),
                  onPressed: isFirst ? null : () => _moveUp(linearIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.arrow_downward,
                    size: 18,
                    color: isLast ? CsColors.gray200 : null,
                  ),
                  onPressed: isLast ? null : () => _moveDown(linearIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Reorderable slots list (admin + draft) – uses LineupReorderList
  // ═══════════════════════════════════════════════════════════

  Widget _buildReorderableSlots(
    List<Map<String, dynamic>> ordered,
    int starterCount,
    int reserveCount,
  ) {
    final lineupStatus = _lineup?['status'] as String?;
    final isPublished = lineupStatus == 'published';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LineupReorderList(
          items: ordered,
          starterCount: starterCount,
          canReorder: _canReorderLineup,
          onPersistReorder: _onPersistReorder,
          onReorderComplete: _onReorderComplete,
          itemBuilder: (context, slot, index) {
            return _buildReorderSlotContent(slot, index);
          },
        ),

        if (_isAdmin && !_canReorderLineup && _lineupSlots.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            isPublished
                ? 'Aufstellung ist veröffentlicht – Reihenfolge kann nicht '
                      'mehr geändert werden.'
                : _lineupGenerating
                ? 'Aufstellung wird generiert …'
                : _lineupPublishing
                ? 'Aufstellung wird veröffentlicht …'
                : 'Reihenfolge ändern ist momentan nicht möglich.',
            style: CsTextStyles.bodySmall.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _buildReorderSlotContent(Map<String, dynamic> slot, int index) {
    final pos = slot['position'] as int;
    final slotType = slot['slot_type'] as String;
    final userId = slot['user_id'] as String?;
    final isMe = userId == _supabase.auth.currentUser?.id;
    final avail = userId != null ? _availStatusForUser(userId) : '–';
    final posColor = slotType == 'starter' ? CsColors.info : CsColors.warning;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(right: 12),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: posColor.withValues(alpha: 0.15),
        child: Text(
          '$pos',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: posColor,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _slotUserName(slot),
              style: TextStyle(
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (userId != null) ...[const SizedBox(width: 4), _availChip(avail)],
        ],
      ),
      subtitle: isMe
          ? Text(
              slotType == 'starter' ? 'Du · Starter' : 'Du · Ersatz',
              style: CsTextStyles.labelSmall.copyWith(color: CsColors.info),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Carpool section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildCarpoolSection() {
    final uid = _supabase.auth.currentUser?.id;
    final hasMyOffer =
        uid != null && _carpoolOffers.any((o) => o.driverUserId == uid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header card with CTA ──
        if (!hasMyOffer)
          CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fahrgemeinschaften',
                  style: CsTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 10),
                CsPrimaryButton(
                  onPressed: () => _showCarpoolOfferDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: 'Ich fahre',
                ),
              ],
            ),
          ),

        if (_carpoolOffers.isEmpty && hasMyOffer)
          _compactEmptyState('Noch keine Fahrgemeinschaften vorhanden.'),

        if (_carpoolOffers.isEmpty && !hasMyOffer)
          _compactEmptyState('Noch keine Fahrgemeinschaften. Biete eine Mitfahrgelegenheit an.'),

        // ── Offer accordion cards ──
        ..._carpoolOffers.map((offer) {
          final isDriver = offer.driverUserId == uid;
          final isPassenger = uid != null && offer.hasPassenger(uid);
          final canJoin = !isDriver && !isPassenger && !offer.isFull;
          final canLeave = isPassenger;
          final isExpanded = _expandedCarpoolOffers.contains(offer.id);
          final progress =
              offer.seatsTotal > 0 ? offer.seatsTaken / offer.seatsTotal : 0.0;

          return CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: EdgeInsets.zero,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCarpoolOffers.remove(offer.id);
                } else {
                  _expandedCarpoolOffers.add(offer.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Collapsed row ──
                  Row(
                    children: [
                      _userAvatar(offer.driverUserId, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_playerNameForUserId(offer.driverUserId)}${isDriver ? ' (du)' : ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: CsColors.gray900,
                              ),
                            ),
                            if (offer.startLocation != null &&
                                offer.startLocation!.isNotEmpty ||
                                offer.departAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  [
                                    if (offer.startLocation != null &&
                                        offer.startLocation!.isNotEmpty)
                                      offer.startLocation!,
                                    if (offer.departAt != null)
                                      _formatDepartAt(offer.departAt!),
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CsColors.gray500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 22,
                          color: CsColors.gray900,
                        ),
                      ),
                    ],
                  ),

                  // ── Progress bar (seats) ──
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 6,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: CsColors.gray200,
                        valueColor: AlwaysStoppedAnimation<Color>(CsColors.emerald),
                      ),
                    ),
                  ),

                  // ── Expanded content ──
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (offer.note != null && offer.note!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _iconTextRow(Icons.notes, offer.note!),
                        ],

                        // ── Passengers ──
                        if (offer.passengers.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ...offer.passengers.map((p) {
                            final pName = _playerNameForUserId(p.userId);
                            final isMe = p.userId == uid;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  _userAvatar(p.userId, radius: 12),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      pName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isMe
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: CsColors.gray900,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.person,
                                    size: 14,
                                    color: CsColors.gray400,
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],

                        // ── Action row ──
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (canJoin)
                              FilledButton.tonalIcon(
                                onPressed: () => _joinCarpool(offer.id),
                                icon: const Icon(Icons.person_add, size: 16),
                                label: const Text('Mitfahren'),
                              ),
                            if (canLeave)
                              OutlinedButton.icon(
                                onPressed: () => _leaveCarpool(offer.id),
                                icon: const Icon(Icons.person_remove, size: 16),
                                label: const Text('Aussteigen'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: CsColors.error,
                                ),
                              ),
                            if (isDriver) ...[
                              const Spacer(),
                              IconButton(
                                onPressed: () => _showCarpoolOfferDialog(
                                    existingOffer: offer),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: 'Bearbeiten',
                                style: IconButton.styleFrom(
                                  foregroundColor: CsColors.gray900,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteCarpool(offer.id),
                                icon: const Icon(
                                    Icons.delete_outline, size: 20),
                                tooltip: 'Löschen',
                                style: IconButton.styleFrom(
                                  foregroundColor: CsColors.gray900,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    crossFadeState: isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    sizeCurve: Curves.easeOut,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _formatDepartAt(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$d.$mo. um $h:$m';
  }

  // ── Carpool actions ──

  Future<void> _joinCarpool(String offerId) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('CARPOOL_JOIN_TAP: offerId=$offerId uid=$uid');
    try {
      await CarpoolService.join(offerId);
      debugPrint('CARPOOL_JOIN_TAP: RPC success, reloading…');
      await _reloadCarpool(rethrow_: true);
      if (!mounted) return;
      debugPrint(
        'CARPOOL_JOIN_TAP: reload done, offers=${_carpoolOffers.length}',
      );
      CsToast.success(context, 'Du fährst mit');
    } catch (e) {
      debugPrint('CARPOOL_JOIN_TAP ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, 'Mitfahren konnte nicht gespeichert werden.');
    }
  }

  Future<void> _leaveCarpool(String offerId) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('CARPOOL_LEAVE_TAP: offerId=$offerId uid=$uid');
    try {
      await CarpoolService.leave(offerId);
      debugPrint('CARPOOL_LEAVE_TAP: RPC success, reloading…');
      await _reloadCarpool(rethrow_: true);
      if (!mounted) return;
      debugPrint(
        'CARPOOL_LEAVE_TAP: reload done, offers=${_carpoolOffers.length}',
      );
      CsToast.success(context, 'Ausgestiegen');
    } catch (e) {
      debugPrint('CARPOOL_LEAVE_TAP ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, 'Aussteigen konnte nicht gespeichert werden.');
    }
  }

  Future<void> _deleteCarpool(String offerId) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: 'Fahrgemeinschaft löschen?',
        ctaLabel: 'Löschen',
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Abbrechen',
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_forever, size: 40, color: CsColors.error),
            const SizedBox(height: 12),
            Text(
              'Alle Mitfahrer werden entfernt.',
              style: CsTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await CarpoolService.deleteOffer(offerId);
      await _reloadCarpool();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  Future<void> _showCarpoolOfferDialog({CarpoolOffer? existingOffer}) async {
    int seats = existingOffer?.seatsTotal ?? 4;
    final locationCtrl = TextEditingController(
      text: existingOffer?.startLocation ?? '',
    );
    final noteCtrl = TextEditingController(text: existingOffer?.note ?? '');
    TimeOfDay? departTime = existingOffer?.departAt != null
        ? TimeOfDay.fromDateTime(existingOffer!.departAt!.toLocal())
        : null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return CsBottomSheetForm(
            title: existingOffer != null
                ? 'Fahrgemeinschaft bearbeiten'
                : 'Ich fahre',
            ctaLabel: 'Speichern',
            onCta: () => Navigator.pop(ctx, true),
            secondaryLabel: 'Abbrechen',
            onSecondary: () => Navigator.pop(ctx, false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wie viele Plätze bietest du an?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: seats > 1 ? () => setD(() => seats--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$seats',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: seats < 9 ? () => setD(() => seats++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Abfahrtsort',
                    hintText: 'z.B. Bahnhof Bern',
                    prefixIcon: Icon(Icons.location_on, size: 18),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        departTime != null
                            ? 'Abfahrt: ${departTime!.format(ctx)}'
                            : 'Abfahrtszeit (optional)',
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: departTime ?? TimeOfDay.now(),
                        );
                        if (t != null) setD(() => departTime = t);
                      },
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      tooltip: departTime != null ? 'Ändern' : 'Setzen',
                    ),
                    if (departTime != null)
                      IconButton(
                        onPressed: () => setD(() => departTime = null),
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Entfernen',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notiz (optional)',
                    hintText: 'z.B. Treffpunkt Parkplatz',
                    prefixIcon: Icon(Icons.notes, size: 18),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true) return;

    DateTime? departAt;
    if (departTime != null) {
      final matchAt = DateTime.tryParse(_match['match_at'] as String? ?? '');
      if (matchAt != null) {
        departAt = DateTime(
          matchAt.year,
          matchAt.month,
          matchAt.day,
          departTime!.hour,
          departTime!.minute,
        );
      }
    }

    try {
      final offerId = await CarpoolService.upsertOffer(
        teamId: widget.teamId,
        matchId: widget.matchId,
        seatsTotal: seats,
        startLocation: locationCtrl.text.trim().isEmpty
            ? null
            : locationCtrl.text.trim(),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        departAt: departAt,
      );
      debugPrint('CARPOOL_UI: upsert returned offerId=$offerId – refetching…');

      await _reloadCarpool(rethrow_: true);
      if (!mounted) return;

      final visible = _carpoolOffers.any((o) => o.id == offerId);
      debugPrint(
        'CARPOOL_UI: post-refetch offers=${_carpoolOffers.length}, '
        'offerId=$offerId visible=$visible',
      );

      if (visible) {
        CsToast.success(context, 'Fahrgemeinschaft gespeichert');
      } else {
        CsToast.info(context,
          'Fahrgemeinschaft erstellt. Bitte lade die Seite neu.',
        );
      }
    } catch (e) {
      debugPrint('CARPOOL_UI CREATE ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Dinner RSVP section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildDinnerSection() {
    final uid = _supabase.auth.currentUser?.id;

    final yesCount = _dinnerRsvps.where((r) => r.status == 'yes').length;
    final noCount = _dinnerRsvps.where((r) => r.status == 'no').length;
    final maybeCount = _dinnerRsvps.where((r) => r.status == 'maybe').length;
    final answered = yesCount + noCount + maybeCount;
    final totalMembers = _members.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main Essen card ──
        CsCard(
          backgroundColor: CsColors.white,
          borderColor: CsColors.gray200,
          boxShadow: CsShadows.soft,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Icon(Icons.restaurant_outlined, size: 18, color: CsColors.gray900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Essen',
                      style: CsTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CsColors.gray900,
                      ),
                    ),
                  ),
                ],
              ),

              // Counts row
              const SizedBox(height: 10),
              Row(
                children: [
                  _neutralCount(Icons.check_circle_outline, yesCount),
                  const SizedBox(width: 12),
                  _neutralCount(Icons.cancel_outlined, noCount),
                  const SizedBox(width: 12),
                  _neutralCount(Icons.help_outline, maybeCount),
                  const Spacer(),
                  Text(
                    '$answered von $totalMembers',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CsColors.gray900,
                    ),
                  ),
                ],
              ),

              // Progress bar
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: totalMembers > 0 ? answered / totalMembers : 0,
                    backgroundColor: CsColors.gray200,
                    valueColor: const AlwaysStoppedAnimation<Color>(CsColors.emerald),
                  ),
                ),
              ),

              // Inline RSVP buttons ("Deine Zusage")
              const SizedBox(height: 14),
              Text(
                'Deine Zusage',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CsColors.gray500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _dinnerButton('Ja', 'yes', Icons.check_circle_outline, CsColors.success),
                  const SizedBox(width: 6),
                  _dinnerButton('Nein', 'no', Icons.cancel_outlined, CsColors.error),
                  const SizedBox(width: 6),
                  _dinnerButton('Unsicher', 'maybe', Icons.help_outline, CsColors.warning),
                ],
              ),

              // Note field
              if (_myDinnerStatus == 'yes' || _myDinnerStatus == 'maybe') ...[
                const SizedBox(height: 10),
                _buildDinnerNoteField(),
              ],
            ],
          ),
        ),

        // ── Teilnehmer accordion ──
        if (_dinnerRsvps.isNotEmpty) ...[
          const SizedBox(height: 6),
          CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200,
            boxShadow: CsShadows.soft,
            padding: EdgeInsets.zero,
            onTap: () => setState(() => _dinnerExpanded = !_dinnerExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collapsed header row
                  Row(
                    children: [
                      Icon(Icons.group_outlined, size: 18, color: CsColors.gray500),
                      const SizedBox(width: 8),
                      Text(
                        'Teilnehmer',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: CsColors.gray900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_dinnerRsvps.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: CsColors.gray500,
                        ),
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _dinnerExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 22,
                          color: CsColors.gray900,
                        ),
                      ),
                    ],
                  ),

                  // Expanded list
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: List.generate(_dinnerRsvps.length, (i) {
                          final rsvp = _dinnerRsvps[i];
                          final name = _playerNameForUserId(rsvp.userId);
                          final isMe = rsvp.userId == uid;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                _userAvatar(rsvp.userId, radius: 14),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$name${isMe ? ' (du)' : ''}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isMe
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: CsColors.gray900,
                                        ),
                                      ),
                                      if (rsvp.note != null &&
                                          rsvp.note!.isNotEmpty)
                                        Text(
                                          rsvp.note!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: CsColors.gray500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                _dinnerStatusIcon(rsvp.status),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                    crossFadeState: _dinnerExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    sizeCurve: Curves.easeOut,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dinnerButton(
      String label, String status, IconData icon, Color color) {
    final isSelected = _myDinnerStatus == status;
    final isUpdating = _dinnerUpdating && isSelected;

    return Expanded(
      child: AnimatedScale(
        scale: isUpdating ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 42,
          decoration: BoxDecoration(
            color: CsColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFDADDE3),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _dinnerUpdating ? null : () => _setDinnerRsvp(status),
              child: Opacity(
                opacity: isUpdating ? 0.5 : 1.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111111),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDinnerNoteField() {
    final uid = _supabase.auth.currentUser?.id;
    final myRsvp = _dinnerRsvps.where((r) => r.userId == uid).firstOrNull;
    final ctrl = TextEditingController(text: myRsvp?.note ?? '');

    return SizedBox(
      height: 44,
      child: TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 13, color: CsColors.gray900),
        decoration: InputDecoration(
          hintText: 'Notiz (z.B. "komme später")',
          hintStyle: TextStyle(fontSize: 13, color: CsColors.gray400),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: CsColors.gray200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: CsColors.gray200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: CsColors.gray400),
          ),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) {
          if (_myDinnerStatus != null) {
            _setDinnerRsvp(_myDinnerStatus!, note: value);
          }
        },
      ),
    );
  }

  Future<void> _setDinnerRsvp(String status, {String? note}) async {
    if (_dinnerUpdating) return;
    final oldStatus = _myDinnerStatus;

    // Haptic feedback.
    HapticFeedback.selectionClick();

    // Optimistic UI update.
    setState(() {
      _myDinnerStatus = status;
      _dinnerUpdating = true;
    });

    try {
      final uid = _supabase.auth.currentUser?.id;
      final existingRsvp =
          _dinnerRsvps.where((r) => r.userId == uid).firstOrNull;
      final effectiveNote = note ?? existingRsvp?.note;

      await DinnerService.upsertRsvp(
        matchId: widget.matchId,
        status: status,
        note: effectiveNote,
      );
      await _reloadDinner();
      if (!mounted) return;
      setState(() => _dinnerUpdating = false);
    } catch (e) {
      debugPrint('DINNER_UPSERT ERROR: $e');
      if (!mounted) return;
      setState(() {
        _myDinnerStatus = oldStatus;
        _dinnerUpdating = false;
      });
      CsToast.error(context, 'Speichern nicht möglich. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Expenses section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildExpensesSection() {
    final uid = _supabase.auth.currentUser?.id;

    final totalCents = _expenses.fold<int>(0, (sum, e) => sum + e.amountCents);
    final totalCHF = totalCents / 100.0;
    final totalOpenCents = _expenses.fold<int>(
      0,
      (sum, e) => sum + e.openCents,
    );
    final totalPaidCents = totalCents - totalOpenCents;
    final memberCount = _expenses.isNotEmpty
        ? _expenses.first.shareCount
        : _members.length;
    final perPersonCHF = memberCount > 0 ? totalCHF / memberCount : 0.0;

    final dinnerYesCount = _dinnerRsvps.where((r) => r.status == 'yes').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary card ──
        CsCard(
          backgroundColor: CsColors.white,
          borderColor: CsColors.gray200,
          boxShadow: CsShadows.soft,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Spesen',
                      style: CsTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CsColors.gray900,
                      ),
                    ),
                  ),
                  if (_expenses.isNotEmpty)
                    CsStatusChip(
                      label: 'CHF ${totalCHF.toStringAsFixed(2)}',
                      variant: CsChipVariant.amber,
                    ),
                ],
              ),
              if (_expenses.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total', style: CsTextStyles.bodySmall.copyWith(color: CsColors.gray500)),
                        Text(
                          'CHF ${totalCHF.toStringAsFixed(2)}',
                          style: CsTextStyles.titleMedium.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: CsColors.gray900,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Pro Kopf ($memberCount Pers.)',
                          style: CsTextStyles.bodySmall.copyWith(color: CsColors.gray500),
                        ),
                        Text(
                          'CHF ${perPersonCHF.toStringAsFixed(2)}',
                          style: CsTextStyles.titleMedium.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: CsColors.gray900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CsProgressRow(
                  label: 'Bezahlt',
                  value:
                      'CHF ${(totalPaidCents / 100).toStringAsFixed(2)} / ${totalCHF.toStringAsFixed(2)}',
                  progress: totalCents > 0 ? totalPaidCents / totalCents : 0,
                  color: CsColors.emerald,
                  onDark: false,
                ),
              ],
              const SizedBox(height: 10),
              CsPrimaryButton(
                onPressed: dinnerYesCount > 0
                    ? () => _showCreateExpenseDialog()
                    : () {
                        CsToast.info(context,
                          'Zuerst unter „Essen" zusagen, bevor Spesen erfasst werden können.',
                        );
                      },
                icon: const Icon(Icons.add, size: 18),
                label: 'Ausgabe hinzufügen',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (_expenses.isEmpty)
          CsLightCard(
            color: CsColors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: CsColors.gray400),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dinnerYesCount > 0
                        ? 'Noch keine Spesen erfasst. Lege eine neue Ausgabe an.'
                        : 'Noch keine Spesen möglich. Zuerst unter „Essen" zusagen.',
                    style: CsTextStyles.bodySmall.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),

        ...List.generate(_expenses.length, (i) {
          final expense = _expenses[i];
          final paidByName = _playerNameForUserId(expense.paidByUserId);
          final isPaidByMe = expense.paidByUserId == uid;

          return CsLightCard(
            color: CsColors.white,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: expense.openCount == 0
                    ? CsColors.success.withValues(alpha: 0.12)
                    : CsColors.warning.withValues(alpha: 0.12),
                child: Icon(
                  expense.openCount == 0 ? Icons.check_circle : Icons.payments,
                  color: expense.openCount == 0
                      ? CsColors.success
                      : CsColors.warning,
                ),
              ),
              title: Text(expense.title, style: CsTextStyles.labelLarge),
              subtitle: Text(
                'Bezahlt von $paidByName${isPaidByMe ? ' (du)' : ''}'
                ' · ${expense.amountFormatted}'
                '${expense.note != null && expense.note!.isNotEmpty ? '\n${expense.note}' : ''}',
                style: CsTextStyles.bodySmall,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${expense.perPersonFormatted}/Pers.',
                    style: CsTextStyles.labelSmall,
                  ),
                  Text(
                    '${expense.paidCount}/${expense.shareCount} bezahlt',
                    style: CsTextStyles.labelSmall.copyWith(
                      color: expense.openCount == 0
                          ? CsColors.success
                          : CsColors.warning,
                    ),
                  ),
                ],
              ),
              children: [
                ...expense.shares.map((share) {
                  final shareName = _playerNameForUserId(share.userId);
                  final isMe = share.userId == uid;
                  final canToggle = isMe || isPaidByMe || _isAdmin;

                  return ListTile(
                    dense: true,
                    leading: _userAvatar(share.userId, radius: 14),
                    title: Text(
                      '$shareName${isMe ? ' (du)' : ''}',
                      style: TextStyle(
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                        decoration: share.isPaid
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      'CHF ${share.shareDouble.toStringAsFixed(2)}'
                      '${share.isPaid ? ' · Bezahlt' : ' · Offen'}',
                      style: CsTextStyles.bodySmall.copyWith(
                        color: share.isPaid
                            ? CsColors.success
                            : CsColors.warning,
                      ),
                    ),
                    trailing: canToggle
                        ? Switch(
                            value: share.isPaid,
                            onChanged: (_) =>
                                _toggleSharePaid(share.id, !share.isPaid),
                          )
                        : Icon(
                            share.isPaid
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: share.isPaid
                                ? CsColors.success
                                : CsColors.gray400,
                            size: 20,
                          ),
                  );
                }),
                if (isPaidByMe)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, right: 8),
                      child: IconButton(
                        onPressed: () => _confirmDeleteExpense(expense),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: CsColors.error,
                        tooltip: 'Ausgabe löschen',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _toggleSharePaid(String shareId, bool paid) async {
    try {
      await ExpenseService.markSharePaid(shareId: shareId, paid: paid);
      await _reloadExpenses();
      if (!mounted) return;
      CsToast.success(context, paid ? 'Als bezahlt markiert' : 'Als offen markiert');
    } catch (e) {
      debugPrint('EXPENSE_TOGGLE_PAID ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  Future<void> _showCreateExpenseDialog() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final dinnerYes = _dinnerRsvps.where((r) => r.status == 'yes').length;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: 'Ausgabe hinzufügen',
        ctaLabel: 'Speichern',
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Abbrechen',
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                hintText: 'z.B. Pizza, Getränke',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Betrag (CHF) *',
                hintText: 'z.B. 45.50',
                prefixText: 'CHF ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                hintText: 'z.B. Restaurant Adler',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Text(
              'Wird gleichmässig auf alle $dinnerYes '
              'Dinner-Teilnehmer (Ja) verteilt.',
              style: CsTextStyles.bodySmall.copyWith(
                color: CsColors.gray500,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final title = titleCtrl.text.trim();
    final amountText = amountCtrl.text.trim().replaceAll(',', '.');
    final note = noteCtrl.text.trim();

    if (title.isEmpty) {
      if (!mounted) return;
      CsToast.info(context, 'Bitte gib einen Titel ein.');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      CsToast.info(context, 'Bitte gib einen gültigen Betrag ein.');
      return;
    }

    try {
      await ExpenseService.createExpenseEqualSplit(
        matchId: widget.matchId,
        title: title,
        amountCHF: amount,
        note: note.isNotEmpty ? note : null,
      );
      await _reloadExpenses();
      if (!mounted) return;
      CsToast.success(context,
        'Ausgabe „$title" (CHF ${amount.toStringAsFixed(2)}) erstellt',
      );
    } catch (e) {
      debugPrint('EXPENSE_CREATE ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  Future<void> _confirmDeleteExpense(Expense expense) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: 'Ausgabe löschen?',
        ctaLabel: 'Löschen',
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Abbrechen',
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_forever, size: 40, color: CsColors.error),
            const SizedBox(height: 12),
            Text(
              '„${expense.title}" (${expense.amountFormatted}) '
              'und alle Anteile werden gelöscht.',
              style: CsTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await ExpenseService.deleteExpense(expense.id);
      await _reloadExpenses();
      if (!mounted) return;
      CsToast.success(context, 'Ausgabe „${expense.title}" gelöscht');
    } catch (e) {
      debugPrint('EXPENSE_DELETE ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, 'Etwas ist schiefgelaufen. Bitte versuche es erneut.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Sub-request section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildSubRequestSection() {
    final pendingCount = _subRequests.where((r) => r['status'] == 'pending').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header card ──
        CsCard(
          backgroundColor: CsColors.white,
          borderColor: CsColors.gray200,
          boxShadow: CsShadows.soft,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ersatzanfragen',
                      style: CsTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CsColors.gray900,
                      ),
                    ),
                  ),
                  if (pendingCount > 0)
                    CsStatusChip(
                      label: '$pendingCount ausstehend',
                      variant: CsChipVariant.amber,
                    ),
                ],
              ),
              if (_subRequests.isNotEmpty) ...[
                const SizedBox(height: 10),
                CsProgressRow(
                  label: 'Ausstehende Anfragen',
                  value: '$pendingCount von ${_subRequests.length}',
                  progress: _subRequests.isNotEmpty
                      ? pendingCount / _subRequests.length
                      : 0,
                  color: CsColors.emerald,
                  onDark: false,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (_myPendingSubRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Du wurdest angefragt:',
              style: CsTextStyles.labelLarge.copyWith(color: CsColors.warning),
            ),
          ),
          ..._myPendingSubRequests.map((req) {
            final originalId = req['original_user_id'] as String? ?? '';
            final originalName = _playerNameForUserId(originalId);
            final actionable = isRequestActionable(req);
            final expiryLabel = expiresInLabel(req);

            return CsLightCard(
              color: actionable
                  ? CsColors.warning.withValues(alpha: 0.08)
                  : CsColors.white,
              border: Border.all(
                color: actionable
                    ? CsColors.warning.withValues(alpha: 0.3)
                    : CsColors.gray200,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  actionable ? Icons.swap_horiz : Icons.timer_off,
                  color: actionable ? CsColors.warning : CsColors.gray400,
                ),
                title: Text('Ersatz für $originalName'),
                subtitle: Text(
                  actionable
                      ? 'Kannst du einspringen?'
                            '${expiryLabel != null ? ' ($expiryLabel)' : ''}'
                      : 'Zeit abgelaufen',
                  style: CsTextStyles.bodySmall.copyWith(
                    color: actionable ? null : CsColors.gray400,
                  ),
                ),
                trailing: actionable
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.check_circle,
                              color: CsColors.success,
                              size: 32,
                            ),
                            tooltip: 'Annehmen',
                            onPressed: () => _respondSubRequest(
                              req['id'] as String,
                              'accepted',
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.cancel,
                              color: CsColors.error,
                              size: 32,
                            ),
                            tooltip: 'Ablehnen',
                            onPressed: () => _respondSubRequest(
                              req['id'] as String,
                              'declined',
                            ),
                          ),
                        ],
                      )
                    : Icon(Icons.block, color: CsColors.gray400, size: 24),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        if (_subRequests.isNotEmpty) ...[
          Text(
            'Anfragen-Verlauf:',
            style: CsTextStyles.bodySmall.copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 4),
          ..._subRequests.map((req) {
            final status = req['status'] as String? ?? '?';
            final originalName = _playerNameForUserId(
              req['original_user_id'] as String? ?? '',
            );
            final subName = _playerNameForUserId(
              req['substitute_user_id'] as String? ?? '',
            );

            final effectivelyExpired =
                status == 'pending' && isRequestExpired(req);
            final displayStatus = effectivelyExpired ? 'expired' : status;

            final icon = switch (displayStatus) {
              'pending' => Icons.hourglass_top,
              'accepted' => Icons.check_circle,
              'declined' => Icons.cancel,
              'expired' => Icons.timer_off,
              _ => Icons.help_outline,
            };
            final color = switch (displayStatus) {
              'pending' => CsColors.warning,
              'accepted' => CsColors.success,
              'declined' => CsColors.error,
              'expired' => CsColors.gray400,
              _ => CsColors.gray400,
            };

            final expiryHint = (displayStatus == 'pending')
                ? expiresInLabel(req)
                : null;

            return ListTile(
              dense: true,
              leading: Icon(icon, color: color, size: 20),
              title: Text('$subName für $originalName'),
              subtitle: expiryHint != null
                  ? Text(
                      expiryHint,
                      style: CsTextStyles.labelSmall.copyWith(
                        color: CsColors.warning,
                      ),
                    )
                  : null,
              trailing: CsStatusChip(
                label: switch (displayStatus) {
                  'pending' => 'Wartet auf Antwort',
                  'accepted' => 'Angenommen',
                  'declined' => 'Abgelehnt',
                  'expired' => 'Zeit abgelaufen',
                  _ => displayStatus,
                },
                variant: switch (displayStatus) {
                  'pending' => CsChipVariant.amber,
                  'accepted' => CsChipVariant.success,
                  'declined' => CsChipVariant.error,
                  _ => CsChipVariant.neutral,
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Resolve a user_id to a display name.
  String _playerNameForUserId(String userId) {
    final claimed = _claimedMap[userId];
    if (claimed != null) {
      final name = TeamPlayerService.playerDisplayName(claimed);
      if (name.isNotEmpty && name != '?') return name;
    }
    final profile = _profiles[userId];
    if (profile != null) {
      final dn = profile['display_name'] as String?;
      if (dn != null && dn.isNotEmpty && dn != 'Spieler') return dn;
    }
    final member = _members.where((m) => m['user_id'] == userId).firstOrNull;
    if (member != null) {
      final nick = member['nickname'] as String?;
      if (nick != null && nick.isNotEmpty) return nick;
      final embedded = member['cs_app_profiles'];
      if (embedded is Map<String, dynamic>) {
        final dn = embedded['display_name'] as String?;
        if (dn != null && dn.isNotEmpty && dn != 'Spieler') return dn;
        final email = embedded['email'] as String?;
        if (email != null && email.isNotEmpty) return email.split('@').first;
      }
    }
    return 'Unbekannt';
  }

  // ═══════════════════════════════════════════════════════════
  //  Player status tile (availability list)
  // ═══════════════════════════════════════════════════════════

  Widget _buildPlayerStatusTile(Map<String, dynamic> member) {
    final uid = member['user_id'] as String;
    final status = _availStatusForUser(uid);
    final isMe = uid == _supabase.auth.currentUser?.id;
    final rank = _rankingStr(uid);
    final nameStr = _memberName(member);
    final display = rank.isNotEmpty ? '$nameStr · $rank' : nameStr;

    final isPublished = _lineup?['status'] == 'published';
    final hasPending = _subRequests.any(
      (r) => r['original_user_id'] == uid && r['status'] == 'pending',
    );
    final showSubButton =
        _isAdmin && status == 'no' && isPublished && !hasPending;

    return ListTile(
      dense: true,
      leading: _statusIcon(status),
      title: Text(
        '$display${_roleTag(member)}',
        style: TextStyle(
          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
          color: CsColors.gray900,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        _statusLabel(status),
        style: CsTextStyles.bodySmall.copyWith(fontSize: 12, color: CsColors.gray500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMe) Icon(Icons.person, size: 16, color: CsColors.info),
          if (showSubButton) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _createSubRequest(uid),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Ersatz', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                foregroundColor: CsColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Reusable widget helpers
  // ═══════════════════════════════════════════════════════════

  Widget _lineupStatusBadge(String status) {
    final isDraft = status == 'draft';
    return CsStatusChip(
      label: isDraft ? 'Entwurf' : 'Veröffentlicht',
      variant: isDraft ? CsChipVariant.amber : CsChipVariant.success,
    );
  }

  Widget _availChip(String status) {
    final IconData icon;
    switch (status) {
      case 'yes':
        icon = Icons.check_circle_outline;
      case 'no':
        icon = Icons.cancel_outlined;
      case 'maybe':
        icon = Icons.help_outline;
      default:
        icon = Icons.remove_circle_outline;
    }
    return Icon(icon, size: 16, color: Colors.black54);
  }

  Widget _availButton(String status, String label, Color color, IconData icon) {
    final isSelected = _myStatus == status;
    final isUpdating = _availUpdating && isSelected;
    return Expanded(
      child: AnimatedScale(
        scale: isUpdating ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 44,
          decoration: BoxDecoration(
            color: CsColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFDADDE3),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _availUpdating ? null : () => _setAvailability(status),
              child: Opacity(
                opacity: isUpdating ? 0.5 : 1.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111111),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Icon _statusIcon(String status) {
    switch (status) {
      case 'yes':
        return Icon(Icons.check_circle, color: CsColors.success, size: 20);
      case 'no':
        return Icon(Icons.cancel, color: CsColors.error, size: 20);
      case 'maybe':
        return Icon(Icons.help, color: CsColors.warning, size: 20);
      default:
        return Icon(
          Icons.radio_button_unchecked,
          color: CsColors.gray400,
          size: 20,
        );
    }
  }

  String _statusLabel(String status) {
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

  /// Reusable premium info banner.
  Widget _premiumBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return CsLightCard(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.25)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: CsTextStyles.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Small icon + text row for card info.
  Widget _cardInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: CsColors.gray400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: CsTextStyles.bodySmall.copyWith(
                color: CsColors.gray600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Neutral icon + count row (for availability summaries etc.).
  Widget _neutralCount(IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  /// Dinner status icon (replaces emoji).
  Widget _dinnerStatusIcon(String status) {
    final IconData icon;
    switch (status) {
      case 'yes':
        icon = Icons.check_circle_outline;
      case 'no':
        icon = Icons.cancel_outlined;
      default:
        icon = Icons.help_outline;
    }
    return Icon(icon, size: 18, color: Colors.black54);
  }

  /// Small icon + text row for light cards.
  Widget _iconTextRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: CsColors.gray400),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: CsTextStyles.bodySmall)),
      ],
    );
  }
}
