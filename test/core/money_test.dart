import 'package:budget_app/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCents', () {
    test('formats whole and fractional dollars', () {
      expect(formatCents(1234), '\$12.34');
      expect(formatCents(100), '\$1.00');
    });

    test('formats small values with leading zero dollars', () {
      expect(formatCents(0), '\$0.00');
      expect(formatCents(5), '\$0.05');
    });

    test('formats negatives with the sign before the dollar sign', () {
      expect(formatCents(-550), '-\$5.50');
    });

    test('adds thousands separators', () {
      expect(formatCents(240000), '\$2,400.00');
      expect(formatCents(123456789), '\$1,234,567.89');
    });
  });
}
