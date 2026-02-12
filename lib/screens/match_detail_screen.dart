import 'package:flutter/material.dart';
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

  // ── Sub-request state ──
  List<Map<String, dynamic>> _subRequests = [];
  List<Map<String, dynamic>> _myPendingSubRequests = [];

  // ── Carpool state ──
  List<CarpoolOffer> _carpoolOffers = [];
  RealtimeChannel? _carpoolOffersChannel;
  RealtimeChannel? _carpoolPassengersChannel;

  // ── Dinner RSVP state ──
  List<DinnerRsvp> _dinnerRsvps = [];
  String? _myDinnerStatus; // 'yes' | 'no' | 'maybe' | null

  // ── Expenses state ──
  List<Expense> _expenses = [];

  // ── Realtime subscription for lineup changes ──
  RealtimeChannel? _lineupChannel;

  // ── Generate-dialog defaults (overridden from lineup row if exists) ──
  int _starterCount = 6;
  int _reserveCount = 3;
  bool _includeMaybe = false;

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
            // Reload lineup when slots are changed (e.g. by auto-promotion trigger)
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
    } catch (e) {
      debugPrint('Lineup reload error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Realtime: carpool (offers + passengers)
  // ═══════════════════════════════════════════════════════════

  void _subscribeCarpoolChanges() {
    // Channel 1: cs_carpool_offers changes (create/update/delete offer)
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

    // Channel 2: cs_carpool_passengers changes (join/leave)
    // No match_id filter possible here, so we listen to all changes
    // and re-fetch (cheap — only rows for this match).
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

  /// Reload carpool offers (with passengers) and update state.
  ///
  /// When [rethrow_] is true the error is re-thrown after logging so the
  /// caller (e.g. create-flow) can show a meaningful message.
  /// Background / realtime callers leave it false (default).
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

  /// Reload dinner RSVPs and update state.
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

  /// Reload expenses and update state.
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
    return _members
        .any((m) => m['user_id'] == uid && m['role'] == 'captain');
  }

  Future<void> _load() async {
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
                'cs_app_profiles(display_name, email, avatar_path)')
            .eq('team_id', widget.teamId)
            .order('created_at', ascending: true);
        members = List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        final rows = await _supabase
            .from('cs_team_members')
            .select(
                'user_id, role, nickname, is_playing, ranking, created_at')
            .eq('team_id', widget.teamId)
            .order('created_at', ascending: true);
        members = List<Map<String, dynamic>>.from(rows);

        final uids =
            members.map((m) => m['user_id'] as String).toSet().toList();
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
          // Read settings from lineup row
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
        subRequests = await SubRequestService.listForMatch(widget.matchId);
        myPendingSubRequests =
            await SubRequestService.listMyPendingRequests();
        // Filter to this match only
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

      // Load carpool offers (non-blocking, separate from main data)
      _reloadCarpool();

      // Load dinner RSVPs (non-blocking)
      _reloadDinner();

      // Load expenses (non-blocking)
      _reloadExpenses();

      // Resolve avatars asynchronously (non-blocking)
      _resolveAvatarUrls();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Avatar resolution
  // ═══════════════════════════════════════════════════════════

  /// Collects all user IDs from members + claimed players, fetches their
  /// avatar_path from cs_app_profiles, and batch-resolves signed URLs.
  Future<void> _resolveAvatarUrls() async {
    // 1. Collect all user IDs
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
      // 2. Batch-fetch avatar_path from profiles
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

      // 3. Batch-resolve signed URLs
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

  /// Get signed avatar URL for a user, or null.
  String? _avatarUrlForUser(String userId) => _avatarUrls[userId];

  /// Build initials from display name (e.g. "Max Muster" → "MM").
  String _initialsForUser(String userId) {
    // 1. Try claimed player slot
    final claimed = _claimedMap[userId];
    if (claimed != null) {
      final f = (claimed['first_name'] as String? ?? '');
      final l = (claimed['last_name'] as String? ?? '');
      if (f.isNotEmpty && l.isNotEmpty) {
        return '${f[0]}${l[0]}'.toUpperCase();
      }
      if (f.isNotEmpty) return f[0].toUpperCase();
    }
    // 2. Try profile display_name
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
    // 3. Try member name resolution
    final member =
        _members.where((m) => m['user_id'] == userId).firstOrNull;
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

  /// Build a CircleAvatar for a user: signed image or initials fallback.
  Widget _userAvatar(String userId, {double radius = 16}) {
    final url = _avatarUrlForUser(userId);
    final initials = _initialsForUser(userId);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: url != null ? NetworkImage(url) : null,
      onBackgroundImageError: url != null
          ? (e, s) {
              // Silently handle broken image
              setState(() => _avatarUrls.remove(userId));
            }
          : null,
      child: url == null
          ? Text(
              initials,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.75,
                color: Colors.grey.shade700,
              ),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Availability
  // ═══════════════════════════════════════════════════════════

  Future<void> _setAvailability(String status) async {
    final old = _myStatus;
    setState(() => _myStatus = status);
    try {
      await MatchService.setAvailability(
        matchId: widget.matchId,
        status: status,
      );
      // Full reload: the DB trigger may have auto-promoted if we set 'no'
      // while being a starter in a published lineup.
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _myStatus = old);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Generate (draft only, no notifications)
  // ═══════════════════════════════════════════════════════════

  Future<void> _generateLineup() async {
    // ── Confirm-dialog with settings ──
    int tmpStarters = _starterCount;
    int tmpReserves = _reserveCount;
    bool tmpMaybe = _includeMaybe;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Aufstellung generieren'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Die Aufstellung wird anhand des Rankings und '
                  'der Verfügbarkeiten erstellt.\n'
                  'Du kannst danach manuell tauschen.\n\n'
                  'Eine bestehende Aufstellung wird überschrieben.',
                ),
                const SizedBox(height: 20),
                // Starter count
                Row(
                  children: [
                    const Expanded(child: Text('Starter')),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: tmpStarters > 1
                          ? () => setD(() => tmpStarters--)
                          : null,
                    ),
                    Text('$tmpStarters',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: tmpStarters < 12
                          ? () => setD(() => tmpStarters++)
                          : null,
                    ),
                  ],
                ),
                // Reserve count
                Row(
                  children: [
                    const Expanded(child: Text('Ersatz')),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: tmpReserves > 0
                          ? () => setD(() => tmpReserves--)
                          : null,
                    ),
                    Text('$tmpReserves',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
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
                  title: const Text('Maybe berücksichtigen'),
                  subtitle: const Text(
                      'Spieler mit „Vielleicht" als Auffüllung'),
                  value: tmpMaybe,
                  onChanged: (v) => setD(() => tmpMaybe = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, true);
              },
              child: const Text('Generieren'),
            ),
          ],
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entwurf erstellt: '
            '${result['starters']} Starter, '
            '${result['reserves']} Ersatz ✅',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
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
      Map<String, dynamic> from, Map<String, dynamic> to) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Drag & Drop reorder
  // ═══════════════════════════════════════════════════════════

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final ordered = _orderedSlots;
    if (oldIndex < 0 || oldIndex >= ordered.length ||
        newIndex < 0 || newIndex >= ordered.length) {
      return;
    }

    final from = ordered[oldIndex];
    final to = ordered[newIndex];
    await _swapSlots(from, to);
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Lock / Unlock slot
  // ═══════════════════════════════════════════════════════════

  Future<void> _toggleLock(Map<String, dynamic> slot) async {
    final slotId = slot['id'] as String;
    final currentLocked = slot['locked'] == true;
    final newLocked = !currentLocked;

    // Optimistic update
    setState(() => slot['locked'] = newLocked);

    try {
      await LineupService.toggleSlotLock(slotId: slotId, locked: newLocked);
    } catch (e) {
      if (!mounted) return;
      setState(() => slot['locked'] = currentLocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Lineup: Publish → sends notifications
  // ═══════════════════════════════════════════════════════════

  Future<void> _publishLineup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufstellung veröffentlichen?'),
        content: const Text(
          'Alle Team-Mitglieder werden über die '
          'Aufstellung informiert (In-App + Push).\n\n'
          'Möchtest du die Aufstellung jetzt senden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zurück'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send),
            label: const Text('Senden'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _lineupPublishing = true);
    try {
      final result = await LineupService.publishLineup(widget.matchId);
      if (!mounted) return;
      final recipients = result['recipients'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Aufstellung veröffentlicht – $recipients Benachrichtigungen gesendet ✅'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    } finally {
      if (mounted) setState(() => _lineupPublishing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Sub-request actions
  // ═══════════════════════════════════════════════════════════

  /// Captain creates a sub request for an absent starter.
  Future<void> _createSubRequest(String originalUserId) async {
    try {
      final result = await SubRequestService.createRequest(
        matchId: widget.matchId,
        originalUserId: originalUserId,
      );
      if (!mounted) return;
      final success = result['success'] == true;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Ersatzanfrage an ${result['substitute_name']} gesendet ✅'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] as String? ??
                'Kein Ersatzspieler gefunden'),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  /// Substitute responds to a pending request.
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
            ? 'Ersatz bestätigt ✅'
            : 'Ersatzanfrage abgelehnt';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(result['message'] as String? ?? 'Fehler aufgetreten'),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Admin match actions
  // ═══════════════════════════════════════════════════════════

  Future<void> _editMatch() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMatchScreen(
          teamId: widget.teamId,
          existingMatch: _match,
        ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spiel löschen?'),
        content: Text(
          'Möchtest du das Spiel gegen '
          '"${_match['opponent'] ?? '?'}" wirklich löschen?\n'
          'Alle Verfügbarkeiten und Aufstellungen gehen verloren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await MatchService.deleteMatch(widget.matchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spiel gelöscht ✅')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
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

  /// Display name for a lineup slot – embedded cs_team_players or fallback.
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
      final member =
          _members.where((m) => m['user_id'] == userId).firstOrNull;
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

  @override
  Widget build(BuildContext context) {
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

    // Availability counts
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

    final lineupStatus = _lineup?['status'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text('vs ${m['opponent'] ?? '?'}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          if (!_loading && _isAdmin)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _editMatch();
                if (value == 'delete') _deleteMatch();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'edit', child: Text('✏️ Bearbeiten')),
                PopupMenuItem(
                    value: 'delete', child: Text('🗑️ Löschen')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Match info card ──────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['opponent'] ?? '?'} '
                          '(${isHome ? 'Heim' : 'Auswärts'})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 6),
                          Text('$dateStr  $timeStr'),
                        ]),
                        if (m['location'] != null &&
                            (m['location'] as String).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.location_on, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(m['location'] as String)),
                          ]),
                        ],
                        if (m['note'] != null &&
                            (m['note'] as String).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.notes, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(m['note'] as String)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── My availability ─────────────────────
                Text('Meine Verfügbarkeit',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _availButton('yes', '✅ Kann', Colors.green),
                    const SizedBox(width: 8),
                    _availButton('no', '❌ Kann nicht', Colors.red),
                    const SizedBox(width: 8),
                    _availButton(
                        'maybe', '❓ Vielleicht', Colors.orange),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Availability summary ────────────────
                Text('Verfügbarkeiten',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _countChip(
                        '✅ $yes', Colors.green.shade50, Colors.green),
                    _countChip(
                        '❌ $no', Colors.red.shade50, Colors.red),
                    _countChip('❓ $maybe', Colors.orange.shade50,
                        Colors.orange),
                    _countChip('– $noResponse', Colors.grey.shade100,
                        Colors.grey),
                  ],
                ),

                const Divider(height: 36),

                // ═════════════════════════════════════════
                // ── AUFSTELLUNG ─────────────────────────
                // ═════════════════════════════════════════
                _buildLineupSection(lineupStatus),

                // ═════════════════════════════════════════
                // ── SUB REQUESTS ──────────────────────
                // ═════════════════════════════════════════
                if (_myPendingSubRequests.isNotEmpty ||
                    _subRequests.isNotEmpty) ...[
                  const Divider(height: 36),
                  _buildSubRequestSection(),
                ],

                const Divider(height: 36),

                // ═════════════════════════════════════════
                // ── CARPOOL ────────────────────────────
                // ═════════════════════════════════════════
                _buildCarpoolSection(),

                const Divider(height: 36),

                // ═════════════════════════════════════════
                // ── DINNER RSVP ──────────────────────────
                // ═════════════════════════════════════════
                _buildDinnerSection(),

                const Divider(height: 36),

                // ═════════════════════════════════════════
                // ── EXPENSES / SPESEN ────────────────────
                // ═════════════════════════════════════════
                _buildExpensesSection(),

                const Divider(height: 36),

                // ── Player availability list ────────────
                Text('Spieler-Status',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._members.map(_buildPlayerStatusTile),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Aufstellung section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildLineupSection(String? lineupStatus) {
    final ordered = _orderedSlots;
    final starters =
        ordered.where((s) => s['slot_type'] == 'starter').toList();
    final reserves =
        ordered.where((s) => s['slot_type'] == 'reserve').toList();

    final isPublished = lineupStatus == 'published';
    final isDraft = lineupStatus == 'draft';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ──
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text('Aufstellung',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (lineupStatus != null) ...[
                    const SizedBox(width: 8),
                    _lineupStatusBadge(lineupStatus),
                  ],
                ],
              ),
            ),
            if (_isAdmin)
              ElevatedButton.icon(
                onPressed:
                    _lineupGenerating ? null : _generateLineup,
                icon: _lineupGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: Text(
                    _lineupSlots.isEmpty ? 'Generieren' : 'Neu'),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Content ──
        if (_lineupSlots.isEmpty) ...[
          // No lineup exists
          if (!_isAdmin)
            const Text(
              'Noch keine Aufstellung.',
              style: TextStyle(
                  color: Colors.grey, fontStyle: FontStyle.italic),
            )
          else
            const Text(
              'Noch keine Aufstellung erstellt.\n'
              'Klicke „Generieren" um eine zu erstellen.',
              style: TextStyle(
                  color: Colors.grey, fontStyle: FontStyle.italic),
            ),
        ] else ...[
          // Non-admin sees draft hint
          if (!_isAdmin && isDraft) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top,
                      color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Captain erstellt gerade die Aufstellung …',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Auto-promotion hint (published) ──
            if (isPublished) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_mode,
                        color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ersatzkette aktiv: Bei Absage rückt '
                        'der nächste Ersatz automatisch nach.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Slot list (drag & drop for admin draft, static otherwise) ──
            if (_isAdmin && isDraft) ...[
              _buildReorderableSlots(
                  ordered, starters.length, reserves.length),
            ] else ...[
              Text('Starter (${starters.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...List.generate(starters.length, (i) {
                return _buildSlotTile(starters[i], i, ordered.length);
              }),
              if (reserves.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Ersatz (${reserves.length})',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...List.generate(reserves.length, (j) {
                  final linearIdx = starters.length + j;
                  return _buildSlotTile(
                      reserves[j], linearIdx, ordered.length);
                }),
              ],
            ],

            // ── Publish button (only for admin in draft state) ──
            if (_isAdmin && isDraft) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _lineupPublishing ? null : _publishLineup,
                  icon: _lineupPublishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.send),
                  label: const Text('Info an Team senden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],

            // Already published + admin hint
            if (isPublished && _isAdmin) ...[
              const SizedBox(height: 12),
              const Text(
                'Aufstellung veröffentlicht. Absagen lösen '
                'automatisches Nachrücken aus.',
                style: TextStyle(
                    color: Colors.green,
                    fontStyle: FontStyle.italic,
                    fontSize: 12),
              ),
            ],
          ],
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Slot tile (with availability chip, lock, up/down arrows)
  // ═══════════════════════════════════════════════════════════

  Widget _buildSlotTile(
      Map<String, dynamic> slot, int linearIndex, int totalCount) {
    final pos = slot['position'] as int;
    final slotType = slot['slot_type'] as String;
    final userId = slot['user_id'] as String?;
    final isMe = userId == _supabase.auth.currentUser?.id;
    final isFirst = linearIndex == 0;
    final isLast = linearIndex == totalCount - 1;
    final isDraft = _lineup?['status'] == 'draft';
    final isPublished = _lineup?['status'] == 'published';
    final isLocked = slot['locked'] == true;

    // Availability of the slot's user
    final avail = userId != null ? _availStatusForUser(userId) : '–';

    // Color based on type
    final posColor =
        slotType == 'starter' ? Colors.blue : Colors.orange;

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
          // Availability chip (always shown, visible for published lineups)
          if (userId != null) ...[
            const SizedBox(width: 4),
            _availChip(avail),
          ],
          // Lock icon (admin only, published only)
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
                      ? Colors.red.shade400
                      : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: isMe
          ? Text(
              slotType == 'starter' ? 'Du · Starter' : 'Du · Ersatz',
              style: const TextStyle(fontSize: 11, color: Colors.blue),
            )
          : null,
      trailing: (_isAdmin && isDraft)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_upward,
                      size: 18,
                      color: isFirst ? Colors.grey.shade300 : null),
                  onPressed: isFirst ? null : () => _moveUp(linearIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_downward,
                      size: 18,
                      color: isLast ? Colors.grey.shade300 : null),
                  onPressed: isLast ? null : () => _moveDown(linearIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),
              ],
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Draggable slot tile (Drag & Drop – admin draft only)
  // ═══════════════════════════════════════════════════════════

  Widget _buildDraggableSlotTile(
      Map<String, dynamic> slot, int index, int totalCount) {
    final pos = slot['position'] as int;
    final slotType = slot['slot_type'] as String;
    final userId = slot['user_id'] as String?;
    final isMe = userId == _supabase.auth.currentUser?.id;
    final avail = userId != null ? _availStatusForUser(userId) : '–';
    final posColor = slotType == 'starter' ? Colors.blue : Colors.orange;

    return Material(
      key: ValueKey(slot['id'] as String),
      child: ListTile(
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
            if (userId != null) ...[
              const SizedBox(width: 4),
              _availChip(avail),
            ],
          ],
        ),
        subtitle: isMe
            ? Text(
                slotType == 'starter' ? 'Du · Starter' : 'Du · Ersatz',
                style: const TextStyle(fontSize: 11, color: Colors.blue),
              )
            : null,
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: Colors.grey),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Reorderable slots list (admin + draft)
  // ═══════════════════════════════════════════════════════════

  Widget _buildReorderableSlots(
      List<Map<String, dynamic>> ordered,
      int starterCount,
      int reserveCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Starter ($starterCount)',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (reserveCount > 0) ...[
              const SizedBox(width: 12),
              Text('· Ersatz ($reserveCount)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700)),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text('Halte ☰ und ziehe um Positionen zu tauschen',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: ordered.length,
          onReorder: _onReorder,
          proxyDecorator: (child, index, animation) {
            return Material(
              elevation: 4,
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              child: child,
            );
          },
          itemBuilder: (context, index) {
            return _buildDraggableSlotTile(
                ordered[index], index, ordered.length);
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Carpool section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildCarpoolSection() {
    final uid = _supabase.auth.currentUser?.id;
    final hasMyOffer =
        uid != null && _carpoolOffers.any((o) => o.driverUserId == uid);
    debugPrint(
      'CARPOOL_CTA: uid=$uid hasMyOffer=$hasMyOffer '
      'offersCount=${_carpoolOffers.length}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row with "Ich fahre" button ──
        Row(
          children: [
            const Icon(Icons.directions_car, size: 20),
            const SizedBox(width: 8),
            Text('Fahrgemeinschaften',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!hasMyOffer)
              TextButton.icon(
                onPressed: () => _showCarpoolOfferDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ich fahre'),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_carpoolOffers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Noch keine Fahrgemeinschaften.',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          )
        else
          ..._carpoolOffers.map((offer) {
            final isDriver = offer.driverUserId == uid;
            final isPassenger = uid != null && offer.hasPassenger(uid);
            final canJoin = !isDriver && !isPassenger && !offer.isFull;
            final canLeave = isPassenger;
            debugPrint(
              'CARPOOL_RENDER: offerId=${offer.id} '
              'uid=$uid driverId=${offer.driverUserId} '
              'isDriver=$isDriver isPassenger=$isPassenger '
              'isFull=${offer.isFull} canJoin=$canJoin canLeave=$canLeave '
              'seats=${offer.seatsTaken}/${offer.seatsTotal} '
              'passengers=${offer.passengers.map((p) => p.userId).toList()}',
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Driver + Seats ──
                    Row(
                      children: [
                        _userAvatar(offer.driverUserId, radius: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_playerNameForUserId(offer.driverUserId)}${isDriver ? ' (du)' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              const Text('Fahrer',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: offer.isFull
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${offer.seatsTaken}/${offer.seatsTotal} Plätze',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: offer.isFull
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ── Start location ──
                    if (offer.startLocation != null &&
                        offer.startLocation!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(offer.startLocation!,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],

                    // ── Departure time ──
                    if (offer.departAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            _formatDepartAt(offer.departAt!),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ],

                    // ── Note ──
                    if (offer.note != null && offer.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(offer.note!,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],

                    // ── Passengers list ──
                    if (offer.passengers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: offer.passengers.map((p) {
                          final pName = _playerNameForUserId(p.userId);
                          final isMe = p.userId == uid;
                          return Chip(
                            avatar: _userAvatar(p.userId, radius: 12),
                            label: Text(
                              pName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    isMe ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ],

                    // ── Action buttons ──
                    const SizedBox(height: 8),
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
                              foregroundColor: Colors.red.shade700,
                            ),
                          ),
                        if (isDriver) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () =>
                                _showCarpoolOfferDialog(existingOffer: offer),
                            icon: const Icon(Icons.edit, size: 18),
                            tooltip: 'Bearbeiten',
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _deleteCarpool(offer.id),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Löschen',
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ],
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
      debugPrint('CARPOOL_JOIN_TAP: reload done, offers=${_carpoolOffers.length}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Du fährst mit ✅')),
      );
    } catch (e) {
      debugPrint('CARPOOL_JOIN_TAP ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mitfahren fehlgeschlagen: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
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
      debugPrint('CARPOOL_LEAVE_TAP: reload done, offers=${_carpoolOffers.length}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ausgestiegen')),
      );
    } catch (e) {
      debugPrint('CARPOOL_LEAVE_TAP ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aussteigen fehlgeschlagen: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _deleteCarpool(String offerId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fahrgemeinschaft löschen?'),
        content: const Text('Alle Mitfahrer werden entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CarpoolService.deleteOffer(offerId);
      await _reloadCarpool();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _showCarpoolOfferDialog({CarpoolOffer? existingOffer}) async {
    int seats = existingOffer?.seatsTotal ?? 4;
    final locationCtrl =
        TextEditingController(text: existingOffer?.startLocation ?? '');
    final noteCtrl =
        TextEditingController(text: existingOffer?.note ?? '');
    TimeOfDay? departTime = existingOffer?.departAt != null
        ? TimeOfDay.fromDateTime(existingOffer!.departAt!.toLocal())
        : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existingOffer != null
              ? 'Fahrgemeinschaft bearbeiten'
              : 'Ich fahre'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seats stepper
                const Text('Anzahl freie Plätze:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      onPressed: seats > 1
                          ? () => setD(() => seats--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$seats',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: seats < 9
                          ? () => setD(() => seats++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Start location
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Abfahrtsort',
                    hintText: 'z.B. Bahnhof Bern',
                    prefixIcon: Icon(Icons.location_on, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Departure time
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 18),
                    const SizedBox(width: 8),
                    Text(departTime != null
                        ? 'Abfahrt: ${departTime!.format(ctx)}'
                        : 'Abfahrtszeit (optional)'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: departTime ?? TimeOfDay.now(),
                        );
                        if (t != null) setD(() => departTime = t);
                      },
                      child: Text(
                          departTime != null ? 'Ändern' : 'Setzen'),
                    ),
                    if (departTime != null)
                      IconButton(
                        onPressed: () => setD(() => departTime = null),
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Entfernen',
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Note
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notiz (optional)',
                    hintText: 'z.B. Treffpunkt Parkplatz',
                    prefixIcon: Icon(Icons.notes, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    // Build depart_at DateTime from the match date + selected time
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
        startLocation:
            locationCtrl.text.trim().isEmpty ? null : locationCtrl.text.trim(),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        departAt: departAt,
      );
      debugPrint('CARPOOL_UI: upsert returned offerId=$offerId – refetching…');

      // Refetch with rethrow so query errors surface here
      await _reloadCarpool(rethrow_: true);
      if (!mounted) return;

      // Verify the offer is actually visible after refetch
      final visible = _carpoolOffers.any((o) => o.id == offerId);
      debugPrint(
        'CARPOOL_UI: post-refetch offers=${_carpoolOffers.length}, '
        'offerId=$offerId visible=$visible',
      );

      if (visible) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fahrgemeinschaft gespeichert ✅')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Fahrgemeinschaft erstellt, aber nicht sichtbar.\n'
              'Mögliche Ursache: fehlende Leseberechtigung (RLS).',
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      debugPrint('CARPOOL_UI CREATE ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Dinner RSVP section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildDinnerSection() {
    final uid = _supabase.auth.currentUser?.id;

    // Counts
    final yesCount = _dinnerRsvps.where((r) => r.status == 'yes').length;
    final noCount = _dinnerRsvps.where((r) => r.status == 'no').length;
    final maybeCount = _dinnerRsvps.where((r) => r.status == 'maybe').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Row(
          children: [
            const Icon(Icons.restaurant, size: 20),
            const SizedBox(width: 8),
            Text('Essen',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),

        // ── My RSVP Buttons ──
        Row(
          children: [
            _dinnerButton('Ja', 'yes', Icons.check_circle_outline),
            const SizedBox(width: 8),
            _dinnerButton('Nein', 'no', Icons.cancel_outlined),
            const SizedBox(width: 8),
            _dinnerButton('Vielleicht', 'maybe', Icons.help_outline),
          ],
        ),

        // ── Note input (visible after choosing yes/maybe) ──
        if (_myDinnerStatus == 'yes' || _myDinnerStatus == 'maybe') ...[
          const SizedBox(height: 8),
          _buildDinnerNoteField(),
        ],

        const SizedBox(height: 12),

        // ── Summary counts ──
        Wrap(
          spacing: 16,
          children: [
            _dinnerCountChip('✅ Ja', yesCount, Colors.green),
            _dinnerCountChip('❌ Nein', noCount, Colors.red),
            _dinnerCountChip('❓ Vielleicht', maybeCount, Colors.orange),
          ],
        ),

        // ── RSVP list ──
        if (_dinnerRsvps.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...List.generate(_dinnerRsvps.length, (i) {
            final rsvp = _dinnerRsvps[i];
            final name = _playerNameForUserId(rsvp.userId);
            final isMe = rsvp.userId == uid;
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              leading: _userAvatar(rsvp.userId, radius: 16),
              title: Text(
                '$name${isMe ? ' (du)' : ''}',
                style: TextStyle(
                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: rsvp.note != null && rsvp.note!.isNotEmpty
                  ? Text(rsvp.note!, style: const TextStyle(fontSize: 12))
                  : null,
              trailing: Text(
                rsvp.statusEmoji,
                style: const TextStyle(fontSize: 18),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _dinnerButton(String label, String status, IconData icon) {
    final isSelected = _myDinnerStatus == status;
    final Color color;
    switch (status) {
      case 'yes':
        color = Colors.green;
        break;
      case 'no':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _setDinnerRsvp(status),
        icon: Icon(icon, size: 18, color: isSelected ? Colors.white : color),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? color : null,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _dinnerCountChip(String label, int count, Color color) {
    return Chip(
      label: Text('$label: $count',
          style: TextStyle(fontSize: 12, color: color)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }

  Widget _buildDinnerNoteField() {
    // Find my current note
    final uid = _supabase.auth.currentUser?.id;
    final myRsvp = _dinnerRsvps
        .where((r) => r.userId == uid)
        .firstOrNull;
    final ctrl = TextEditingController(text: myRsvp?.note ?? '');

    return TextField(
      controller: ctrl,
      decoration: const InputDecoration(
        hintText: 'Notiz (z.B. "komme später")',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (value) {
        if (_myDinnerStatus != null) {
          _setDinnerRsvp(_myDinnerStatus!, note: value);
        }
      },
    );
  }

  Future<void> _setDinnerRsvp(String status, {String? note}) async {
    try {
      // If same status tapped again without note change, just ignore
      final uid = _supabase.auth.currentUser?.id;
      final existingRsvp = _dinnerRsvps
          .where((r) => r.userId == uid)
          .firstOrNull;

      // Use existing note if none provided
      final effectiveNote = note ?? existingRsvp?.note;

      await DinnerService.upsertRsvp(
        matchId: widget.matchId,
        status: status,
        note: effectiveNote,
      );
      await _reloadDinner();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'yes'
              ? 'Du isst mit! 🍽️'
              : status == 'no'
                  ? 'Kein Essen für dich.'
                  : 'Vielleicht – wir zählen dich mal mit.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('DINNER_UPSERT ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Expenses section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildExpensesSection() {
    final uid = _supabase.auth.currentUser?.id;

    // Summary
    final totalCents =
        _expenses.fold<int>(0, (sum, e) => sum + e.amountCents);
    final totalCHF = totalCents / 100.0;
    final totalOpenCents =
        _expenses.fold<int>(0, (sum, e) => sum + e.openCents);
    final totalPaidCents = totalCents - totalOpenCents;
    final memberCount =
        _expenses.isNotEmpty ? _expenses.first.shareCount : _members.length;
    final perPersonCHF = memberCount > 0 ? totalCHF / memberCount : 0.0;

    // Dinner-yes count (for the hint in the dialog)
    final dinnerYesCount =
        _dinnerRsvps.where((r) => r.status == 'yes').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header with add button ──
        Row(
          children: [
            const Icon(Icons.receipt_long, size: 20),
            const SizedBox(width: 8),
            Text('Spesen',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: dinnerYesCount > 0
                  ? () => _showCreateExpenseDialog()
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Keine Dinner-Zusagen (Ja) – '
                            'bitte zuerst unter "Essen" zusagen.',
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Summary ──
        if (_expenses.isNotEmpty) ...[
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            'CHF ${totalCHF.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Pro Kopf ($memberCount Pers.)',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          Text(
                            'CHF ${perPersonCHF.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '✅ Bezahlt: CHF ${(totalPaidCents / 100).toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.green.shade700),
                      ),
                      Text(
                        '⏳ Offen: CHF ${(totalOpenCents / 100).toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: totalOpenCents > 0
                                ? Colors.orange.shade700
                                : Colors.green.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── Empty state ──
        if (_expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              dinnerYesCount > 0
                  ? 'Noch keine Spesen erfasst.'
                  : 'Noch keine Spesen – zuerst unter "Essen" zusagen.',
              style: const TextStyle(color: Colors.grey),
            ),
          ),

        // ── Expense list (expandable with shares) ──
        ...List.generate(_expenses.length, (i) {
          final expense = _expenses[i];
          final paidByName = _playerNameForUserId(expense.paidByUserId);
          final isPaidByMe = expense.paidByUserId == uid;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: expense.openCount == 0
                    ? Colors.green.shade100
                    : Colors.orange.shade100,
                child: Icon(
                  expense.openCount == 0
                      ? Icons.check_circle
                      : Icons.payments,
                  color: expense.openCount == 0
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              title: Text(expense.title),
              subtitle: Text(
                'Bezahlt von $paidByName${isPaidByMe ? ' (du)' : ''}'
                ' · ${expense.amountFormatted}'
                '${expense.note != null && expense.note!.isNotEmpty ? '\n${expense.note}' : ''}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${expense.perPersonFormatted}/Pers.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  Text(
                    '${expense.paidCount}/${expense.shareCount} bezahlt',
                    style: TextStyle(
                      fontSize: 11,
                      color: expense.openCount == 0
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
              children: [
                // ── Share list ──
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
                      '${share.isPaid ? ' · ✅ Bezahlt' : ' · ⏳ Offen'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: share.isPaid ? Colors.green : Colors.orange,
                      ),
                    ),
                    trailing: canToggle
                        ? Switch(
                            value: share.isPaid,
                            activeTrackColor: Colors.green.shade200,
                            activeThumbColor: Colors.green,
                            onChanged: (_) => _toggleSharePaid(
                              share.id,
                              !share.isPaid,
                            ),
                          )
                        : Icon(
                            share.isPaid
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color:
                                share.isPaid ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                  );
                }),
                // ── Delete action (for payer) ──
                if (isPaidByMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton.icon(
                      onPressed: () => _confirmDeleteExpense(expense),
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      label: const Text('Spese löschen',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(paid ? 'Als bezahlt markiert ✅' : 'Als offen markiert'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('EXPENSE_TOGGLE_PAID ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _showCreateExpenseDialog() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spese hinzufügen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titel *',
                  hintText: 'z.B. Pizza, Getränke',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Betrag (CHF) *',
                  hintText: 'z.B. 45.50',
                  border: OutlineInputBorder(),
                  prefixText: 'CHF ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                  hintText: 'z.B. Restaurant Adler',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              Text(
                'Wird gleichmässig auf alle '
                '${_dinnerRsvps.where((r) => r.status == 'yes').length} '
                'Dinner-Teilnehmer (Ja) verteilt.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final title = titleCtrl.text.trim();
    final amountText = amountCtrl.text.trim().replaceAll(',', '.');
    final note = noteCtrl.text.trim();

    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel eingeben.')),
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gültigen Betrag eingeben.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Spese "$title" (CHF ${amount.toStringAsFixed(2)}) erstellt.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('EXPENSE_CREATE ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _confirmDeleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spese löschen?'),
        content: Text(
          '„${expense.title}" (${expense.amountFormatted}) '
          'und alle Anteile werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ExpenseService.deleteExpense(expense.id);
      await _reloadExpenses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Spese „${expense.title}" gelöscht.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('EXPENSE_DELETE ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Sub-request section builder
  // ═══════════════════════════════════════════════════════════

  Widget _buildSubRequestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ersatzanfragen',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),

        // ── Pending requests for ME (I am the substitute) ──
        if (_myPendingSubRequests.isNotEmpty) ...[
          const Text('Du wurdest angefragt:',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.orange)),
          const SizedBox(height: 4),
          ..._myPendingSubRequests.map((req) {
            final originalId = req['original_user_id'] as String? ?? '';
            final originalName = _playerNameForUserId(originalId);
            return Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading:
                    const Icon(Icons.swap_horiz, color: Colors.orange),
                title: Text('Ersatz für $originalName'),
                subtitle: const Text('Kannst du einspringen?'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle,
                          color: Colors.green, size: 32),
                      tooltip: 'Annehmen',
                      onPressed: () => _respondSubRequest(
                          req['id'] as String, 'accepted'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.cancel,
                          color: Colors.red, size: 32),
                      tooltip: 'Ablehnen',
                      onPressed: () => _respondSubRequest(
                          req['id'] as String, 'declined'),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        // ── All requests for this match (history / captain view) ──
        if (_subRequests.isNotEmpty) ...[
          const Text('Anfragen-Verlauf:',
              style: TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          ..._subRequests.map((req) {
            final status = req['status'] as String? ?? '?';
            final originalName =
                _playerNameForUserId(req['original_user_id'] as String? ?? '');
            final subName = _playerNameForUserId(
                req['substitute_user_id'] as String? ?? '');
            final icon = switch (status) {
              'pending' => Icons.hourglass_top,
              'accepted' => Icons.check_circle,
              'declined' => Icons.cancel,
              'expired' => Icons.timer_off,
              _ => Icons.help_outline,
            };
            final color = switch (status) {
              'pending' => Colors.orange,
              'accepted' => Colors.green,
              'declined' => Colors.red,
              'expired' => Colors.grey,
              _ => Colors.grey,
            };
            return ListTile(
              dense: true,
              leading: Icon(icon, color: color, size: 20),
              title: Text('$subName für $originalName'),
              trailing: Chip(
                label: Text(status,
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: color.withValues(alpha: 0.15),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Resolve a user_id to a display name via claimed player slots,
  /// profiles (display_name), member nickname, or UUID fallback.
  String _playerNameForUserId(String userId) {
    // 1. Claimed player slot (first_name + last_name)
    final claimed = _claimedMap[userId];
    if (claimed != null) {
      final name = TeamPlayerService.playerDisplayName(claimed);
      if (name.isNotEmpty && name != '?') return name;
    }
    // 2. Profile display_name
    final profile = _profiles[userId];
    if (profile != null) {
      final dn = profile['display_name'] as String?;
      if (dn != null && dn.isNotEmpty && dn != 'Spieler') return dn;
    }
    // 3. Member embedded profile or nickname
    final member =
        _members.where((m) => m['user_id'] == userId).firstOrNull;
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
    // 4. Fallback
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
    final display =
        rank.isNotEmpty ? '$nameStr · $rank' : nameStr;

    // Show "Ersatz anfordern" for admin when player is 'no'
    // and lineup is published, and no pending request already exists.
    final isPublished = _lineup?['status'] == 'published';
    final hasPending = _subRequests.any((r) =>
        r['original_user_id'] == uid && r['status'] == 'pending');
    final showSubButton =
        _isAdmin && status == 'no' && isPublished && !hasPending;

    return ListTile(
      dense: true,
      leading: _statusIcon(status),
      title: Text(
        '$display${_roleTag(member)}',
        style: TextStyle(
          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(_statusLabel(status)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMe)
            const Icon(Icons.person, size: 16, color: Colors.blue),
          if (showSubButton) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _createSubRequest(uid),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Ersatz', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                foregroundColor: Colors.orange.shade700,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDraft
            ? Colors.orange.shade100
            : Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isDraft ? 'Entwurf' : 'Veröffentlicht',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color:
              isDraft ? Colors.orange.shade800 : Colors.green.shade800,
        ),
      ),
    );
  }

  /// Compact chip showing availability status for a lineup slot player.
  Widget _availChip(String status) {
    String label;
    Color bg;
    Color fg;
    switch (status) {
      case 'yes':
        label = '✅';
        bg = Colors.green.shade50;
        fg = Colors.green;
      case 'no':
        label = '❌';
        bg = Colors.red.shade50;
        fg = Colors.red;
      case 'maybe':
        label = '❓';
        bg = Colors.orange.shade50;
        fg = Colors.orange;
      default:
        label = '–';
        bg = Colors.grey.shade100;
        fg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: fg),
      ),
    );
  }

  Widget _availButton(String status, String label, Color color) {
    final isSelected = _myStatus == status;
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _setAvailability(status),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? color : null,
          foregroundColor: isSelected ? Colors.white : color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _countChip(String label, Color bg, Color fg) {
    return Chip(
      label: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Icon _statusIcon(String status) {
    switch (status) {
      case 'yes':
        return const Icon(Icons.check_circle,
            color: Colors.green, size: 20);
      case 'no':
        return const Icon(Icons.cancel, color: Colors.red, size: 20);
      case 'maybe':
        return const Icon(Icons.help, color: Colors.orange, size: 20);
      default:
        return const Icon(Icons.radio_button_unchecked,
            color: Colors.grey, size: 20);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'yes':
        return 'Verfügbar';
      case 'no':
        return 'Nicht verfügbar';
      case 'maybe':
        return 'Vielleicht';
      default:
        return 'Keine Antwort';
    }
  }
}
