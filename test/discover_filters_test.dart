import 'package:drivelife/screens/discover/discover_filters.dart';
import 'package:drivelife/screens/discover/discover_place.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the Discover filters.
///
/// The one that matters is [DiscoverFilters.needsRefetch]. Categories are
/// applied on the client and distance/date are query parameters, so getting
/// this wrong either makes ticking a checkbox cost a network round trip, or —
/// worse — leaves a radius change showing the old radius's results.
void main() {
  group('needsRefetch', () {
    final base = DiscoverFilters.initial;

    test('a category change does not', () {
      // Everything is fetched once and hidden or shown locally. A round trip
      // here would make the checkboxes feel broken.
      final next = base.copyWith(kinds: {DiscoverKind.event});
      expect(next.needsRefetch(base), isFalse);
    });

    test('a radius change does', () {
      expect(base.copyWith(radius: 50).needsRefetch(base), isTrue);
    });

    test('a date change does', () {
      expect(base.copyWith(date: 'today').needsRefetch(base), isTrue);
    });

    test('a different custom range does', () {
      final first = base.copyWith(
        date: DiscoverFilters.customDate,
        range: DateTimeRange(
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 5, 7),
        ),
      );
      final second = first.copyWith(
        range: DateTimeRange(
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 6, 7),
        ),
      );

      // Both are date == 'custom', so comparing the date alone would miss
      // this and leave May's events on screen for a June search.
      expect(second.needsRefetch(first), isTrue);
    });

    test('an identical set does not', () {
      expect(base.copyWith().needsRefetch(base), isFalse);
    });
  });

  group('summary', () {
    test('reads as distance and date', () {
      expect(DiscoverFilters.initial.summary, 'Within 25 mi · Any time');
    });

    test('names a custom range by its dates', () {
      final f = DiscoverFilters.initial.copyWith(
        date: DiscoverFilters.customDate,
        range: DateTimeRange(
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 5, 9),
        ),
      );

      expect(f.summary, 'Within 25 mi · 1 May – 9 May');
    });

    test('falls back to Any time when custom has no range', () {
      // Selecting "Custom dates" and cancelling the picker leaves the date
      // set with nothing to show for it.
      final f = DiscoverFilters.initial.copyWith(
        date: DiscoverFilters.customDate,
      );

      expect(f.dateLabel, 'Any time');
    });
  });

  group('defaults', () {
    test('opens showing every category it offers', () {
      // Every one the sheet shows, so the map is never silently narrower
      // than the filters claim.
      expect(DiscoverFilters.initial.kinds, DiscoverKind.shown.toSet());
    });

    test('offers only the categories with something behind them', () {
      // Businesses and Locations are hidden for now — they have no post
      // type, so every chip for them was a chip nobody could use. Hidden
      // rather than deleted: the enum, the colours and the pin images all
      // still exist, so bringing them back is one line in `shown`.
      expect(DiscoverKind.shown, [
        DiscoverKind.event,
        DiscoverKind.venue,
        DiscoverKind.track,
      ]);

      expect(
        DiscoverKind.shown,
        everyElement(
          predicate((k) {
            return (k as DiscoverKind).backed;
          }, 'is backed by a post type'),
        ),
      );
    });

    test('keeps the hidden ones intact', () {
      // They are still enum values with their own colour and pin id, which
      // is what makes un-hiding them a one-line change rather than a
      // re-implementation.
      expect(DiscoverKind.values, contains(DiscoverKind.business));
      expect(DiscoverKind.values, contains(DiscoverKind.location));
    });

    test('opens at the distance the design shows', () {
      expect(DiscoverFilters.initial.radius, 25);
      expect(DiscoverFilters.radii, contains(25));
    });

    test('offers a national range', () {
      expect(DiscoverFilters.radii, contains(DiscoverFilters.national));
      // Last, so the list reads as increasing distance.
      expect(DiscoverFilters.radii.last, DiscoverFilters.national);
    });

    test('national is the radius the server already means by it', () {
      // get_radius_for_location('national') is 2000 miles. Matching it keeps
      // the map and the list screens showing the same thing.
      expect(DiscoverFilters.national, 2000);
    });

    test('every distance reads as a distance except national', () {
      for (final r in DiscoverFilters.radii) {
        final label = DiscoverFilters.radiusLabel(r);
        if (r == DiscoverFilters.national) {
          // "2000 mi" is a strange way to write "everywhere".
          expect(label, 'National');
        } else {
          expect(label, '$r mi');
        }
      }
    });

    test('the summary says nationwide rather than a mileage', () {
      final f = DiscoverFilters.initial.copyWith(
        radius: DiscoverFilters.national,
      );
      expect(f.summary, 'Nationwide · Any time');
    });

    test('changing to national still refetches', () {
      // Radius is a query parameter, so it cannot be applied to the loaded
      // page the way a category can.
      final base = DiscoverFilters.initial;
      final national = base.copyWith(radius: DiscoverFilters.national);
      expect(national.needsRefetch(base), isTrue);
    });
  });

  group('categories', () {
    test('only the types WordPress actually has are backed', () {
      // Businesses and locations have no post type behind them, so they read
      // "Coming soon" in the filters rather than claiming a count of 0.
      final backed = DiscoverKind.values.where((k) => k.backed).toSet();
      expect(backed, {
        DiscoverKind.event,
        DiscoverKind.venue,
        DiscoverKind.track,
      });
    });

    test('every category has its own pin image id', () {
      final ids = DiscoverKind.values.map((k) => k.iconId).toSet();
      // A shared id would have two categories drawing the same pin, which
      // makes the colour key meaningless.
      expect(ids.length, DiscoverKind.values.length);
    });

    test('every category has a distinct colour', () {
      final colours = DiscoverKind.values.map((k) => k.colour).toSet();
      expect(colours.length, DiscoverKind.values.length);
    });
  });
}
