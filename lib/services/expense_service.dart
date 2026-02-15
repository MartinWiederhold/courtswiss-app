import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense.dart';

/// Service for match expenses (cs_expenses + cs_expense_shares).
///
/// MVP: equal-split only, via the RPC `cs_create_expense_equal_split`.
class ExpenseService {
  static final _supabase = Supabase.instance.client;

  // ── Queries ─────────────────────────────────────────────────

  /// Fetch all expenses for a match, including embedded shares.
  static Future<List<Expense>> listExpenses(String matchId) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('EXPENSE_LOAD: matchId=$matchId uid=$uid');

    final rows = await _supabase
        .from('cs_expenses')
        .select('*, cs_expense_shares(*)')
        .eq('match_id', matchId)
        .order('created_at', ascending: true);

    final result = <Expense>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      try {
        result.add(Expense.fromMap(row));
      } catch (e) {
        debugPrint('EXPENSE_PARSE ERROR: $e — row keys: ${row.keys.toList()}');
      }
    }

    debugPrint('EXPENSE_LOAD: ${result.length} expenses returned');
    return result;
  }

  // ── Mutations ───────────────────────────────────────────────

  /// Create an expense with equal split among all team members.
  ///
  /// [amountCHF] is the total in CHF (e.g. 45.50).
  /// Returns the new expense id.
  static Future<String> createExpenseEqualSplit({
    required String matchId,
    required String title,
    required double amountCHF,
    String? note,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    final amountCents = (amountCHF * 100).round();
    debugPrint(
      'EXPENSE_CREATE: uid=$uid matchId=$matchId title=$title '
      'amountCents=$amountCents',
    );

    if (uid == null) {
      throw Exception('Nicht eingeloggt – bitte App neu starten.');
    }

    if (amountCents <= 0) {
      throw ArgumentError('Betrag muss grösser als 0 sein.');
    }

    final result = await _supabase.rpc(
      'cs_create_expense_equal_split',
      params: {
        'p_match_id': matchId,
        'p_title': title,
        'p_amount_cents': amountCents,
        'p_note': note,
      },
    );

    final expenseId = result?.toString();
    if (expenseId == null || expenseId.isEmpty) {
      debugPrint('EXPENSE_CREATE ERROR: RPC returned null/empty: $result');
      throw Exception(
        'Spese konnte nicht erstellt werden – '
        'Server hat keine ID zurückgegeben.',
      );
    }

    debugPrint('EXPENSE_CREATE: success, expenseId=$expenseId');
    return expenseId;
  }

  /// Mark a share as paid or unpaid.
  static Future<void> markSharePaid({
    required String shareId,
    required bool paid,
  }) async {
    debugPrint(
      'EXPENSE_MARK_PAID: shareId=$shareId paid=$paid '
      'uid=${_supabase.auth.currentUser?.id}',
    );

    await _supabase.rpc(
      'cs_mark_expense_share_paid',
      params: {'p_share_id': shareId, 'p_paid': paid},
    );

    debugPrint('EXPENSE_MARK_PAID: success');
  }

  /// Delete an expense (only allowed for the person who paid, or captain).
  static Future<void> deleteExpense(String expenseId) async {
    debugPrint(
      'EXPENSE_DELETE: expenseId=$expenseId '
      'uid=${_supabase.auth.currentUser?.id}',
    );
    await _supabase.from('cs_expenses').delete().eq('id', expenseId);
    debugPrint('EXPENSE_DELETE: success');
  }
}
