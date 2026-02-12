import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/utils/sub_request_timeout.dart';

// ─── Helpers ─────────────────────────────────────────────────

Map<String, dynamic> _req({
  String status = 'pending',
  String? expiresAt,
}) =>
    {
      'id': 'req-1',
      'status': status,
      if (expiresAt != null) 'expires_at': expiresAt,
    };

void main() {
  // ═════════════════════════════════════════════════════════════
  //  parseExpiresAt
  // ═════════════════════════════════════════════════════════════

  group('parseExpiresAt', () {
    test('parses ISO 8601 string', () {
      final req = _req(expiresAt: '2026-02-12T15:30:00Z');
      final dt = parseExpiresAt(req);
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 2);
      expect(dt.day, 12);
    });

    test('returns null when field missing', () {
      final req = _req();
      expect(parseExpiresAt(req), isNull);
    });

    test('returns null when field is null', () {
      final req = {'status': 'pending', 'expires_at': null};
      expect(parseExpiresAt(req), isNull);
    });

    test('returns null for invalid string', () {
      final req = {'status': 'pending', 'expires_at': 'not-a-date'};
      expect(parseExpiresAt(req), isNull);
    });

    test('handles DateTime object directly', () {
      final dt = DateTime(2026, 3, 1, 12, 0);
      final req = {'status': 'pending', 'expires_at': dt};
      expect(parseExpiresAt(req), dt);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  isRequestExpired
  // ═════════════════════════════════════════════════════════════

  group('isRequestExpired', () {
    test('pending + expires_at in the past → expired', () {
      final req = _req(
        status: 'pending',
        expiresAt: '2026-01-01T00:00:00Z',
      );
      expect(
        isRequestExpired(req, now: DateTime.utc(2026, 2, 1)),
        isTrue,
      );
    });

    test('pending + expires_at in the future → not expired', () {
      final req = _req(
        status: 'pending',
        expiresAt: '2026-03-01T00:00:00Z',
      );
      expect(
        isRequestExpired(req, now: DateTime.utc(2026, 2, 1)),
        isFalse,
      );
    });

    test('pending + no expires_at → not expired', () {
      final req = _req(status: 'pending');
      expect(isRequestExpired(req), isFalse);
    });

    test('status=expired → expired regardless of time', () {
      final req = _req(
        status: 'expired',
        expiresAt: '2099-12-31T23:59:59Z',
      );
      expect(isRequestExpired(req), isTrue);
    });

    test('status=accepted → expired (terminal)', () {
      expect(isRequestExpired(_req(status: 'accepted')), isTrue);
    });

    test('status=declined → expired (terminal)', () {
      expect(isRequestExpired(_req(status: 'declined')), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  isRequestActionable
  // ═════════════════════════════════════════════════════════════

  group('isRequestActionable', () {
    test('pending + future expiry → actionable', () {
      final req = _req(
        status: 'pending',
        expiresAt: '2026-03-01T00:00:00Z',
      );
      expect(
        isRequestActionable(req, now: DateTime.utc(2026, 2, 1)),
        isTrue,
      );
    });

    test('pending + past expiry → not actionable', () {
      final req = _req(
        status: 'pending',
        expiresAt: '2026-01-01T00:00:00Z',
      );
      expect(
        isRequestActionable(req, now: DateTime.utc(2026, 2, 1)),
        isFalse,
      );
    });

    test('accepted → not actionable', () {
      expect(isRequestActionable(_req(status: 'accepted')), isFalse);
    });

    test('declined → not actionable', () {
      expect(isRequestActionable(_req(status: 'declined')), isFalse);
    });

    test('expired status → not actionable', () {
      expect(isRequestActionable(_req(status: 'expired')), isFalse);
    });

    test('pending + no expires_at → actionable (no timeout)', () {
      expect(isRequestActionable(_req(status: 'pending')), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  expiresInLabel
  // ═════════════════════════════════════════════════════════════

  group('expiresInLabel', () {
    test('no expires_at → null', () {
      expect(expiresInLabel(_req()), isNull);
    });

    test('past expiry → "abgelaufen"', () {
      final req = _req(expiresAt: '2026-01-01T00:00:00Z');
      expect(
        expiresInLabel(req, now: DateTime.utc(2026, 2, 1)),
        'abgelaufen',
      );
    });

    test('< 1 minute remaining → "läuft gleich ab"', () {
      final req = _req(expiresAt: '2026-02-01T12:00:30Z');
      expect(
        expiresInLabel(req, now: DateTime.utc(2026, 2, 1, 12, 0, 0)),
        'läuft gleich ab',
      );
    });

    test('exactly 1 minute remaining → "läuft ab in 1 Min"', () {
      final req = _req(expiresAt: '2026-02-01T12:01:00Z');
      expect(
        expiresInLabel(req, now: DateTime.utc(2026, 2, 1, 12, 0, 0)),
        'läuft ab in 1 Min',
      );
    });

    test('15 minutes remaining → "läuft ab in 15 Min"', () {
      final req = _req(expiresAt: '2026-02-01T12:15:00Z');
      expect(
        expiresInLabel(req, now: DateTime.utc(2026, 2, 1, 12, 0, 0)),
        'läuft ab in 15 Min',
      );
    });

    test('29 minutes remaining → "läuft ab in 29 Min"', () {
      final req = _req(expiresAt: '2026-02-01T12:30:00Z');
      expect(
        expiresInLabel(req, now: DateTime.utc(2026, 2, 1, 12, 1, 0)),
        'läuft ab in 29 Min',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  kSubRequestTimeout constant
  // ═════════════════════════════════════════════════════════════

  group('constants', () {
    test('default timeout is 30 minutes', () {
      expect(kSubRequestTimeout, const Duration(minutes: 30));
    });
  });
}
