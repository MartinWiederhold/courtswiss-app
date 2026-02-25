import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/services/support_service.dart';

void main() {
  group('SupportService validation', () {
    test('validates category correctly', () {
      expect(SupportService.isValidCategory('TECHNICAL'), isTrue);
      expect(SupportService.isValidCategory('GENERAL'), isTrue);
      expect(SupportService.isValidCategory('FEEDBACK'), isTrue);
      expect(SupportService.isValidCategory('OTHER'), isFalse);
      expect(SupportService.isValidCategory(null), isFalse);
    });

    test('validates message length boundaries', () {
      expect(SupportService.isValidMessage('short'), isFalse);
      expect(SupportService.isValidMessage('1234567890'), isTrue);
      expect(
        SupportService.isValidMessage('x' * 4000),
        isTrue,
      );
      expect(
        SupportService.isValidMessage('x' * 4001),
        isFalse,
      );
    });

    test('validates optional email format', () {
      expect(SupportService.isValidEmail(null), isTrue);
      expect(SupportService.isValidEmail(''), isTrue);
      expect(SupportService.isValidEmail('max@example.com'), isTrue);
      expect(SupportService.isValidEmail('max.example.com'), isFalse);
    });
  });
}
