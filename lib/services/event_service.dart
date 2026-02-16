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
      default:
        return Icons.notifications;
    }
  }
}
