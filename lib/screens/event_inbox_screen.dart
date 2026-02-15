import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/event_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';
import 'match_detail_screen.dart';

/// Global Inbox screen – shows cs_events across all teams.
/// Unread events are highlighted; tapping marks as read.
/// Events with a match_id navigate to MatchDetailScreen.
/// Optional: Team-filter dropdown to scope the list.
class EventInboxScreen extends StatefulWidget {
  const EventInboxScreen({super.key});

  @override
  State<EventInboxScreen> createState() => _EventInboxScreenState();
}

class _EventInboxScreenState extends State<EventInboxScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _events = [];

  /// All distinct teams found in events (for filter dropdown).
  List<_TeamOption> _teamOptions = [];

  /// null = "Alle Teams"
  String? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final events = await EventService.fetchEvents(teamId: _selectedTeamId);
      if (!mounted) return;

      // Build team filter options from all loaded events.
      // We always load all teams when building options, but filter via query.
      final teamMap = <String, String>{};
      for (final ev in events) {
        final tid = EventService.getTeamId(ev);
        if (tid != null && !teamMap.containsKey(tid)) {
          // Use team_id as label fallback; the payload may have a team name
          // in the future, but for now we fetch it from the event context.
          teamMap[tid] = tid;
        }
      }

      setState(() {
        _events = events;
        // Only rebuild team options when showing "all" (unfiltered)
        if (_selectedTeamId == null) {
          _teamOptions = teamMap.entries
              .map((e) => _TeamOption(id: e.key, label: e.value))
              .toList();
          _loadTeamNames(); // async name resolution
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CsToast.error(context, 'Events konnten nicht geladen werden.');
    }
  }

  /// Resolve team names for the filter dropdown (best-effort).
  Future<void> _loadTeamNames() async {
    if (_teamOptions.isEmpty) return;
    try {
      final ids = _teamOptions.map((t) => t.id).toList();
      final rows = await Supabase.instance.client
          .from('cs_teams')
          .select('id, name')
          .inFilter('id', ids);
      if (!mounted) return;
      final nameMap = <String, String>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        nameMap[r['id'] as String] = r['name'] as String? ?? r['id'] as String;
      }
      setState(() {
        _teamOptions = _teamOptions.map((t) {
          return _TeamOption(id: t.id, label: nameMap[t.id] ?? t.id);
        }).toList();
      });
    } catch (_) {
      // non-critical – dropdown just shows IDs
    }
  }

  /// Tap handler: always marks read, then navigates if match_id present.
  Future<void> _onTap(Map<String, dynamic> event) async {
    // Always mark as read on tap (idempotent RPC – no-op if already read).
    try {
      await EventService.markRead(event['id'] as String);
    } catch (_) {
      // best-effort; don't block navigation
    }

    final matchId = EventService.getMatchId(event);
    final teamId = EventService.getTeamId(event);

    // Navigate to match if possible – soft-fail on missing/deleted match.
    if (matchId != null && teamId != null) {
      try {
        final match = await Supabase.instance.client
            .from('cs_matches')
            .select()
            .eq('id', matchId)
            .maybeSingle();

        if (!mounted) return;

        if (match == null) {
          CsToast.info(context, 'Match nicht verfügbar (gelöscht oder archiviert).');
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MatchDetailScreen(
                matchId: matchId,
                teamId: teamId,
                match: match,
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        CsToast.error(context, 'Match nicht verfügbar.');
        debugPrint('EventInbox: match load failed: $e');
      }
    }

    // Reload to update read state
    _load();
  }

  Future<void> _markAllRead() async {
    try {
      await EventService.markAllRead();
      _load();
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Events konnten nicht geladen werden.');
    }
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tagen';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _events.where(EventService.isUnread).length;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: 'Benachrichtigungen ($unreadCount)',
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Alle gelesen'),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // ── Team filter dropdown ──────────────────────────────
          if (_teamOptions.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedTeamId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Team-Filter',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Alle Teams'),
                  ),
                  ..._teamOptions.map(
                    (t) => DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(t.label, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedTeamId = value);
                  _load();
                },
              ),
            ),

          // ── Event list ────────────────────────────────────────
          Expanded(
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Column(
                      children: List.generate(5, (_) => const CsSkeletonCard()),
                    ),
                  )
                : _events.isEmpty
                ? Center(
                    child: CsEmptyState(
                      icon: Icons.notifications_none,
                      title: 'Keine neuen Events',
                      subtitle: 'Sobald es Neuigkeiten gibt, siehst du sie hier.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: _events.length,
                      itemBuilder: (context, i) {
                        final ev = _events[i];
                        final isUnread = EventService.isUnread(ev);
                        final eventType = ev['event_type'] as String? ?? '';
                        final title = EventService.formatTitle(ev);
                        final body = EventService.formatBody(ev);
                        final hasMatch = EventService.getMatchId(ev) != null;

                        return CsAnimatedEntrance.staggered(
                          index: i,
                          child: CsCard(
                            accentBarColor: isUnread ? CsColors.blue : null,
                            onTap: () => _onTap(ev),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: (isUnread
                                            ? CsColors.blue
                                            : CsColors.gray500)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      CsRadii.sm,
                                    ),
                                  ),
                                  child: Icon(
                                    EventService.eventIcon(eventType),
                                    color: isUnread
                                        ? CsColors.blue
                                        : CsColors.gray400,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: CsTextStyles.onDarkPrimary
                                            .copyWith(
                                          fontWeight: isUnread
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        style: CsTextStyles.onDarkSecondary
                                            .copyWith(fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _timeAgo(
                                          ev['created_at'] as String?,
                                        ),
                                        style: CsTextStyles.onDarkTertiary
                                            .copyWith(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                if (hasMatch || isUnread) ...[
                                  const SizedBox(width: 8),
                                  Column(
                                    children: [
                                      if (isUnread)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: CsColors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      if (hasMatch)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            top: isUnread ? 8 : 0,
                                          ),
                                          child: const Icon(
                                            Icons.chevron_right,
                                            size: 18,
                                            color: CsColors.blue,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Simple value holder for team filter dropdown.
class _TeamOption {
  final String id;
  final String label;
  const _TeamOption({required this.id, required this.label});
}
