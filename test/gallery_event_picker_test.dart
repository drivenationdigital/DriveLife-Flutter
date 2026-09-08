import 'package:drivelife/screens/media/new_gallery_screen.dart';
import 'package:flutter_test/flutter_test.dart';

TaggedEvent event(String name, DateTime? date) =>
    TaggedEvent(id: '1', name: name, date: date);

DateTime daysOut(int days) => DateTime.now().add(Duration(days: days));

void main() {
  group('date parsing', () {
    // The time half is whatever the ACF picker stored, and a strict parse
    // against one pattern used to drop the whole date when it did not match.
    for (final raw in const [
      '05/24/2026 10:00',
      '05/24/2026 10:00:00',
      '05/24/2026 7:30 pm',
      '05/24/2026',
      '05/24/2026 ',
    ]) {
      test('reads the date out of "$raw"', () {
        final parsed = TaggedEvent.fromSearchResult({
          'id': '1',
          'name': 'Goodwood',
          'start_date': raw,
        });

        expect(parsed.date, isNotNull, reason: raw);
        expect(parsed.date!.year, 2026);
        expect(parsed.date!.month, 5);
        expect(parsed.date!.day, 24);
      });
    }

    test('an unreadable date is null rather than a wrong one', () {
      final parsed = TaggedEvent.fromSearchResult({
        'id': '1',
        'name': 'Goodwood',
        'start_date': 'sometime soon',
      });

      expect(parsed.date, isNull);
    });
  });

  group('searchSubtitle', () {
    test('leads with the date, and never repeats the type', () {
      final e = event('Goodwood', DateTime(2026, 5, 24));
      expect(e.searchSubtitle, '24 May 2026');
    });

    test('falls back to the type when there is nothing else to say', () {
      // An empty subtitle line would leave the row looking broken.
      expect(event('Goodwood', null).searchSubtitle, 'Event');
    });

    test('the chosen-entity card still says what kind of thing it is', () {
      final e = event('Goodwood', DateTime(2026, 5, 24));
      expect(e.subtitle, startsWith('Event'));
    });
  });

  group('orderForPicker', () {
    test('upcoming first soonest-first, then past most-recent-first', () {
      final ordered = TaggedEvent.orderForPicker([
        event('last month', daysOut(-30)),
        event('next year', daysOut(300)),
        event('yesterday', daysOut(-1)),
        event('next week', daysOut(7)),
      ]);

      expect(ordered.map((e) => e.name), [
        'next week',
        'next year',
        'yesterday',
        'last month',
      ]);
    });

    test('drops events past the six-month window', () {
      final ordered = TaggedEvent.orderForPicker([
        event('ancient', daysOut(-400)),
        event('recent', daysOut(-10)),
      ]);

      expect(ordered.map((e) => e.name), ['recent']);
    });

    test('today counts as upcoming, not past', () {
      // An event running today is the single most likely thing to tag, so it
      // must not fall to the bottom half of the list.
      final ordered = TaggedEvent.orderForPicker([
        event('yesterday', daysOut(-1)),
        event('today', DateTime.now()),
      ]);

      expect(ordered.first.name, 'today');
    });

    test('keeps undated events, last', () {
      // Missing can mean unreadable, and hiding a real event over a parsing
      // miss is worse than showing it without its date.
      final ordered = TaggedEvent.orderForPicker([
        event('no date', null),
        event('next week', daysOut(7)),
      ]);

      expect(ordered.map((e) => e.name), ['next week', 'no date']);
    });
  });
}
