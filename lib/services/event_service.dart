import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';

/// Service for the cs_events + cs_event_reads event system.
///
/// cs_events stores team-scoped events (broadcast or per-user).
/// cs_event_reads tracks per-user read status (separate table).
///
/// Events are created automatically by DB triggers:
///   - publish lineup  → trg_emit_lineup_published_event
///   - auto-promotion  → trg_emit_lineup_event_to_cs_events
///   - no reserve      → trg_emit_lineup_event_to_cs_events
class EventService {
  static final _supabase = Supabase.instance.client;

  // ── Payload helpers ────────────────────────────────────────

  /// Extract match_id from the row's column first, then from payload.
  /// Robust for both legacy rows (match_id only in column) and enriched
  /// rows (match_id also in payload).
  static String? getMatchId(Map<String, dynamic> event) {
    final column = event['match_id'];
    if (column != null && column is String && column.isNotEmpty) return column;
    final payload = event['payload'];
    if (payload is Map<String, dynamic>) {
      final fromPayload = payload['match_id'];
      if (fromPayload != null &&
          fromPayload is String &&
          fromPayload.isNotEmpty) {
        return fromPayload;
      }
    }
    return null;
  }

  /// Extract team_id from column first, then from payload.
  static String? getTeamId(Map<String, dynamic> event) {
    final column = event['team_id'];
    if (column != null && column is String && column.isNotEmpty) return column;
    final payload = event['payload'];
    if (payload is Map<String, dynamic>) {
      final fromPayload = payload['team_id'];
      if (fromPayload != null &&
          fromPayload is String &&
          fromPayload.isNotEmpty) {
        return fromPayload;
      }
    }
    return null;
  }

  // ── Queries ──────────────────────────────────────────────────

