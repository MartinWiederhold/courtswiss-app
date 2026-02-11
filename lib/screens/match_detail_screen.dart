import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/match_service.dart';
import '../services/lineup_service.dart';
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

  // ── Lineup state ──
  Map<String, dynamic>? _lineup; // cs_match_lineups row (or null)
  List<Map<String, dynamic>> _lineupSlots = [];
  bool _lineupGenerating = false;
  bool _lineupPublishing = false;

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
  }

  @override
  void dispose() {
    _lineupChannel?.unsubscribe();
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
                'cs_app_profiles(display_name, email)')
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
              .select('user_id, display_name, email')
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

      if (!mounted) return;
      setState(() {
        _availability = avail;
        _members = members;
        _profiles = profileMap;
        _claimedMap = claimedMap;
        _myStatus = myStatus;
        _lineup = lineup;
        _lineupSlots = lineupSlots;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
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

            // ── Starters ──
            Text('Starter (${starters.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...List.generate(starters.length, (i) {
              final linearIdx = i; // starters are first
              return _buildSlotTile(
                  starters[i], linearIdx, ordered.length);
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
      trailing: isMe
          ? const Icon(Icons.person, size: 16, color: Colors.blue)
          : null,
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
