import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_notification_service.dart';

/// In-app notification service.
///
/// The `cs_notifications` table uses `recipient_user_id` (not `user_id`)
/// as the column identifying who the notification is for.
class NotificationService {
  static final _supabase = Supabase.instance.client;
  static RealtimeChannel? _channel;

  // ── Queries ────────────────────────────────────────────────

  /// Load all notifications for the current user (newest first).
  static Future<List<Map<String, dynamic>>> getMyNotifications({
    int limit = 50,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    final rows = await _supabase
        .from('cs_notifications')
        .select()
        .eq('recipient_user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Count unread notifications.
  static Future<int> getUnreadCount() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return 0;

    final rows = await _supabase
        .from('cs_notifications')
        .select('id')
        .eq('recipient_user_id', uid)
        .isFilter('read_at', null);
    return (rows as List).length;
  }

  /// Mark a single notification as read (via RPC).
  static Future<void> markRead(String notificationId) async {
    await _supabase.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  /// Mark all unread notifications as read (direct update, guarded by RLS).
  static Future<void> markAllRead() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    await _supabase
        .from('cs_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_user_id', uid)
        .isFilter('read_at', null);
  }

  // ── Realtime ───────────────────────────────────────────────

  /// Subscribe to new notifications via Supabase Realtime.
  /// Also fires a local push notification on each new insert.
  static void subscribe({
    required void Function(Map<String, dynamic> notification) onInsert,
  }) {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    _channel?.unsubscribe();
    _channel = _supabase
        .channel('cs_notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'cs_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: uid,
          ),
          callback: (payload) {
            final record = Map<String, dynamic>.from(payload.newRecord);

            // UI callback (SnackBar / setState)
            onInsert(record);

            // Local push notification
            final title = record['title'] as String? ?? formatTitle(record);
            final body = record['body'] as String? ?? formatMessage(record);
            if (title.isNotEmpty || body.isNotEmpty) {
              LocalNotificationService.show(
                title: title.isNotEmpty ? title : 'CourtSwiss',
                body: body,
                payload: record['match_id'] as String?,
              );
            }
          },
        )
        .subscribe();
  }

  /// Unsubscribe from Realtime notifications.
  static void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }

  // ── Formatting ─────────────────────────────────────────────

  /// Short title from DB column or type-based fallback.
  static String formatTitle(Map<String, dynamic> notif) {
    final title = notif['title'] as String?;
    if (title != null && title.isNotEmpty) return title;

    final type = notif['type'] as String? ?? '';
    switch (type) {
      case 'lineup_published':
        return 'Aufstellung veröffentlicht';
      case 'lineup_selected':
        return 'Aufstellung';
      case 'reserve_requested':
        return 'Ersatzanfrage';
      case 'promoted_to_starter':
      case 'auto_promotion':
        return 'Nachrücker';
      case 'auto_promotion_captain':
        return 'Auto-Nachrücken';
      case 'no_reserve_available':
        return 'Kein Ersatz verfügbar';
      case 'lineup_generated':
        return 'Aufstellung erstellt';
      case 'slot_confirmed':
        return 'Bestätigung';
      case 'no_reserves_left':
        return 'Achtung';
      case 'selected':
        return 'Aufstellung';
      case 'promoted':
        return 'Beförderung';
      case 'roster_generated':
        return 'Aufstellung';
      default:
        return 'CourtSwiss';
    }
  }

  /// Body text from DB column or type-based fallback.
  static String formatMessage(Map<String, dynamic> notif) {
    final body = notif['body'] as String?;
    if (body != null && body.isNotEmpty) return body;

    final type = notif['type'] as String? ?? '';
    final payload = notif['payload'];
    final p = payload is Map<String, dynamic> ? payload : <String, dynamic>{};

    switch (type) {
      case 'lineup_published':
        return 'Die Aufstellung ist online. Schau sie dir an!';
      case 'lineup_selected':
        final st = p['slot_type'] == 'starter' ? 'Starter' : 'Ersatz';
        final pos = p['position'] ?? '?';
        return 'Du wurdest als $st (Pos. $pos) aufgestellt';
      case 'reserve_requested':
        final pos = p['position'] ?? '?';
        return 'Du bist Ersatz $pos. Bitte bestätige.';
      case 'promoted_to_starter':
        final pos = p['new_position'] ?? '?';
        return 'Du wurdest zum Starter (Pos. $pos) befördert 🎉';
      case 'auto_promotion':
        return 'Du bist als Ersatz nachgerückt und spielst nun mit 🎉';
      case 'auto_promotion_captain':
        final from = p['absent_name'] ?? '?';
        final to = p['promoted_name'] ?? '?';
        return 'Auto-Nachrücken: $to ersetzt $from';
      case 'no_reserve_available':
        final absent = p['absent_name'] ?? '?';
        return '$absent hat abgesagt – kein Ersatz verfügbar!';
      case 'lineup_generated':
        final s = p['starters'] ?? 0;
        final r = p['reserves'] ?? 0;
        return 'Aufstellung erstellt: $s Starter, $r Ersatz';
      case 'slot_confirmed':
        return 'Ein Spieler hat bestätigt';
      case 'no_reserves_left':
        return 'Keine Ersatzspieler mehr verfügbar!';
      case 'selected':
        final role = p['role'] == 'starter' ? 'Starter' : 'Ersatz';
        final pos = p['position'] ?? '?';
        return 'Du wurdest als $role (Pos. $pos) aufgestellt';
      case 'promoted':
        final pos = p['new_position'] ?? '?';
        return 'Du wurdest zum Starter befördert (Pos. $pos) 🎉';
      case 'roster_generated':
        final s = p['starters'] ?? 0;
        final sub = p['substitutes'] ?? 0;
        return 'Aufstellung erstellt: $s Starter, $sub Ersatz';
      case 'roster_changed':
        return 'Die Aufstellung wurde geändert';
      case 'needs_response':
        return 'Bitte bestätige deine Aufstellung';
      default:
        return type;
    }
  }
}
