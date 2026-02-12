import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/models/dinner_rsvp.dart';

void main() {
  group('DinnerRsvp.fromMap', () {
    test('parses a valid map with all fields', () {
      final map = {
        'id': 'abc-123',
        'match_id': 'match-456',
        'user_id': 'user-789',
        'status': 'yes',
        'note': 'komme später',
        'updated_at': '2026-02-12T10:00:00Z',
        'created_at': '2026-02-12T09:00:00Z',
      };

      final rsvp = DinnerRsvp.fromMap(map);

      expect(rsvp.id, 'abc-123');
      expect(rsvp.matchId, 'match-456');
      expect(rsvp.userId, 'user-789');
      expect(rsvp.status, 'yes');
      expect(rsvp.note, 'komme später');
      expect(rsvp.updatedAt, DateTime.utc(2026, 2, 12, 10));
      expect(rsvp.createdAt, DateTime.utc(2026, 2, 12, 9));
    });

    test('parses a map without optional fields (note null, timestamps null)', () {
      final map = {
        'id': 'abc',
        'match_id': 'match',
        'user_id': 'user',
        'status': 'no',
      };

      final rsvp = DinnerRsvp.fromMap(map);

      expect(rsvp.id, 'abc');
      expect(rsvp.status, 'no');
      expect(rsvp.note, isNull);
      // timestamps fallback to DateTime.now() – just verify they're reasonable
      expect(rsvp.updatedAt.year, greaterThanOrEqualTo(2026));
      expect(rsvp.createdAt.year, greaterThanOrEqualTo(2026));
    });

    test('throws FormatException when id is missing', () {
      final map = {
        'match_id': 'match',
        'user_id': 'user',
        'status': 'yes',
      };

      expect(
        () => DinnerRsvp.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when user_id is missing', () {
      final map = {
        'id': 'abc',
        'match_id': 'match',
        'status': 'yes',
      };

      expect(
        () => DinnerRsvp.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when status is missing', () {
      final map = {
        'id': 'abc',
        'match_id': 'match',
        'user_id': 'user',
      };

      expect(
        () => DinnerRsvp.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException with multiple missing fields', () {
      final map = <String, dynamic>{};

      expect(
        () => DinnerRsvp.fromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('id'),
          ),
        ),
      );
    });

    test('statusEmoji returns correct emoji', () {
      DinnerRsvp make(String s) => DinnerRsvp.fromMap({
            'id': '1',
            'match_id': 'm',
            'user_id': 'u',
            'status': s,
          });

      expect(make('yes').statusEmoji, '✅');
      expect(make('no').statusEmoji, '❌');
      expect(make('maybe').statusEmoji, '❓');
      expect(make('unknown').statusEmoji, '–');
    });

    test('statusLabel returns correct German label', () {
      DinnerRsvp make(String s) => DinnerRsvp.fromMap({
            'id': '1',
            'match_id': 'm',
            'user_id': 'u',
            'status': s,
          });

      expect(make('yes').statusLabel, 'Ja');
      expect(make('no').statusLabel, 'Nein');
      expect(make('maybe').statusLabel, 'Vielleicht');
    });
  });
}
