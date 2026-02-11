import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import 'match_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final notifs = await NotificationService.getMyNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifs;
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

  Future<void> _onTap(Map<String, dynamic> notif) async {
    // Mark as read
    if (notif['read_at'] == null) {
      try {
        await NotificationService.markRead(notif['id'] as String);
      } catch (_) {}
    }

    final type = notif['type'] as String? ?? '';
    final matchId = notif['match_id'] as String?;
    final teamId = notif['team_id'] as String?;

    // Navigate to match for lineup notifications (published, auto-promotion, etc.)
    final lineupTypes = {
      'lineup_published',
      'auto_promotion',
      'auto_promotion_captain',
      'no_reserve_available',
    };
    if (matchId != null && teamId != null && lineupTypes.contains(type)) {
      try {
        final match = await Supabase.instance.client
            .from('cs_matches')
            .select()
            .eq('id', matchId)
            .single();

        if (!mounted) return;

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
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spiel konnte nicht geladen werden: $e')),
        );
      }
    }

    // Reload to show read state
    _load();
  }

  Future<void> _markAllRead() async {
    try {
      await NotificationService.markAllRead();
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'lineup_published':
        return Icons.campaign;
      case 'lineup_selected':
      case 'selected':
        return Icons.sports_tennis;
      case 'promoted_to_starter':
      case 'promoted':
      case 'auto_promotion':
        return Icons.arrow_upward;
      case 'auto_promotion_captain':
        return Icons.swap_horiz;
      case 'no_reserve_available':
        return Icons.warning_amber;
      case 'lineup_generated':
      case 'roster_generated':
        return Icons.list_alt;
      case 'reserve_requested':
        return Icons.swap_horiz;
      case 'slot_confirmed':
        return Icons.check_circle;
      case 'no_reserves_left':
        return Icons.warning;
      case 'roster_changed':
        return Icons.swap_horiz;
      default:
        return Icons.notifications;
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
    final unreadCount =
        _notifications.where((n) => n['read_at'] == null).length;

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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
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
                    itemCount: _notifications.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      final isUnread = n['read_at'] == null;
                      final type = n['type'] as String? ?? '';

                      final title =
                          NotificationService.formatTitle(n);
                      final body =
                          NotificationService.formatMessage(n);

                      // Show a "navigate" hint for lineup-related notifications
                      final navTypes = {
                        'lineup_published',
                        'auto_promotion',
                        'auto_promotion_captain',
                        'no_reserve_available',
                      };
                      final hasNav =
                          navTypes.contains(type) &&
                          n['match_id'] != null;

                      return ListTile(
                        tileColor:
                            isUnread ? Colors.blue.shade50 : null,
                        leading: Icon(
                          _notifIcon(type),
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
                          '$body\n${_timeAgo(n['created_at'] as String?)}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasNav)
                              const Icon(Icons.chevron_right,
                                  size: 20, color: Colors.blue),
                            if (isUnread)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        onTap: () => _onTap(n),
                      );
                    },
                  ),
                ),
    );
  }
}
