import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
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
                title: title.isNotEmpty ? title : 'Lineup',
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
  static String formatTitle(Map<String, dynamic> notif, [AppLocalizations? l]) {
    final title = notif['title'] as String?;
    if (title != null && title.isNotEmpty) return title;

    final type = notif['type'] as String? ?? '';
    switch (type) {
      case 'lineup_published':
        return l?.lineupPublished ?? 'Aufstellung veröffentlicht';
      case 'lineup_selected':
        return l?.notifTitleLineup ?? 'Aufstellung';
      case 'reserve_requested':
        return l?.notifTitleSubRequest ?? 'Ersatzanfrage';
      case 'promoted_to_starter':
      case 'auto_promotion':
        return l?.notifTitlePromotion ?? 'Nachrücker';
      case 'auto_promotion_captain':
        return l?.notifTitleAutoPromotion ?? 'Auto-Nachrücken';
      case 'no_reserve_available':
        return l?.noReserveAvailable ?? 'Kein Ersatz verfügbar';
      case 'lineup_generated':
        return l?.notifTitleLineupGenerated ?? 'Aufstellung erstellt';
      case 'slot_confirmed':
        return l?.notifTitleConfirmation ?? 'Bestätigung';
      case 'no_reserves_left':
        return l?.notifTitleWarning ?? 'Achtung';
      case 'selected':
        return l?.notifTitleLineup ?? 'Aufstellung';
      case 'promoted':
        return l?.notifTitlePromoted ?? 'Beförderung';
      case 'roster_generated':
        return l?.notifTitleLineup ?? 'Aufstellung';
      // ── Business notification types ───────────────────────
      case 'expense_added':
        return 'Neue Spese';
      case 'expense_share_paid':
        return 'Spese bezahlt';
      case 'expense_share_due':
        return 'Offene Spese';
      case 'dinner_rsvp_yes':
        return 'Essen: Zusage';
      case 'dinner_rsvp':
        final p = notif['payload'];
        final dp = p is Map<String, dynamic> ? p : <String, dynamic>{};
        final dStatus = dp['status'] as String? ?? '';
        if (dStatus == 'yes') return 'Essen: Zusage';
        if (dStatus == 'no') return 'Essen: Absage';
        if (dStatus == 'maybe') return 'Essen: Unsicher';
        return 'Essen';
      case 'availability_changed':
        final p = notif['payload'];
        final ap = p is Map<String, dynamic> ? p : <String, dynamic>{};
        final aStatus = ap['status'] as String? ?? '';
        if (aStatus == 'yes') return 'Verfügbarkeit: Zugesagt';
        if (aStatus == 'no') return 'Verfügbarkeit: Abgesagt';
        if (aStatus == 'maybe') return 'Verfügbarkeit: Unsicher';
        return 'Verfügbarkeit';
      case 'carpool_offered':
        return 'Neue Fahrgemeinschaft';
      case 'carpool_passenger_joined':
        return 'Mitfahrer';
      case 'carpool_passenger_left':
        return 'Mitfahrer ausgestiegen';
      case 'sub_request':
        return l?.notifTitleSubRequest ?? 'Ersatzanfrage';
      case 'sub_accepted':
        return 'Ersatz bestätigt';
      case 'sub_declined':
        return 'Ersatz abgelehnt';
      case 'sub_chain_next':
        return 'Nächster Ersatz angefragt';
      case 'match_reminder_24h':
        return 'Spielerinnerung – morgen';
      case 'match_reminder_2h':
        return 'Gleich gehts los!';
      default:
        return 'Lineup';
    }
  }

  /// Body text from DB column or type-based fallback.
  static String formatMessage(Map<String, dynamic> notif, [AppLocalizations? l]) {
    final body = notif['body'] as String?;
    if (body != null && body.isNotEmpty) return body;

    final type = notif['type'] as String? ?? '';
    final payload = notif['payload'];
    final p = payload is Map<String, dynamic> ? payload : <String, dynamic>{};

    switch (type) {
      case 'lineup_published':
        return l?.notifBodyLineupOnline
            ?? 'Die Aufstellung ist online. Schau sie dir an!';
      case 'lineup_selected':
        final st = p['slot_type'] == 'starter'
            ? (l?.starterLabel ?? 'Starter')
            : (l?.reserveLabel ?? 'Ersatz');
        final pos = p['position'] ?? '?';
        return l?.notifBodySelectedAs(st, '$pos')
            ?? 'Du wurdest als $st (Pos. $pos) aufgestellt';
      case 'reserve_requested':
        final pos = p['position'] ?? '?';
        return l?.notifBodyReserveConfirm('$pos')
            ?? 'Du bist Ersatz $pos. Bitte bestätige.';
      case 'promoted_to_starter':
        final pos = p['new_position'] ?? '?';
        return l?.notifBodyPromotedToStarter('$pos')
            ?? 'Du wurdest zum Starter (Pos. $pos) befördert 🎉';
      case 'auto_promotion':
        return l?.notifBodyAutoPromoted
            ?? 'Du bist als Ersatz nachgerückt und spielst nun mit 🎉';
      case 'auto_promotion_captain':
        final from = p['absent_name'] ?? '?';
        final to = p['promoted_name'] ?? '?';
        return l?.notifBodyAutoPromotionCaptain('$to', '$from')
            ?? 'Auto-Nachrücken: $to ersetzt $from';
      case 'no_reserve_available':
        final absent = p['absent_name'] ?? '?';
        return l?.notifBodyNoReserve('$absent')
            ?? '$absent hat abgesagt – kein Ersatz verfügbar!';
      case 'lineup_generated':
        final s = p['starters'] ?? 0;
        final r = p['reserves'] ?? 0;
        return l?.notifBodyLineupCreated('$s', '$r')
            ?? 'Aufstellung erstellt: $s Starter, $r Ersatz';
      case 'slot_confirmed':
        return l?.notifBodyPlayerConfirmed ?? 'Ein Spieler hat bestätigt';
      case 'no_reserves_left':
        return l?.notifBodyNoReservesLeft
            ?? 'Keine Ersatzspieler mehr verfügbar!';
      case 'selected':
        final role = p['role'] == 'starter'
            ? (l?.starterLabel ?? 'Starter')
            : (l?.reserveLabel ?? 'Ersatz');
        final pos = p['position'] ?? '?';
        return l?.notifBodySelectedAs(role, '$pos')
            ?? 'Du wurdest als $role (Pos. $pos) aufgestellt';
      case 'promoted':
        final pos = p['new_position'] ?? '?';
        return l?.notifBodyPromotedToPos('$pos')
            ?? 'Du wurdest zum Starter befördert (Pos. $pos) 🎉';
      case 'roster_generated':
        final s = p['starters'] ?? 0;
        final sub = p['substitutes'] ?? 0;
        return l?.notifBodyLineupCreated('$s', '$sub')
            ?? 'Aufstellung erstellt: $s Starter, $sub Ersatz';
      case 'roster_changed':
        return l?.notifBodyRosterChanged ?? 'Die Aufstellung wurde geändert';
      case 'needs_response':
        return l?.notifBodyNeedsResponse
            ?? 'Bitte bestätige deine Aufstellung';
      // ── Business notification types ───────────────────────
      case 'expense_added':
        final payer = p['payer_name'] ?? '?';
        final t = p['title'] ?? '?';
        return '$payer: $t';
      case 'expense_share_paid':
        final debtor = p['debtor_name'] ?? '?';
        final expTitle = p['expense_title'] ?? '?';
        return '$debtor hat bezahlt ($expTitle)';
      case 'expense_share_due':
        final payerName = p['payer_name'] ?? '?';
        final expTitle2 = p['expense_title'] ?? '?';
        final shareCents = p['share_cents'];
        final amt = shareCents is num
            ? (shareCents / 100).toStringAsFixed(2)
            : '?';
        return '$amt CHF an $payerName ($expTitle2)';
      case 'dinner_rsvp_yes':
        final name = p['player_name'] ?? '?';
        return '$name isst mit';
      case 'dinner_rsvp':
        final dName = p['player_name'] ?? '?';
        final dSt = p['status'] as String? ?? '';
        if (dSt == 'yes') return '$dName isst mit';
        if (dSt == 'no') return '$dName isst nicht mit';
        if (dSt == 'maybe') return '$dName ist unsicher (Essen)';
        return '$dName: Essen $dSt';
      case 'availability_changed':
        final aName = p['player_name'] ?? '?';
        final aSt = p['status'] as String? ?? '';
        if (aSt == 'yes') return '$aName hat zugesagt';
        if (aSt == 'no') return '$aName hat abgesagt';
        if (aSt == 'maybe') return '$aName ist unsicher';
        return '$aName: Verfügbarkeit $aSt';
      case 'carpool_offered':
        final driver = p['driver_name'] ?? '?';
        final seats = p['seats_total'] ?? '?';
        return '$driver bietet Fahrt an ($seats Plätze)';
      case 'carpool_passenger_joined':
        final passenger = p['passenger_name'] ?? '?';
        return '$passenger fährt bei dir mit';
      case 'carpool_passenger_left':
        final passengerLeft = p['passenger_name'] ?? '?';
        return '$passengerLeft fährt nicht mehr mit';
      case 'sub_request':
        final origName = p['original_name'] ?? '?';
        return 'Du wurdest als Ersatz angefragt für $origName';
      case 'sub_accepted':
        final subName = p['substitute_name'] ?? '?';
        final origNameAcc = p['original_name'] ?? '?';
        return '$subName ersetzt $origNameAcc';
      case 'sub_declined':
        final declinedName = p['substitute_name'] ?? '?';
        final origNameDec = p['original_name'] ?? '?';
        return '$declinedName hat die Ersatzanfrage abgelehnt (für $origNameDec)';
      case 'sub_chain_next':
        final nextName = p['next_substitute_name'] ?? '?';
        final origNameChain = p['original_name'] ?? '?';
        return '$nextName wurde als nächster Ersatz angefragt (für $origNameChain)';
      case 'match_reminder_24h':
        return 'Morgen steht ein Match an – sei bereit!';
      case 'match_reminder_2h':
        return 'In 2 Stunden gehts los – sei bereit!';
      default:
        return type;
    }
  }
}
