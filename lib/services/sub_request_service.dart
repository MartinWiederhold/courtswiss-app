import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for the substitute request system (cs_sub_requests).
///
/// Flow:
///   1. Player declines → captain calls [createRequest] to find a substitute
///   2. Substitute sees pending request → calls [respond] with 'accepted'/'declined'
///   3. If accepted: lineup slot is updated automatically by the RPC
///   4. If declined: captain can call [createRequest] again to find the next candidate
class SubRequestService {
  static final _supabase = Supabase.instance.client;

  /// Create a substitute request for a match.
  /// Finds the best available candidate and creates a pending request.
  ///
  /// Returns a JSON object with:
  ///   - success: bool
  ///   - request_id: uuid (if success)
  ///   - substitute_user_id: uuid (if success)
  ///   - substitute_name: string (if success)
  ///   - reason / message: string (if no candidate found)
  static Future<Map<String, dynamic>> createRequest({
    required String matchId,
    required String originalUserId,
  }) async {
    final result = await _supabase.rpc('cs_create_sub_request', params: {
      'p_match_id': matchId,
      'p_original_user_id': originalUserId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Respond to a substitute request (accept or decline).
  ///
  /// [response] must be 'accepted' or 'declined'.
  ///
  /// Returns a JSON object with:
  ///   - success: bool
  ///   - action: 'accepted' or 'declined'
  ///   - slot_updated: bool (only if accepted)
  static Future<Map<String, dynamic>> respond({
    required String requestId,
    required String response,
  }) async {
    final result = await _supabase.rpc('cs_respond_sub_request', params: {
      'p_request_id': requestId,
      'p_response': response,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// List all pending substitute requests for the current user.
  static Future<List<Map<String, dynamic>>> listMyPendingRequests() async {
    final result = await _supabase.rpc('cs_list_my_sub_requests');
    return List<Map<String, dynamic>>.from(result as List);
  }

  /// List all sub requests for a specific match (any status).
  static Future<List<Map<String, dynamic>>> listForMatch(
      String matchId) async {
    final rows = await _supabase
        .from('cs_sub_requests')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Get a single sub request by ID.
  static Future<Map<String, dynamic>?> getRequest(String requestId) async {
    final rows = await _supabase
        .from('cs_sub_requests')
        .select()
        .eq('id', requestId)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }
}
