/// Pure helper for equal expense splitting (no I/O, no Supabase).
///
/// Distributes [amountCents] equally across [memberCount] participants.
/// Remainder cents are distributed 1 each to the first N members
/// (so that sum of all shares == amountCents exactly).
///
/// Returns a list of share amounts in cents (length == memberCount).
///
/// Throws [ArgumentError] if [amountCents] <= 0 or [memberCount] <= 0.
List<int> calculateEqualSplit({
  required int amountCents,
  required int memberCount,
}) {
  if (amountCents <= 0) {
    throw ArgumentError.value(amountCents, 'amountCents', 'must be > 0');
  }
  if (memberCount <= 0) {
    throw ArgumentError.value(memberCount, 'memberCount', 'must be > 0');
  }

  final baseShare = amountCents ~/ memberCount;
  final remainder = amountCents - (baseShare * memberCount);

  return List<int>.generate(memberCount, (i) {
    return i < remainder ? baseShare + 1 : baseShare;
  });
}
