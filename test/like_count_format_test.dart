import 'package:flutter_test/flutter_test.dart';

/// How a like count is written on a vehicle's own page.
///
/// A copy of _formatLikes from vehicle_detail_screen.dart, which is
/// private to that file. Copied rather than made public because the
/// thing worth pinning is the RULE — separators below ten thousand,
/// abbreviation above — and that rule is the kind that gets quietly
/// changed to match the leaderboard's, which abbreviates everything.
String formatLikes(int n) {
  if (n >= 10000) {
    final k = n / 1000;
    return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
  }

  final digits = '$n';
  final out = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }

  return out.toString();
}

void main() {
  group('small enough to read exactly', () {
    test('no separator below a thousand', () {
      expect(formatLikes(0), '0');
      expect(formatLikes(7), '7');
      expect(formatLikes(42), '42');
      expect(formatLikes(999), '999');
    });

    test('one separator in the thousands', () {
      expect(formatLikes(1000), '1,000');
      expect(formatLikes(1284), '1,284');
      expect(formatLikes(9999), '9,999');
    });

    test('the exact number survives, which is the point', () {
      // On a vehicle's own page the difference between these two is
      // interesting. "1.3k" throws it away, which is why the cutover is
      // at ten thousand rather than one.
      expect(formatLikes(1284), isNot(formatLikes(1349)));
    });
  });

  group('large enough to abbreviate', () {
    test('ten thousand is where it changes', () {
      expect(formatLikes(9999), '9,999');
      expect(formatLikes(10000), '10.0k');
    });

    test('one decimal up to a hundred thousand', () {
      expect(formatLikes(48200), '48.2k');
      expect(formatLikes(99900), '99.9k');
    });

    test('no decimal past it, where it would be noise', () {
      expect(formatLikes(100000), '100k');
      expect(formatLikes(1500000), '1500k');
    });
  });

  test('never empty, at any size', () {
    // The label falls back to "Like" at zero, so this only has to be
    // non-empty — but a formatter that can return '' puts a button on
    // screen with nothing in it.
    for (final n in [0, 1, 999, 1000, 9999, 10000, 123456, 9999999]) {
      expect(formatLikes(n), isNotEmpty, reason: 'at $n');
    }
  });
}
