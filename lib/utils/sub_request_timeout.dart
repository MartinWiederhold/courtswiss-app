/// Pure utility functions for sub-request timeout handling.
/// No Flutter/Supabase dependencies – unit-testable with plain Dart.

/// Default timeout for sub-requests (30 minutes).
const Duration kSubRequestTimeout = Duration(minutes: 30);

/// Parse `expires_at` from a sub-request map.
/// Returns `null` if the field is missing, null, or unparseable.
DateTime? parseExpiresAt(Map<String, dynamic> request) {
  final raw = request['expires_at'];
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

/// Whether a sub-request is effectively expired (status or time-based).
///
/// A request is expired if:
///   - `status` is 'expired', 'accepted', or 'declined' (terminal states)
///   - OR `status` is 'pending' but `expires_at` is in the past
///
/// [now] can be injected for testing; defaults to `DateTime.now()`.
bool isRequestExpired(Map<String, dynamic> request, {DateTime? now}) {
  final status = request['status'] as String? ?? '';
  if (status == 'expired' || status == 'accepted' || status == 'declined') {
    return true;
  }
  if (status != 'pending') return false;

  final expiresAt = parseExpiresAt(request);
  if (expiresAt == null) return false; // no expiry → not expired

  final effectiveNow = now ?? DateTime.now();
  return expiresAt.isBefore(effectiveNow);
}

/// Whether a pending request can still be accepted/declined by the user.
///
/// Returns `true` only if status is 'pending' AND not timed out.
bool isRequestActionable(Map<String, dynamic> request, {DateTime? now}) {
  final status = request['status'] as String? ?? '';
  if (status != 'pending') return false;
  return !isRequestExpired(request, now: now);
}

/// Human-readable remaining time label for a pending request.
///
/// Returns:
///   - `"abgelaufen"` if expired
///   - `"läuft ab in X Min"` if > 1 minute remaining
///   - `"läuft gleich ab"` if < 1 minute remaining
///   - `null` if no expires_at data
String? expiresInLabel(Map<String, dynamic> request, {DateTime? now}) {
  final expiresAt = parseExpiresAt(request);
  if (expiresAt == null) return null;

  final effectiveNow = now ?? DateTime.now();
  final remaining = expiresAt.difference(effectiveNow);

  if (remaining.isNegative) return 'abgelaufen';
  if (remaining.inMinutes < 1) return 'läuft gleich ab';
  if (remaining.inMinutes == 1) return 'läuft ab in 1 Min';
  return 'läuft ab in ${remaining.inMinutes} Min';
}
