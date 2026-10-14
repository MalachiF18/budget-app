/// Formats whole cents as dollars, e.g. 1234 -> $12.34, -550 -> -$5.50.
///
/// Money is stored as int cents everywhere (see README); this is the only
/// place cents become a display string. Pure integer math, so no rounding
/// surprises from double.
String formatCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final dollars = abs ~/ 100;
  final remainder = abs % 100;

  // Insert a comma before every group of three digits, counted from the right.
  final digits = dollars.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }

  final sign = negative ? '-' : '';
  return '$sign\$$grouped.${remainder.toString().padLeft(2, '0')}';
}
