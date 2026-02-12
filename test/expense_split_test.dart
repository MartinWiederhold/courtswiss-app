import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/models/expense.dart';
import 'package:swisscourt/utils/expense_split.dart';

void main() {
  group('ExpenseShare.fromMap paid fields', () {
    test('defaults isPaid=false when fields missing', () {
      final share = ExpenseShare.fromMap({
        'id': 'abc',
        'expense_id': 'exp1',
        'user_id': 'u1',
        'share_cents': 500,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(share.isPaid, false);
      expect(share.paidAt, isNull);
    });

    test('parses isPaid=true and paidAt', () {
      final share = ExpenseShare.fromMap({
        'id': 'abc',
        'expense_id': 'exp1',
        'user_id': 'u1',
        'share_cents': 500,
        'is_paid': true,
        'paid_at': '2026-02-10T14:30:00Z',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(share.isPaid, true);
      expect(share.paidAt, isNotNull);
      expect(share.paidAt!.year, 2026);
    });

    test('isPaid=false when is_paid is false', () {
      final share = ExpenseShare.fromMap({
        'id': 'abc',
        'expense_id': 'exp1',
        'user_id': 'u1',
        'share_cents': 300,
        'is_paid': false,
        'paid_at': null,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(share.isPaid, false);
      expect(share.paidAt, isNull);
    });
  });

  group('Expense helpers: paidCount / openCount / paidCents / openCents', () {
    test('calculates correctly with mixed paid states', () {
      final expense = Expense(
        id: 'e1',
        matchId: 'm1',
        teamId: 't1',
        title: 'Pizza',
        amountCents: 3000,
        paidByUserId: 'u1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        shares: [
          ExpenseShare(
            id: 's1',
            expenseId: 'e1',
            userId: 'u1',
            shareCents: 1000,
            isPaid: true,
            paidAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
          ExpenseShare(
            id: 's2',
            expenseId: 'e1',
            userId: 'u2',
            shareCents: 1000,
            isPaid: false,
            createdAt: DateTime.now(),
          ),
          ExpenseShare(
            id: 's3',
            expenseId: 'e1',
            userId: 'u3',
            shareCents: 1000,
            isPaid: true,
            paidAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        ],
      );
      expect(expense.paidCount, 2);
      expect(expense.openCount, 1);
      expect(expense.paidCents, 2000);
      expect(expense.openCents, 1000);
    });

    test('payer auto-paid: only payer share marked, rest open', () {
      // Simulates the DB behaviour after cs_create_expense_equal_split
      // where the payer's share is auto-marked as paid.
      final payerUid = 'payer1';
      final expense = Expense(
        id: 'e2',
        matchId: 'm1',
        teamId: 't1',
        title: 'Getränke',
        amountCents: 4500,
        paidByUserId: payerUid,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        shares: [
          ExpenseShare(
            id: 's1',
            expenseId: 'e2',
            userId: payerUid,
            shareCents: 1500,
            isPaid: true,
            paidAt: DateTime(2026, 2, 12),
            createdAt: DateTime.now(),
          ),
          ExpenseShare(
            id: 's2',
            expenseId: 'e2',
            userId: 'u2',
            shareCents: 1500,
            isPaid: false,
            createdAt: DateTime.now(),
          ),
          ExpenseShare(
            id: 's3',
            expenseId: 'e2',
            userId: 'u3',
            shareCents: 1500,
            isPaid: false,
            createdAt: DateTime.now(),
          ),
        ],
      );

      expect(expense.paidCount, 1);
      expect(expense.openCount, 2);
      expect(expense.paidCents, 1500);
      expect(expense.openCents, 3000);
      expect(expense.shareCount, 3);
      expect(expense.perPersonDouble, closeTo(15.0, 0.01));

      // Verify the payer's share is marked paid
      final payerShare =
          expense.shares.firstWhere((s) => s.userId == payerUid);
      expect(payerShare.isPaid, true);
      expect(payerShare.paidAt, isNotNull);
    });
  });

  group('calculateEqualSplit', () {
    test('8000 cents / 3 members → 2667, 2667, 2666', () {
      final shares = calculateEqualSplit(amountCents: 8000, memberCount: 3);
      expect(shares, [2667, 2667, 2666]);
      expect(shares.reduce((a, b) => a + b), 8000);
    });

    test('100 cents / 6 members → sum equals 100', () {
      final shares = calculateEqualSplit(amountCents: 100, memberCount: 6);
      expect(shares.length, 6);
      expect(shares.reduce((a, b) => a + b), 100);
      // 100 / 6 = 16 remainder 4 → first 4 get 17, last 2 get 16
      expect(shares, [17, 17, 17, 17, 16, 16]);
    });

    test('even split: 900 / 3 → [300, 300, 300]', () {
      final shares = calculateEqualSplit(amountCents: 900, memberCount: 3);
      expect(shares, [300, 300, 300]);
      expect(shares.reduce((a, b) => a + b), 900);
    });

    test('single member gets all', () {
      final shares = calculateEqualSplit(amountCents: 4550, memberCount: 1);
      expect(shares, [4550]);
    });

    test('1 cent / 3 members → [1, 0, 0]', () {
      final shares = calculateEqualSplit(amountCents: 1, memberCount: 3);
      expect(shares, [1, 0, 0]);
      expect(shares.reduce((a, b) => a + b), 1);
    });

    test('throws on zero amount', () {
      expect(
        () => calculateEqualSplit(amountCents: 0, memberCount: 3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on negative amount', () {
      expect(
        () => calculateEqualSplit(amountCents: -100, memberCount: 3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on zero members', () {
      expect(
        () => calculateEqualSplit(amountCents: 100, memberCount: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
