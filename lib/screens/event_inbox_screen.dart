import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
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
      CsToast.error(context, AppLocalizations.of(context)!.eventsLoadError);
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
          CsToast.info(context, AppLocalizations.of(context)!.matchUnavailableDeleted);
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
        CsToast.error(context, AppLocalizations.of(context)!.matchUnavailable);
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
      CsToast.error(context, AppLocalizations.of(context)!.eventsLoadError);
    }
  }

  Future<void> _dismissEvent(int index) async {
    final ev = _events[index];
    final removed = ev;
    setState(() => _events.removeAt(index));
    try {
      await EventService.markRead(ev['id'] as String);
    } catch (e) {
      if (!mounted) return;
      setState(() => _events.insert(index, removed));
    }
  }

  Future<void> _deleteAllEvents() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteAllNotificationsConfirm),
        content: Text(l.deleteAllNotificationsBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: CsColors.error,
            ),
            child: Text(l.deleteAllNotifications),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await EventService.markAllRead();
      if (!mounted) return;
      _load();
      CsToast.success(context, l.allNotifsDeleted);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l.eventsLoadError);
    }
  }

  String _timeAgo(String? isoDate, AppLocalizations l) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l.timeJustNow;
    if (diff.inMinutes < 60) return l.timeMinutesAgo('${diff.inMinutes}');
    if (diff.inHours < 24) return l.timeHoursAgo('${diff.inHours}');
    if (diff.inDays < 7) return l.timeDaysAgo('${diff.inDays}');
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final unreadCount = _events.where(EventService.isUnread).length;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: l.notifTitleWithCount('$unreadCount'),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(l.markAllRead),
            ),
          if (_events.isNotEmpty)
            IconButton(
              onPressed: _deleteAllEvents,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: l.deleteAllNotifications,
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
                decoration: InputDecoration(
                  labelText: l.teamFilterLabel,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l.allTeams),
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
                      title: l.noNewEvents,
                      subtitle: l.noNewEventsSubtitle,
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
                        final title = EventService.formatTitle(ev, l);
                        final body = EventService.formatBody(ev, l);
                        final hasMatch = EventService.getMatchId(ev) != null;

                        return CsAnimatedEntrance.staggered(
                          index: i,
                          child: Dismissible(
                            key: ValueKey(ev['id'] as String? ?? '$i'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => _dismissEvent(i),
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              decoration: BoxDecoration(
                                color: CsColors.error,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: CsColors.white,
                                size: 24,
                              ),
                            ),
                            child: _EventCard(
                              title: title,
                              body: body,
                              timeAgo: _timeAgo(
                                ev['created_at'] as String?, l),
                              icon: EventService.eventIcon(eventType),
                              isUnread: isUnread,
                              hasNav: hasMatch,
                              onTap: () => _onTap(ev),
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

// ─────────────────────────────────────────────────────────────────
//  White event card – black icon pill, white icon
// ─────────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.title,
    required this.body,
    required this.timeAgo,
    required this.icon,
    required this.isUnread,
    required this.hasNav,
    required this.onTap,
  });

  final String title;
  final String body;
  final String timeAgo;
  final IconData icon;
  final bool isUnread;
  final bool hasNav;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: CsColors.gray200.withValues(alpha: 0.5),
          highlightColor: CsColors.gray100.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Black icon pill, white icon ──
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // ── Text column ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isUnread ? FontWeight.w700 : FontWeight.w500,
                          color: const Color(0xFF111827),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF666666),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFA0A0A0),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Unread dot + chevron ──
                if (hasNav || isUnread) ...[
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B82F6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (hasNav)
                        Padding(
                          padding: EdgeInsets.only(top: isUnread ? 8 : 0),
                          child: const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: CsColors.gray400,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
