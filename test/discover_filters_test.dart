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
    test('opens showing every category', () {
      // Including the two with nothing behind them, so the map is not
      // silently narrower than the filter sheet claims.
      expect(
        DiscoverFilters.initial.kinds,
        DiscoverKind.values.toSet(),
      );
    });

    test('opens at the distance the design shows', () {
      expect(DiscoverFilters.initial.radius, 25);
      expect(DiscoverFilters.radii, contains(25));
    });
  });

  group('categories', () {
    test('only events and venues have a data source', () {
      final backed = DiscoverKind.values.where((k) => k.backed).toSet();
      expect(backed, {DiscoverKind.event, DiscoverKind.venue});
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
