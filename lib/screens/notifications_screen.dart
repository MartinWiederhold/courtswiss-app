import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';
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
      CsToast.error(context, 'Benachrichtigungen konnten nicht geladen werden.');
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
        CsToast.error(context, 'Spiel konnte nicht geladen werden.');
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
      CsToast.error(context, 'Benachrichtigungen konnten nicht geladen werden.');
    }
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'lineup_published':
        return Icons.campaign_outlined;
      case 'lineup_selected':
      case 'selected':
        return Icons.sports_tennis;
      case 'promoted_to_starter':
      case 'promoted':
      case 'auto_promotion':
        return Icons.arrow_upward_rounded;
      case 'auto_promotion_captain':
        return Icons.swap_horiz_rounded;
      case 'no_reserve_available':
        return Icons.warning_amber_rounded;
      case 'lineup_generated':
      case 'roster_generated':
        return Icons.list_alt_rounded;
      case 'reserve_requested':
        return Icons.swap_horiz_rounded;
      case 'slot_confirmed':
        return Icons.check_circle_outline;
      case 'no_reserves_left':
        return Icons.warning_rounded;
      case 'roster_changed':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.notifications_outlined;
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
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                children: List.generate(5, (_) => const CsSkeletonCard()),
              ),
            )
          : _notifications.isEmpty
              ? Center(
                  child: CsEmptyState(
                    icon: Icons.notifications_none,
                    title: 'Alles gelesen',
                    subtitle: 'Neue Benachrichtigungen erscheinen automatisch hier.',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: _notifications.length,
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      final isUnread = n['read_at'] == null;
                      final type = n['type'] as String? ?? '';

                      final title = NotificationService.formatTitle(n);
                      final body = NotificationService.formatMessage(n);

                      final navTypes = {
                        'lineup_published',
                        'auto_promotion',
                        'auto_promotion_captain',
                        'no_reserve_available',
                      };
                      final hasNav =
                          navTypes.contains(type) && n['match_id'] != null;

                      return CsAnimatedEntrance.staggered(
                        index: i,
                        child: _NotificationCard(
                          title: title,
                          body: body,
                          timeAgo: _timeAgo(n['created_at'] as String?),
                          icon: _notifIcon(type),
                          isUnread: isUnread,
                          hasNav: hasNav,
                          onTap: () => _onTap(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  White notification card – premium, light, consistent with app
// ─────────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
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
            color: Color(0x0F000000), // ~6% black
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x08000000), // ~3% black
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
                // ── Icon container (black pill, white icon) ──
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
                          color: const Color(0xFF111827), // gray-900
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
                          color: Color(0xFFA0A0A0), // light gray
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
                            color: Color(0xFF3B82F6), // subtle blue dot
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
