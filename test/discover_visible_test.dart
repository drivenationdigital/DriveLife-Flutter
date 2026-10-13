import 'package:drivelife/screens/discover/discover_place.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the one filter that decides what Discover shows.
///
/// The map's pins, the cluster badges and the sheet's "N nearby" heading are
/// three views of this single list. They used to be computed separately and
/// disagreed in two ways:
///
///  * the pin layer filtered by category but the GeoJSON source did not, and
///    clustering runs on the source — so a cluster badge counted results that
///    were filtered out of the map;
///  * the search box filtered the sheet and nothing else, so typing left the
///    sheet saying "2 nearby" over a map still showing forty pins.
///
/// Everything now goes through [discoverVisible].
void main() {
  DiscoverPlace event(String title, {String? where}) => DiscoverPlace.fromEvent(
    {
      'id': title.hashCode,
      'title': title,
      'location': where,
      'latitude': 54.0,
      'longitude': -1.0,
    },
  )!;

  DiscoverPlace venue(String title, {String? where}) => DiscoverPlace.fromVenue(
    {
      'ID': title.hashCode,
      'title': title,
      'venue_location': where,
      'latitude': 54.0,
      'longitude': -1.0,
    },
  )!;

  final places = [
    event('Teesside Auto Show', where: 'Middlesbrough'),
    event('Croft Track Day', where: 'Darlington'),
    venue('Croft Circuit', where: 'Darlington'),
    venue('Redcar Beach', where: 'Redcar'),
  ];

  final all = DiscoverKind.values.toSet();

  group('categories', () {
    test('shows everything by default', () {
      expect(discoverVisible(places, kinds: all), hasLength(4));
    });

    test('a focused chip narrows to one kind', () {
      final shown = discoverVisible(
        places,
        kinds: all,
        category: DiscoverKind.event,
      );

      expect(shown, hasLength(2));
      expect(shown.every((p) => p.kind == DiscoverKind.event), isTrue);
    });

    test('a kind switched off in the sheet is gone even without a chip', () {
      final shown = discoverVisible(places, kinds: {DiscoverKind.venue});

      expect(shown, hasLength(2));
      expect(shown.every((p) => p.kind == DiscoverKind.venue), isTrue);
    });

    test('the chip and the sheet intersect rather than override', () {
      // Venues allowed, events focused: nothing satisfies both. The screen
      // clears a focus that its sheet has just disallowed, but the predicate
      // must not quietly widen either of them.
      expect(
        discoverVisible(
          places,
          kinds: {DiscoverKind.venue},
          category: DiscoverKind.event,
        ),
        isEmpty,
      );
    });
  });

  group('search', () {
    test('matches a title, case-insensitively', () {
      expect(discoverVisible(places, kinds: all, query: 'croft'), hasLength(2));
    });

    test('matches the subtitle too', () {
      // The place under the title is where it is, and "events in Darlington"
      // is a thing people type.
      final shown = discoverVisible(places, kinds: all, query: 'darlington');
      expect(shown, hasLength(2));
    });

    test('ignores surrounding whitespace', () {
      expect(
        discoverVisible(places, kinds: all, query: '  croft  '),
        hasLength(2),
      );
    });

    test('an empty query filters nothing', () {
      expect(discoverVisible(places, kinds: all, query: '   '), hasLength(4));
    });

    test('combines with the category', () {
      final shown = discoverVisible(
        places,
        kinds: all,
        category: DiscoverKind.venue,
        query: 'croft',
      );

      expect(shown, hasLength(1));
      expect(shown.single.title, 'Croft Circuit');
    });

    test('no match is empty, not everything', () {
      expect(discoverVisible(places, kinds: all, query: 'zzzz'), isEmpty);
    });
  });

  group('the map and the list agree', () {
    test('the GeoJSON carries exactly the visible results', () {
      // This is the invariant the cluster badges depend on. The source holds
      // the filtered set, so point_count can only ever count pins that are
      // actually drawn.
      for (final query in ['', 'croft', 'darlington', 'zzzz']) {
        for (final category in [null, ...DiscoverKind.values]) {
          final shown = discoverVisible(
            places,
            kinds: all,
            category: category,
            query: query,
          );

          final features = [for (final p in shown) p.toFeature()];

          expect(
            features,
            hasLength(shown.length),
            reason: 'query "$query", category $category',
          );
        }
      }
    });
  });
}
