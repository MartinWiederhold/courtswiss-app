import 'package:flutter/foundation.dart';

/// Model for an expense (cs_expenses) with embedded shares.
class Expense {
  final String id;
  final String matchId;
  final String teamId;
  final String title;
  final int amountCents;
  final String currency;
  final String paidByUserId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ExpenseShare> shares;

  Expense({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.title,
    required this.amountCents,
    this.currency = 'CHF',
    required this.paidByUserId,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.shares = const [],
  });

  /// Amount in CHF (or whatever currency) as double.
  double get amountDouble => amountCents / 100.0;

  /// Formatted amount string (e.g. "CHF 45.50").
  String get amountFormatted =>
      '$currency ${amountDouble.toStringAsFixed(2)}';

  /// Per-person share (based on shares list).
  double get perPersonDouble =>
      shares.isEmpty ? amountDouble : amountDouble / shares.length;

  /// Formatted per-person string.
  String get perPersonFormatted =>
      '$currency ${perPersonDouble.toStringAsFixed(2)}';

  /// Number of people sharing.
  int get shareCount => shares.length;

  /// Number of shares marked as paid.
  int get paidCount => shares.where((s) => s.isPaid).length;

  /// Number of open (unpaid) shares.
  int get openCount => shares.where((s) => !s.isPaid).length;

  /// Total cents already paid.
  int get paidCents =>
      shares.where((s) => s.isPaid).fold<int>(0, (sum, s) => sum + s.shareCents);

  /// Total cents still open.
  int get openCents => amountCents - paidCents;

  /// Parse a Supabase row into an [Expense].
  factory Expense.fromMap(Map<String, dynamic> map,
      {String paidByName = '?'}) {
    final id = map['id'];
    final matchId = map['match_id'];
    final teamId = map['team_id'];
    final title = map['title'];
    final amountCents = map['amount_cents'];
    final paidByUserId = map['paid_by_user_id'];

    final missing = <String>[];
    if (id == null) missing.add('id');
    if (matchId == null) missing.add('match_id');
    if (teamId == null) missing.add('team_id');
    if (title == null) missing.add('title');
    if (amountCents == null) missing.add('amount_cents');
    if (paidByUserId == null) missing.add('paid_by_user_id');

    if (missing.isNotEmpty) {
      debugPrint(
        'Expense.fromMap: NULL in required fields $missing. '
        'Row keys: ${map.keys.toList()}',
      );
      throw FormatException('Expense: Pflichtfelder fehlen: $missing');
    }

    // Parse shares
    final shareList = <ExpenseShare>[];
    final rawShares = map['cs_expense_shares'];
    if (rawShares is List) {
      for (final s in rawShares) {
        if (s is Map<String, dynamic>) {
          try {
            shareList.add(ExpenseShare.fromMap(s));
          } catch (e) {
            debugPrint('ExpenseShare.fromMap skipped: $e');
          }
        }
      }
    }

    final createdAtRaw = map['created_at'];
    DateTime createdAt;
    if (createdAtRaw is String && createdAtRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    final updatedAtRaw = map['updated_at'];
    DateTime updatedAt;
    if (updatedAtRaw is String && updatedAtRaw.isNotEmpty) {
      updatedAt = DateTime.tryParse(updatedAtRaw) ?? DateTime.now();
    } else {
      updatedAt = DateTime.now();
    }

    return Expense(
      id: id.toString(),
      matchId: matchId.toString(),
      teamId: teamId.toString(),
      title: title.toString(),
      amountCents: (amountCents as num).toInt(),
      currency: (map['currency'] as String?) ?? 'CHF',
      paidByUserId: paidByUserId.toString(),
      note: map['note'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      shares: shareList,
    );
  }
}

/// Model for a single expense share (cs_expense_shares).
class ExpenseShare {
  final String id;
  final String expenseId;
  final String userId;
  final int shareCents;
  final bool isPaid;
  final DateTime? paidAt;
  final DateTime createdAt;

  ExpenseShare({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.shareCents,
    this.isPaid = false,
    this.paidAt,
    required this.createdAt,
  });

  double get shareDouble => shareCents / 100.0;

  factory ExpenseShare.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final expenseId = map['expense_id'];
    final userId = map['user_id'];
    final shareCents = map['share_cents'];

    final missing = <String>[];
    if (id == null) missing.add('id');
    if (expenseId == null) missing.add('expense_id');
    if (userId == null) missing.add('user_id');
    if (shareCents == null) missing.add('share_cents');

    if (missing.isNotEmpty) {
      debugPrint(
        'ExpenseShare.fromMap: NULL in required fields $missing. '
        'Row keys: ${map.keys.toList()}',
      );
      throw FormatException(
        'ExpenseShare: Pflichtfelder fehlen: $missing',
      );
    }

    final createdAtRaw = map['created_at'];
    DateTime createdAt;
    if (createdAtRaw is String && createdAtRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    final paidAtRaw = map['paid_at'];
    DateTime? paidAt;
    if (paidAtRaw is String && paidAtRaw.isNotEmpty) {
      paidAt = DateTime.tryParse(paidAtRaw);
    }

    return ExpenseShare(
      id: id.toString(),
      expenseId: expenseId.toString(),
      userId: userId.toString(),
      shareCents: (shareCents as num).toInt(),
      isPaid: map['is_paid'] == true,
      paidAt: paidAt,
      createdAt: createdAt,
    );
  }
}
