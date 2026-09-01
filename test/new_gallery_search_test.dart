import 'package:drivelife/screens/media/new_gallery_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real row from `app/v1/discover-search`, captured against the live
/// endpoint — including the US-ordered date that ISO parsing silently dropped.
const _liveEvent = {
  'id': 26218,
  'name': 'Goodwood Revival',
  'thumbnail': 'https://example.com/goodwoodrevival26-600x365.png',
  'type': 'events',
  'start_date': '09/18/2026 09:00',
  'end_date': '09/20/2026 17:00',
  'location': 'Goodwood Motor Circuit, Chichester, UK',
  'is_liked': false,
};

void main() {
  group('TaggedEvent.fromSearchResult', () {
    test('reads a live discover-search row', () {
      final event = TaggedEvent.fromSearchResult(
        Map<String, dynamic>.from(_liveEvent),
      );

      expect(event.id, '26218');
      expect(event.name, 'Goodwood Revival');
      expect(event.location, 'Goodwood Motor Circuit, Chichester, UK');
    });

    test('parses the MM/dd/yyyy date the API actually sends', () {
      final event = TaggedEvent.fromSearchResult(
        Map<String, dynamic>.from(_liveEvent),
      );

      // 09/18/2026 is 18 September — month first, which is why
      // DateTime.tryParse returned null and the date vanished from the card.
      expect(event.date, isNotNull);
      expect(event.date!.year, 2026);
      expect(event.date!.month, 9);
      expect(event.date!.day, 18);
    });

    test('builds the subtitle shown on the tag card', () {
      final event = TaggedEvent.fromSearchResult(
        Map<String, dynamic>.from(_liveEvent),
      );

      expect(event.subtitle, contains('Event'));
      expect(event.subtitle, contains('18/09/2026'));
    });

    test('omits missing parts rather than leaving dangling separators', () {
      final event = TaggedEvent.fromSearchResult({
        'id': 1,
        'name': 'Unplaced meet',
      });

      expect(event.subtitle, 'Event');
    });

    test('decodes entities in the name', () {
      final event = TaggedEvent.fromSearchResult({
        'id': 2,
        'name': 'Cars &amp; Coffee',
      });

      expect(event.name, 'Cars & Coffee');
    });
  });
}
