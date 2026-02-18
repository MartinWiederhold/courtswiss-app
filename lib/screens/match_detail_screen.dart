import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
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

  // ── Auto-promotion state ──
  Map<String, dynamic>? _pendingPromotion; // unconfirmed auto_promotion for me

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
  RealtimeChannel? _lineupStatusChannel;
  RealtimeChannel? _availabilityChannel;

  // ── Generate-dialog defaults (overridden from lineup row if exists) ──
  int _starterCount = 6;
  int _reserveCount = 3;
  bool _includeMaybe = false;

  /// Tab index for segment tabs.
  int _tabIndex = 0;

  /// Live match data (may be updated after edit).
  late Map<String, dynamic> _match;

  late AppLocalizations l10n;

  @override
  void initState() {
    super.initState();
    _match = Map.of(widget.match);
    _load();
    _subscribeLineupChanges();
    _subscribeLineupStatusChanges();
    _subscribeAvailabilityChanges();
    _subscribeCarpoolChanges();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    l10n = AppLocalizations.of(context)!;
  }

  @override
  void dispose() {
    _lineupChannel?.unsubscribe();
    _lineupStatusChannel?.unsubscribe();
    _availabilityChannel?.unsubscribe();
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

  // ═══════════════════════════════════════════════════════════
  //  Realtime: auto-reload when availability changes
  //  (so captain/players see live updates)
  // ═══════════════════════════════════════════════════════════

  void _subscribeAvailabilityChanges() {
    _availabilityChannel = _supabase
        .channel('availability:${widget.matchId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cs_match_availability',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: widget.matchId,
          ),
          callback: (payload) {
            debugPrint('AVAILABILITY_RT: change detected, reloading…');
            _reloadAvailability();
          },
        )
        .subscribe();
  }

  /// Reload only availability data (not the full page).
  Future<void> _reloadAvailability() async {
    try {
      final avail = await MatchService.listAvailability(widget.matchId);
      final uid = _supabase.auth.currentUser?.id;
      String? myStatus;
      for (final a in avail) {
        if (a['user_id'] == uid) {
          myStatus = a['status'] as String?;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _availability = avail;
        _myStatus = myStatus;
      });
    } catch (e) {
      debugPrint('Availability reload error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Realtime: auto-reload when lineup master row changes
  //  (e.g. status draft → published)
  // ═══════════════════════════════════════════════════════════

  void _subscribeLineupStatusChanges() {
    _lineupStatusChannel = _supabase
        .channel('lineup_status:${widget.matchId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cs_match_lineups',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: widget.matchId,
          ),
          callback: (payload) {
            debugPrint('LINEUP_STATUS_RT: lineup row changed, reloading…');
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

      // 7. Check for pending auto-promotion (for the current user)
      Map<String, dynamic>? pendingPromotion;
      try {
        final events = await LineupService.getEvents(widget.matchId);
        for (final ev in events) {
          if (ev['event_type'] == 'auto_promotion' &&
              ev['confirmed_at'] == null) {
            final payload = ev['payload'] as Map<String, dynamic>?;
            if (payload != null && payload['to'] == uid) {
              pendingPromotion = ev;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Lineup events load error: $e');
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
        _pendingPromotion = pendingPromotion;
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
      CsToast.error(context, l10n.genericError);
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
      CsToast.error(context, l10n.genericError);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Auto-promotion confirmation
  // ═══════════════════════════════════════════════════════════

  Future<void> _confirmPromotion() async {
    final eventId = _pendingPromotion?['id'] as String?;
    if (eventId == null) return;
    try {
      await LineupService.confirmPromotion(eventId);
      if (!mounted) return;
      setState(() => _pendingPromotion = null);
      HapticFeedback.mediumImpact();
      CsToast.success(context, 'Teilnahme bestätigt!');
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
            title: l10n.generateLineupTitle,
            ctaLabel: l10n.generateButton,
            onCta: () => Navigator.pop(ctx, true),
            secondaryLabel: l10n.cancel,
            onSecondary: () => Navigator.pop(ctx, false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.lineupGenerateDescription,
                  style: CsTextStyles.bodySmall,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.starterLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                    Expanded(
                      child: Text(
                        l10n.reserveLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                title: Text(l10n.includeMaybeTitle),
                subtitle: Text(l10n.includeMaybeSubtitle),
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
        l10n.lineupCreatedToast('${result['starters']}', '${result['reserves']}'),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
      CsToast.error(context, l10n.genericError);
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
      CsToast.error(context, l10n.genericError);
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
        title: l10n.publishLineupTitle,
        ctaLabel: l10n.publishSendButton,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l10n.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.send, size: 40, color: CsColors.blue),
            const SizedBox(height: 12),
            Text(
              l10n.publishLineupBody,
              style: CsTextStyles.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.publishLineupConfirm,
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
        l10n.lineupPublishedToast('$recipients'),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
        CsToast.success(context, l10n.subRequestSentToast('${result['substitute_name']}'));
      } else {
        CsToast.info(context,
          result['message'] as String? ?? l10n.noSubAvailable,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
            ? l10n.subRequestAcceptedToast
            : l10n.subRequestDeclinedToast;
        CsToast.success(context, msg);
      } else {
        CsToast.error(context,
          result['message'] as String? ?? l10n.somethingWentWrong,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
        title: l10n.deleteMatchTitle,
        ctaLabel: l10n.delete,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l10n.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_forever, size: 40, color: CsColors.error),
            const SizedBox(height: 12),
            Text(
              l10n.deleteMatchBody(_match['opponent'] as String? ?? '?'),
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
      CsToast.success(context, l10n.matchDeleted);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
    if (role == 'captain') return l10n.roleCaptainSuffix;
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
  List<String> get _tabLabels => [
    l10n.matchTabOverview,
    l10n.matchTabLineup,
    l10n.matchTabMore,
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
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 18, color: CsColors.gray900),
                      const SizedBox(width: 8),
                      Text(l10n.editLabel),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline, size: 18, color: CsColors.error),
                      const SizedBox(width: 8),
                      Text(l10n.delete),
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
                        isHome ? l10n.home : l10n.away,
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
                  label: l10n.matchConfirmedProgress('$yes', '$total'),
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
                  l10n.myAvailability,
                  style: CsTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _availButton('yes', l10n.availYes, CsColors.success, Icons.check_circle_outline),
                    const SizedBox(width: 6),
                    _availButton('no', l10n.availNo, CsColors.error, Icons.cancel_outlined),
                    const SizedBox(width: 6),
                    _availButton(
                      'maybe',
                      l10n.availMaybe,
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
                  l10n.availabilitiesTitle,
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
                  label: l10n.respondedProgress('${yes + no + maybe}', '$total'),
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
                    l10n.playerAvailabilities,
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
        _sectionHeader(Icons.swap_horiz, l10n.subRequestSection),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 200),
          child: (_myPendingSubRequests.isNotEmpty || _subRequests.isNotEmpty)
              ? _buildSubRequestSection()
              : _compactEmptyState(l10n.noSubRequests),
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
        if (_pendingPromotion != null) ...[
          _buildPromotionBanner(),
          const SizedBox(height: 8),
        ],
        CsAnimatedEntrance(
          child: _buildLineupSection(lineupStatus),
        ),
      ],
    );
  }

  /// Banner: "Du bist nachgerückt! Bitte bestätige deine Teilnahme."
  Widget _buildPromotionBanner() {
    final payload = _pendingPromotion?['payload'] as Map<String, dynamic>?;
    final absentName = payload?['absent_name'] as String? ?? '?';

    return CsAnimatedEntrance(
      child: Container(
        decoration: BoxDecoration(
          color: CsColors.emerald.withValues(alpha: 0.08),
          border: Border.all(color: CsColors.emerald.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports, size: 22, color: CsColors.emerald),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Du bist nachgerückt!',
                    style: CsTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: CsColors.emerald,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$absentName hat abgesagt. Du spielst jetzt als Starter.',
              style: CsTextStyles.bodySmall.copyWith(
                color: CsColors.gray700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirmPromotion,
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('Teilnahme bestätigen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CsColors.emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
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
        _sectionHeader(Icons.directions_car, l10n.sectionRides),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 60),
          child: _buildCarpoolSection(),
        ),

        const SizedBox(height: 14),

        // ── Section: Essen ──
        _sectionHeader(Icons.restaurant, l10n.sectionDinner),
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 120),
          child: _buildDinnerSection(),
        ),

        const SizedBox(height: 14),

        // ── Section: Spesen ──
        _sectionHeader(Icons.payments, l10n.sectionExpenses),
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
                          l10n.lineupTitle,
                          style: CsTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: CsColors.gray900,
                          ),
                        ),
                        if (lineupStatus != null)
                          Text(
                            isDraft ? l10n.lineupStatusDraft : l10n.lineupStatusPublished,
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
                      ? l10n.allSlotsOccupied
                      : (totalNeeded - (starters.length + reserves.length)) == 1
                          ? l10n.slotsFreeSingle
                          : l10n.slotsFree('${totalNeeded - (starters.length + reserves.length)}'),
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
                  label: _lineupSlots.isEmpty ? l10n.generateButton : l10n.regenerateButton,
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
                      l10n.noLineupYet,
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
                      l10n.noLineupYetAdmin,
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
              text: l10n.captainCreatingLineup,
              color: CsColors.warning,
            ),
          ] else ...[
            if (isPublished) ...[
              const SizedBox(height: 8),
              _premiumBanner(
                icon: Icons.auto_mode,
                text: l10n.subChainActive,
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
                        l10n.starterCountHeader('${starters.length}'),
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
                          l10n.reserveCountHeader('${reserves.length}'),
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
                label: l10n.sendLineupToTeam,
              ),
            ],

            if (isPublished && _isAdmin) ...[
              const SizedBox(height: 12),
              _premiumBanner(
                icon: Icons.check_circle,
                text: l10n.lineupPublishedBanner,
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
        ? l10n.violationSingle
        : l10n.violationMultiple('$count');

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
                l10n.violationMore('${_lineupViolations.length - 5}'),
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
              l10n.publishAnyway,
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
              slotType == 'starter' ? l10n.youStarter : l10n.youReserve,
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
                ? l10n.lineupPublishedNoReorder
                : _lineupGenerating
                ? l10n.lineupBeingGenerated
                : _lineupPublishing
                ? l10n.lineupBeingPublished
                : l10n.reorderNotPossible,
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
              slotType == 'starter' ? l10n.youStarter : l10n.youReserve,
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
                  l10n.carpoolsTitle,
                  style: CsTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 10),
                CsPrimaryButton(
                  onPressed: () => _showCarpoolOfferDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: l10n.iDriveButton,
                ),
              ],
            ),
          ),

        if (_carpoolOffers.isEmpty && hasMyOffer)
          _compactEmptyState(l10n.noCarpoolsYet),

        if (_carpoolOffers.isEmpty && !hasMyOffer)
          _compactEmptyState(l10n.noCarpoolsHint),

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
                              '${_playerNameForUserId(offer.driverUserId)}${isDriver ? ' ${l10n.youSuffix}' : ''}',
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
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 6,
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: CsColors.gray200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                offer.isFull ? CsColors.error : CsColors.emerald,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        offer.isFull
                            ? l10n.carpoolFull
                            : l10n.slotsFree('${offer.seatsAvailable}'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: offer.isFull
                              ? CsColors.error
                              : CsColors.gray500,
                        ),
                      ),
                    ],
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
                                label: Text(l10n.joinRideButton),
                              ),
                            if (canLeave)
                              OutlinedButton.icon(
                                onPressed: () => _leaveCarpool(offer.id),
                                icon: const Icon(Icons.person_remove, size: 16),
                                label: Text(l10n.leaveRideButton),
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
                                tooltip: l10n.editLabel,
                                style: IconButton.styleFrom(
                                  foregroundColor: CsColors.gray900,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteCarpool(offer.id),
                                icon: const Icon(
                                    Icons.delete_outline, size: 20),
                                tooltip: l10n.delete,
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
    return l10n.departAtFormat('$d.$mo.', '$h:$m');
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
      CsToast.success(context, l10n.joinedRideToast);
    } catch (e) {
      debugPrint('CARPOOL_JOIN_TAP ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.joinRideError);
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
      CsToast.success(context, l10n.leftRideToast);
    } catch (e) {
      debugPrint('CARPOOL_LEAVE_TAP ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.leaveRideError);
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
        title: l10n.deleteCarpoolTitle,
        ctaLabel: l10n.delete,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l10n.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_forever, size: 40, color: CsColors.error),
            const SizedBox(height: 12),
            Text(
              l10n.deleteCarpoolBody,
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
      CsToast.error(context, l10n.genericError);
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
                ? l10n.editCarpoolTitle
                : l10n.iDriveButton,
            ctaLabel: l10n.save,
            onCta: () => Navigator.pop(ctx, true),
            secondaryLabel: l10n.cancel,
            onSecondary: () => Navigator.pop(ctx, false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.seatsQuestion,
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
                  decoration: InputDecoration(
                    labelText: l10n.departureLocationLabel,
                    hintText: l10n.departureLocationHint,
                    prefixIcon: const Icon(Icons.location_on, size: 18),
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
                            ? l10n.departureTimeWithValue(departTime!.format(ctx))
                            : l10n.departureTimeOptional,
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
                      tooltip: departTime != null ? l10n.changeTooltip : l10n.setTooltip,
                    ),
                    if (departTime != null)
                      IconButton(
                        onPressed: () => setD(() => departTime = null),
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: l10n.removeTooltipLabel,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.noteOptional,
                    hintText: l10n.carpoolNoteHint,
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
        CsToast.success(context, l10n.carpoolSavedToast);
      } else {
        CsToast.info(context,
          l10n.carpoolCreatedReloadToast,
        );
      }
    } catch (e) {
      debugPrint('CARPOOL_UI CREATE ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
              // Counts row
              Row(
                children: [
                  _neutralCount(Icons.check_circle_outline, yesCount),
                  const SizedBox(width: 12),
                  _neutralCount(Icons.cancel_outlined, noCount),
                  const SizedBox(width: 12),
                  _neutralCount(Icons.help_outline, maybeCount),
                  const Spacer(),
                  Text(
                    l10n.answeredOfTotal('$answered', '$totalMembers'),
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
                l10n.yourRsvp,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CsColors.gray500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _dinnerButton(l10n.dinnerYes, 'yes', Icons.check_circle_outline, CsColors.success),
                  const SizedBox(width: 6),
                  _dinnerButton(l10n.dinnerNo, 'no', Icons.cancel_outlined, CsColors.error),
                  const SizedBox(width: 6),
                  _dinnerButton(l10n.dinnerMaybe, 'maybe', Icons.help_outline, CsColors.warning),
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
                        l10n.participantsTitle,
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
                                        '$name${isMe ? ' ${l10n.youSuffix}' : ''}',
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
          hintText: l10n.dinnerNoteHint,
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
      CsToast.error(context, l10n.dinnerSaveError);
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
              if (_expenses.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: CsStatusChip(
                    label: 'CHF ${totalCHF.toStringAsFixed(2)}',
                    variant: CsChipVariant.amber,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.expenseTotal, style: CsTextStyles.bodySmall.copyWith(color: CsColors.gray500)),
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
                          l10n.perPersonLabel('$memberCount'),
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
                  label: l10n.paidLabel,
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
                          l10n.firstConfirmDinner,
                        );
                      },
                icon: const Icon(Icons.add, size: 18),
                label: l10n.addExpenseButton,
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
                        ? l10n.noExpensesYet
                        : l10n.noExpensesPossible,
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
                '${l10n.paidByLabel(paidByName)}${isPaidByMe ? ' ${l10n.youSuffix}' : ''}'
                ' · ${expense.amountFormatted}'
                '${expense.note != null && expense.note!.isNotEmpty ? '\n${expense.note}' : ''}',
                style: CsTextStyles.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l10n.perPersonAmountLabel(expense.perPersonFormatted),
                        style: CsTextStyles.labelSmall,
                      ),
                      Text(
                        l10n.paidOfShareCount('${expense.paidCount}', '${expense.shareCount}'),
                        style: CsTextStyles.labelSmall.copyWith(
                          color: expense.openCount == 0
                              ? CsColors.success
                              : CsColors.warning,
                        ),
                      ),
                    ],
                  ),
                  if (isPaidByMe || _isAdmin)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: CsColors.gray500),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showEditExpenseDialog(expense);
                        } else if (value == 'delete') {
                          _confirmDeleteExpense(expense);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18, color: CsColors.gray600),
                              const SizedBox(width: 8),
                              Text(l10n.editExpenseTooltip),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: CsColors.error),
                              const SizedBox(width: 8),
                              Text(l10n.deleteExpenseTooltip, style: TextStyle(color: CsColors.error)),
                            ],
                          ),
                        ),
                      ],
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
                      '$shareName${isMe ? ' ${l10n.youSuffix}' : ''}',
                      style: TextStyle(
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                        decoration: share.isPaid
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      'CHF ${share.shareDouble.toStringAsFixed(2)}'
                      '${share.isPaid ? ' · ${l10n.sharePaid}' : ' · ${l10n.shareOpen}'}',
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
      CsToast.success(context, paid ? l10n.markedAsPaid : l10n.markedAsOpen);
    } catch (e) {
      debugPrint('EXPENSE_TOGGLE_PAID ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
        title: l10n.addExpenseButton,
        ctaLabel: l10n.save,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l10n.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: l10n.expenseTitleField,
                hintText: l10n.expenseTitleHint,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              decoration: InputDecoration(
                labelText: l10n.expenseAmountField,
                hintText: l10n.expenseAmountHint,
                prefixText: l10n.currencyPrefix,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: l10n.noteOptional,
                hintText: l10n.expenseNoteHint,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.expenseDistribution('$dinnerYes'),
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
      CsToast.info(context, l10n.enterTitleValidation);
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      CsToast.info(context, l10n.enterAmountValidation);
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
        l10n.expenseCreatedToast(title, amount.toStringAsFixed(2)),
      );
    } catch (e) {
      debugPrint('EXPENSE_CREATE ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
        title: l10n.deleteExpenseTitle,
        ctaLabel: l10n.delete,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l10n.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.delete_forever, size: 40, color: CsColors.error),
            const SizedBox(height: 12),
            Text(
              l10n.deleteExpenseBody(expense.title, expense.amountFormatted),
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
      CsToast.success(context, l10n.expenseDeletedToast(expense.title));
    } catch (e) {
      debugPrint('EXPENSE_DELETE ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
    }
  }

  Future<void> _showEditExpenseDialog(Expense expense) async {
    final titleCtrl = TextEditingController(text: expense.title);
    final amountCtrl = TextEditingController(
      text: expense.amountDouble.toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController(text: expense.note ?? '');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: l10n.editExpenseTitle,
        ctaLabel: l10n.save,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l10n.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: l10n.expenseTitleField,
                hintText: l10n.expenseTitleHint,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              decoration: InputDecoration(
                labelText: l10n.expenseAmountField,
                hintText: l10n.expenseAmountHint,
                prefixText: l10n.currencyPrefix,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: l10n.noteOptional,
                hintText: l10n.expenseNoteHint,
              ),
              textCapitalization: TextCapitalization.sentences,
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
      CsToast.info(context, l10n.enterTitleValidation);
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      CsToast.info(context, l10n.enterAmountValidation);
      return;
    }

    try {
      await ExpenseService.updateExpense(
        expenseId: expense.id,
        title: title,
        amountCents: (amount * 100).round(),
        note: note.isNotEmpty ? note : null,
      );
      await _reloadExpenses();
      if (!mounted) return;
      CsToast.success(context, l10n.expenseUpdatedToast(title));
    } catch (e) {
      debugPrint('EXPENSE_EDIT ERROR: $e');
      if (!mounted) return;
      CsToast.error(context, l10n.genericError);
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
                      l10n.subRequestsTitle,
                      style: CsTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CsColors.gray900,
                      ),
                    ),
                  ),
                  if (pendingCount > 0)
                    CsStatusChip(
                      label: l10n.pendingCountChip('$pendingCount'),
                      variant: CsChipVariant.amber,
                    ),
                ],
              ),
              if (_subRequests.isNotEmpty) ...[
                const SizedBox(height: 10),
                CsProgressRow(
                  label: l10n.pendingRequestsLabel,
                  value: l10n.answeredOfTotal('$pendingCount', '${_subRequests.length}'),
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
              l10n.youWereAsked,
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
                title: Text(l10n.subForPlayer(originalName)),
                subtitle: Text(
                  actionable
                      ? '${l10n.canYouStepIn}'
                            '${expiryLabel != null ? ' ($expiryLabel)' : ''}'
                      : l10n.timeExpired,
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
                            tooltip: l10n.acceptTooltip,
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
                            tooltip: l10n.declineTooltip,
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
            l10n.requestHistory,
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
              title: Text(l10n.subForPlayerHistory(subName, originalName)),
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
                  'pending' => l10n.chipWaiting,
                  'accepted' => l10n.chipAccepted,
                  'declined' => l10n.chipDeclined,
                  'expired' => l10n.timeExpired,
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
    return l10n.unknownPlayer;
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
              label: Text(l10n.subButton, style: const TextStyle(fontSize: 12)),
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
      label: isDraft ? l10n.lineupStatusDraft : l10n.lineupStatusPublished,
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
        return l10n.availYes;
      case 'no':
        return l10n.availNo;
      case 'maybe':
        return l10n.availMaybe;
      default:
        return l10n.availNoResponse;
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
