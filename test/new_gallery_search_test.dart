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

/// A real venue row from the same endpoint. Note the address arrives as
/// `venue_location`, not `location` — reading only `location` left the
/// subtitle blank for every venue.
const _liveVenue = {
  'id': '12246',
  'name': 'The Motorist',
  'title': 'The Motorist',
  'thumbnail': 'https://example.com/DSC_1190-1-1024x683.jpg',
  'cover_image': 'https://example.com/DSC_1190-1-1024x683.jpg',
  'venue_location': 'Newcastle upon Tyne',
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

  group('TaggedEvent for venues', () {
    test('reads a live venue row, including venue_location', () {
      final venue = TaggedEvent.fromSearchResult(
        Map<String, dynamic>.from(_liveVenue),
        type: TaggedEntityType.venue,
      );

      expect(venue.id, '12246');
      expect(venue.name, 'The Motorist');
      expect(venue.location, 'Newcastle upon Tyne');
      expect(venue.type, TaggedEntityType.venue);
    });

    test('labels itself a venue and carries no date', () {
      final venue = TaggedEvent.fromSearchResult(
        Map<String, dynamic>.from(_liveVenue),
        type: TaggedEntityType.venue,
      );

      expect(venue.subtitle, startsWith('Venue'));
      expect(venue.subtitle, contains('Newcastle upon Tyne'));
      expect(venue.date, isNull);
      expect(venue.entityType, 'venue');
    });

    test('events still report themselves as events', () {
      final event = TaggedEvent.fromSearchResult(
        Map<String, dynamic>.from(_liveEvent),
      );

      expect(event.entityType, 'event');
      expect(event.subtitle, startsWith('Event'));
    });
  });
}
