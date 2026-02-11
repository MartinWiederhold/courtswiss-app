import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/event_service.dart';
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
      final events = await EventService.fetchEvents(
        teamId: _selectedTeamId,
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Match nicht verfügbar (gelöscht oder archiviert).'),
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match nicht verfügbar.'),
          ),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Benachrichtigungen ($unreadCount)'),
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
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Alle Teams'),
                  ),
                  ..._teamOptions.map(
                    (t) => DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(
                        t.label,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('Keine Benachrichtigungen',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _events.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final ev = _events[i];
                            final isUnread = EventService.isUnread(ev);
                            final eventType =
                                ev['event_type'] as String? ?? '';
                            final title = EventService.formatTitle(ev);
                            final body = EventService.formatBody(ev);
                            final hasMatch =
                                EventService.getMatchId(ev) != null;

                            return ListTile(
                              tileColor:
                                  isUnread ? Colors.blue.shade50 : null,
                              leading: Icon(
                                EventService.eventIcon(eventType),
                                color:
                                    isUnread ? Colors.blue : Colors.grey,
                              ),
                              title: Text(
                                title,
                                style: TextStyle(
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '$body\n${_timeAgo(ev['created_at'] as String?)}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasMatch)
                                    const Icon(Icons.chevron_right,
                                        size: 20, color: Colors.blue),
                                  if (isUnread)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin:
                                          const EdgeInsets.only(left: 6),
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () => _onTap(ev),
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
