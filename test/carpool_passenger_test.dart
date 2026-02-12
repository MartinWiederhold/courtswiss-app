import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/models/carpool_offer.dart';

void main() {
  group('CarpoolPassenger.fromMap', () {
    test('parses row with passenger_user_id (DB column name)', () {
      final map = {
        'offer_id': 'offer-aaa',
        'passenger_user_id': 'user-bbb',
        'created_at': '2026-02-12T15:30:00Z',
      };

      final p = CarpoolPassenger.fromMap(map);

      expect(p.offerId, 'offer-aaa');
      expect(p.userId, 'user-bbb');
      expect(p.createdAt, DateTime.utc(2026, 2, 12, 15, 30));
      // synthetic id because no 'id' column
      expect(p.id, 'offer-aaa_user-bbb');
    });

    test('parses row with user_id (legacy/alias)', () {
      final map = {
        'offer_id': 'offer-aaa',
        'user_id': 'user-ccc',
      };

      final p = CarpoolPassenger.fromMap(map);

      expect(p.userId, 'user-ccc');
      expect(p.id, 'offer-aaa_user-ccc');
    });

    test('prefers passenger_user_id over user_id when both present', () {
      final map = {
        'offer_id': 'offer-x',
        'passenger_user_id': 'puid',
        'user_id': 'uid-legacy',
      };

      final p = CarpoolPassenger.fromMap(map);

      expect(p.userId, 'puid');
    });

    test('uses explicit id when present', () {
      final map = {
        'id': 'explicit-id',
        'offer_id': 'offer-y',
        'passenger_user_id': 'user-z',
      };

      final p = CarpoolPassenger.fromMap(map);

      expect(p.id, 'explicit-id');
    });

    test('throws FormatException when offer_id is missing', () {
      final map = {
        'passenger_user_id': 'user-bbb',
      };

      expect(
        () => CarpoolPassenger.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when both user id fields are missing', () {
      final map = {
        'offer_id': 'offer-aaa',
      };

      expect(
        () => CarpoolPassenger.fromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('passenger_user_id'),
          ),
        ),
      );
    });

    test('throws FormatException when map is empty', () {
      expect(
        () => CarpoolPassenger.fromMap({}),
        throwsA(isA<FormatException>()),
      );
    });

    test('handles null created_at gracefully', () {
      final map = {
        'offer_id': 'offer-1',
        'passenger_user_id': 'user-1',
        'created_at': null,
      };

      final p = CarpoolPassenger.fromMap(map);

      // Falls back to DateTime.now()
      expect(p.createdAt.year, greaterThanOrEqualTo(2026));
    });
  });
}
