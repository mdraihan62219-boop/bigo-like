import 'package:flutter_test/flutter_test.dart';
import 'package:rayzi_app/core/utils/formatters.dart';

void main() {
  group('formatNumber (production)', () {
    test('formats thousands correctly', () {
      expect(formatNumber(1500), '1.5K');
      expect(formatNumber(999), '999');
    });

    test('formats round values without decimals', () {
      expect(formatNumber(1000000), '1M');
      expect(formatNumber(1000), '1K');
    });

    test('formats millions and billions', () {
      expect(formatNumber(2500000), '2.5M');
      expect(formatNumber(1000000000), '1B');
    });

    test('passes through small numbers', () {
      expect(formatNumber(500), '500');
      expect(formatNumber(0), '0');
    });
  });

  group('validateEmail (production)', () {
    test('accepts valid addresses', () {
      expect(validateEmail('test@example.com'), true);
      expect(validateEmail('user.name+tag@sub.domain.org'), true);
    });

    test('rejects invalid input', () {
      expect(validateEmail('invalid'), false);
      expect(validateEmail('missing@tld'), false);
      expect(validateEmail('@example.com'), false);
      expect(validateEmail('a b@example.com'), false);
    });
  });
}