  /// Load events visible to the current user (newest first).
  /// Each event includes a `cs_event_reads` array: empty = unread,
  /// `[{read_at: ...}]` = read.
  ///
  /// [teamId] – optional filter; when non-null only events for that team
  /// are returned.
  static Future<List<Map<String, dynamic>>> fetchEvents({
    int limit = 50,
    String? teamId,
  }) async {
    try {
      // PostgREST LEFT JOIN via FK embed.
      // RLS on cs_events filters to visible events.
      // RLS on cs_event_reads filters to auth.uid() reads only.
      var query = _supabase
          .from('cs_events')
          .select('*, cs_event_reads(read_at)');
      if (teamId != null) {
        query = query.eq('team_id', teamId);
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('EventService.fetchEvents embed failed, falling back: $e');
      return _fetchEventsFallback(limit: limit, teamId: teamId);
    }
  }

  /// Fallback: two separate queries (events + reads), merged in Dart.
  static Future<List<Map<String, dynamic>>> _fetchEventsFallback({
    int limit = 50,
    String? teamId,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    var query = _supabase.from('cs_events').select();
    if (teamId != null) {
      query = query.eq('team_id', teamId);
    }
    final events = await query
        .order('created_at', ascending: false)
        .limit(limit);

    final eventList = List<Map<String, dynamic>>.from(events);
    final ids = eventList.map((e) => e['id'] as String).toList();
    if (ids.isEmpty) return eventList;

    final reads = await _supabase
        .from('cs_event_reads')
        .select('event_id, read_at')
        .eq('user_id', uid)
        .inFilter('event_id', ids);

    final readMap = <String, String?>{};
    for (final r in List<Map<String, dynamic>>.from(reads)) {
      readMap[r['event_id'] as String] = r['read_at'] as String?;
    }

    return eventList.map((e) {
      final map = Map<String, dynamic>.from(e);
      final readAt = readMap[e['id'] as String];
      map['cs_event_reads'] = readAt != null
          ? [
              {'read_at': readAt},
            ]
          : <Map<String, dynamic>>[];
      return map;
    }).toList();
  }

  /// Returns the number of unread events across all teams (via RPC).
  static Future<int> fetchUnreadCount() async {
    try {
      final result = await _supabase.rpc('cs_unread_event_count');
      return (result as int?) ?? 0;
    } catch (e) {
      debugPrint('EventService.fetchUnreadCount error: $e');
      return 0;
    }
  }

  // ── Mutations ────────────────────────────────────────────────

  /// Mark a single event as read (idempotent).
  static Future<void> markRead(String eventId) async {
    await _supabase.rpc('cs_mark_event_read', params: {'p_event_id': eventId});
  }

  /// Mark all visible events as read.
  static Future<void> markAllRead() async {
    await _supabase.rpc('cs_mark_all_events_read');
  }

  // ── Display helpers ──────────────────────────────────────────

  /// Check whether an event row is unread.
  static bool isUnread(Map<String, dynamic> event) {
    final reads = event['cs_event_reads'];
    if (reads is List) return reads.isEmpty;
    return true; // no read data → treat as unread
  }

  /// Human-readable title.
  /// Priority: payload-specific title → DB title column → type-based fallback.
  static String formatTitle(Map<String, dynamic> event, [AppLocalizations? l]) {
    final payload = event['payload'] is Map<String, dynamic>
        ? event['payload'] as Map<String, dynamic>
        : <String, dynamic>{};

    // 1) Payload may carry a display title (future-proof)
    final payloadTitle = payload['title'] as String?;
    if (payloadTitle != null && payloadTitle.isNotEmpty) return payloadTitle;

    // 2) DB column title
    final title = event['title'] as String?;
    if (title != null && title.isNotEmpty) return title;

    // 3) Type-based fallback
    switch (event['event_type'] as String? ?? '') {
      case 'lineup_published':
        return l?.lineupPublished ?? 'Aufstellung veröffentlicht';
      case 'replacement_promoted':
        return l?.replacementPromoted ?? 'Ersatz nachgerückt';
      case 'no_reserve_available':
        return l?.noReserveAvailable ?? 'Kein Ersatz verfügbar';
      case 'availability_changed':
        final status = payload['status'] as String? ?? '';
        if (status == 'yes') return 'Verfügbarkeit: Zugesagt';
        if (status == 'no') return 'Verfügbarkeit: Abgesagt';
        if (status == 'maybe') return 'Verfügbarkeit: Unsicher';
        return 'Verfügbarkeit';
      case 'dinner_rsvp':
        final dStatus = payload['status'] as String? ?? '';
        if (dStatus == 'yes') return 'Essen: Zusage';
        if (dStatus == 'no') return 'Essen: Absage';
        if (dStatus == 'maybe') return 'Essen: Unsicher';
        return 'Essen';
      case 'carpool_offered':
        return 'Neue Fahrgemeinschaft';
      case 'carpool_passenger_joined':
        return 'Mitfahrer';
      case 'carpool_passenger_left':
        return 'Mitfahrer ausgestiegen';
      case 'sub_request':
        return 'Ersatzanfrage';
      case 'sub_accepted':
        return 'Ersatz bestätigt';
      case 'sub_declined':
        return 'Ersatz abgelehnt';
      case 'sub_chain_next':
        return 'Nächster Ersatz angefragt';
      case 'expense_added':
        return 'Neue Spese';
      case 'expense_share_paid':
        return 'Spese bezahlt';
      case 'expense_share_due':
        return 'Offene Spese';
      case 'match_reminder_24h':
        return 'Spielerinnerung – morgen';
      case 'match_reminder_2h':
        return 'Gleich gehts los!';
      default:
        return 'Lineup';
    }
  }

  /// Human-readable body.
  /// Priority: payload-constructed body → DB body column → type-based fallback.
  static String formatBody(Map<String, dynamic> event, [AppLocalizations? l]) {
    final payload = event['payload'] is Map<String, dynamic>
        ? event['payload'] as Map<String, dynamic>
        : <String, dynamic>{};

    final eventType = event['event_type'] as String? ?? '';

    // 1) Try to build body from payload keys (richer than static DB body).
    switch (eventType) {
      case 'lineup_published':
        // If payload has match info, we could enhance, but the DB body is fine.
        break;
      case 'replacement_promoted':
        final inName = payload['in_name'] ?? payload['promoted_name'];
        final outName = payload['out_name'] ?? payload['absent_name'];
        if (inName != null && outName != null) {
          return l?.eventBodyReplaced('$inName', '$outName')
              ?? '$inName ersetzt $outName';
        }
        break;
      case 'no_reserve_available':
        final absent = payload['out_name'] ?? payload['absent_name'];
        if (absent != null) {
          return l?.notifBodyNoReserve('$absent')
              ?? '$absent hat abgesagt – kein Ersatz verfügbar!';
        }
        break;
    }

    // 2) DB body column
    final body = event['body'] as String?;
    if (body != null && body.isNotEmpty) return body;

    // 3) Fallback
    switch (eventType) {
      case 'lineup_published':
        return l?.notifBodyLineupOnline
            ?? 'Die Aufstellung ist online. Schau sie dir an!';
      case 'replacement_promoted':
        final to = payload['promoted_name'] ?? payload['in_name'] ?? '?';
        final from = payload['absent_name'] ?? payload['out_name'] ?? '?';
        return l?.eventBodyReplaced('$to', '$from')
            ?? '$to ersetzt $from';
      case 'no_reserve_available':
        final absent = payload['absent_name'] ?? payload['out_name'] ?? '?';
        return l?.notifBodyNoReserve('$absent')
            ?? '$absent hat abgesagt – kein Ersatz verfügbar!';
      case 'availability_changed':
        final aName = payload['player_name'] ?? '?';
        final aSt = payload['status'] as String? ?? '';
        if (aSt == 'yes') return '$aName hat zugesagt';
        if (aSt == 'no') return '$aName hat abgesagt';
        if (aSt == 'maybe') return '$aName ist unsicher';
        return '$aName: Verfügbarkeit $aSt';
      case 'dinner_rsvp':
        final dName = payload['player_name'] ?? '?';
        final dSt = payload['status'] as String? ?? '';
        if (dSt == 'yes') return '$dName isst mit';
        if (dSt == 'no') return '$dName isst nicht mit';
        if (dSt == 'maybe') return '$dName ist unsicher (Essen)';
        return '$dName: Essen $dSt';
      case 'carpool_offered':
        final driver = payload['driver_name'] ?? '?';
        final seats = payload['seats_total'] ?? '?';
        return '$driver bietet Fahrt an ($seats Plätze)';
      case 'carpool_passenger_joined':
        final passenger = payload['passenger_name'] ?? '?';
        return '$passenger fährt bei dir mit';
      case 'carpool_passenger_left':
        final passengerLeft = payload['passenger_name'] ?? '?';
        return '$passengerLeft fährt nicht mehr mit';
      case 'sub_request':
        final origName = payload['original_name'] ?? '?';
        return 'Du wurdest als Ersatz angefragt für $origName';
      case 'sub_accepted':
        final subName = payload['substitute_name'] ?? '?';
        final origAcc = payload['original_name'] ?? '?';
        return '$subName ersetzt $origAcc';
      case 'sub_declined':
        final decName = payload['substitute_name'] ?? '?';
        final origDec = payload['original_name'] ?? '?';
        return '$decName hat die Ersatzanfrage abgelehnt (für $origDec)';
      case 'sub_chain_next':
        final nextName = payload['next_substitute_name'] ?? '?';
        final origChain = payload['original_name'] ?? '?';
        return '$nextName wurde als nächster Ersatz angefragt (für $origChain)';
      case 'expense_added':
        final payer = payload['payer_name'] ?? '?';
        final t = payload['title'] ?? '?';
        return '$payer: $t';
      case 'expense_share_paid':
        final debtor = payload['debtor_name'] ?? '?';
        final expTitle = payload['expense_title'] ?? '?';
        return '$debtor hat bezahlt ($expTitle)';
      case 'expense_share_due':
        final payerName = payload['payer_name'] ?? '?';
        final expTitle2 = payload['expense_title'] ?? '?';
        final shareCents = payload['share_cents'];
        final amt = shareCents is num
            ? (shareCents / 100).toStringAsFixed(2)
            : '?';
        return '$amt CHF an $payerName ($expTitle2)';
      case 'match_reminder_24h':
        return 'Morgen steht ein Match an – sei bereit!';
      case 'match_reminder_2h':
        return 'In 2 Stunden gehts los – sei bereit!';
      default:
        return eventType;
    }
  }

  /// Icon for a given event type.
  static IconData eventIcon(String eventType) {
    switch (eventType) {
      case 'lineup_published':
        return Icons.campaign;
      case 'replacement_promoted':
        return Icons.arrow_upward;
      case 'no_reserve_available':
        return Icons.warning_amber;
      case 'availability_changed':
        return Icons.event_available;
      case 'dinner_rsvp':
      case 'dinner_rsvp_yes':
        return Icons.restaurant;
      case 'carpool_offered':
        return Icons.directions_car;
      case 'carpool_passenger_joined':
        return Icons.person_add;
      case 'carpool_passenger_left':
        return Icons.person_remove;
      case 'sub_request':
        return Icons.swap_horiz;
      case 'sub_accepted':
        return Icons.check_circle;
      case 'sub_declined':
        return Icons.cancel;
      case 'sub_chain_next':
        return Icons.swap_horiz;
      case 'expense_added':
      case 'expense_share_due':
        return Icons.receipt_long;
      case 'expense_share_paid':
        return Icons.paid;
      case 'match_reminder_24h':
      case 'match_reminder_2h':
        return Icons.alarm;
      default:
        return Icons.notifications;
    }
  }
}
