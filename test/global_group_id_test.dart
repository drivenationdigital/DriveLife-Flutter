import 'package:drivelife/api/global_groups_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a group's id out of a payload that cannot agree with itself.
///
/// The detail endpoint and the garage suggestions send `ID`. The list
/// endpoints and the interest suggestions send `id`. One suggestions
/// response contains both, because its two halves are built by
/// different functions.
///
/// Reading one name only does not fail loudly — it returns 0, which is
/// a perfectly good id that every other group also has. That is how one
/// Join marked three rows joined.
void main() {
  GlobalGroup parse(Map<String, dynamic> json) => GlobalGroup.fromJson({
    'slug': 'mx5',
    'title': 'Mazda MX-5',
    ...json,
  });

  group('whichever name it arrived under', () {
    test('ID, as the detail endpoint and garage matches send it', () {
      expect(parse({'ID': 42}).id, 42);
    });

    test('id, as the lists and interest matches send it', () {
      expect(parse({'id': 42}).id, 42);
    });

    test('a string, because MySQL columns arrive as text', () {
      expect(parse({'id': '42'}).id, 42);
    });

    test('ID wins when both are there, since it came first', () {
      expect(parse({'ID': 7, 'id': 9}).id, 7);
    });
  });

  group('when there is none', () {
    test('no id at all is zero', () {
      expect(parse({}).id, 0);
    });

    test('rubbish is zero rather than a crash', () {
      expect(parse({'id': 'nonsense'}).id, 0);
      expect(parse({'ID': null, 'id': null}).id, 0);
    });

    test('two groups with no id are NOT distinguishable', () {
      // The thing that caused the bug, stated plainly: zero does not
      // identify anything, so screen state must never be keyed on it.
      // groups_screen keys its joined set on the slug for this reason.
      expect(parse({}).id, parse({'title': 'Something else'}).id);
    });
  });
}
