import 'package:drivelife/models/tag_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Choosing which event a post of several photos is about.
///
/// ── THE BUG THIS PINS ───────────────────────────────────────────────
///
/// A set of photos from Leicester Airport on 23 August was tagged with
/// a different event. The merge kept the nearest copy of each place and
/// ordered the result by distance alone, so one stray frame that caught
/// something half a mile closer put that event at the top — and the top
/// is what gets applied without being asked.
///
/// What the post is ABOUT is what most of its photos saw.
void main() {
  TagSuggestion event(String id, {required double miles, int photos = 1}) =>
      TagSuggestion(
        id: id,
        title: 'Event $id',
        kind: 'event',
        distanceMiles: miles,
        photos: photos,
      );

  TagSuggestions photo(List<TagSuggestion> events) =>
      TagSuggestions(events: events);

  group('merging one photo at a time', () {
    test('the event most photos saw leads, not the nearest', () {
      // Three photos at the airport, one of which also picked up a
      // closer event down the road.
      final merged = photo([event('airport', miles: 0.4)])
          .mergedWith(photo([event('airport', miles: 0.6)]))
          .mergedWith(
            photo([
              event('airport', miles: 0.5),
              event('other', miles: 0.1),
            ]),
          );

      expect(merged.events.first.id, 'airport');
      expect(merged.events.first.photos, 3);
      expect(merged.events.last.id, 'other');
    });

    test('distance still decides between events with equal support', () {
      final merged = photo([
        event('far', miles: 4),
        event('near', miles: 1),
      ]).mergedWith(photo([event('far', miles: 4), event('near', miles: 1)]));

      expect(merged.events.map((e) => e.id).toList(), ['near', 'far']);
    });

    test('a single photo is ordered exactly as before', () {
      // Every count is one, so nothing about this changed.
      final merged = photo([
        event('c', miles: 9),
        event('a', miles: 1),
        event('b', miles: 5),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events.map((e) => e.id).toList(), ['a', 'b', 'c']);
    });

    test('the kept copy is the closest any photo saw it at', () {
      final merged = photo([
        event('airport', miles: 2.2),
      ]).mergedWith(photo([event('airport', miles: 0.3)]));

      expect(merged.events.single.distanceMiles, closeTo(0.3, 0.001));
      expect(merged.events.single.photos, 2);
    });

    test('a nearer copy arriving first is not thrown away', () {
      // The same as above with the photos the other way round, because
      // "keep the better one" is easy to write as "keep the last one".
      final merged = photo([
        event('airport', miles: 0.3),
      ]).mergedWith(photo([event('airport', miles: 2.2)]));

      expect(merged.events.single.distanceMiles, closeTo(0.3, 0.001));
      expect(merged.events.single.photos, 2);
    });

    test('counts add up across already-merged lists', () {
      // Merging is done pairwise down a list of photos, so both sides
      // can already be totals. Stepping by one would undercount.
      final left = photo([
        event('airport', miles: 1),
      ]).mergedWith(photo([event('airport', miles: 1)]));

      final right = photo([
        event('airport', miles: 1),
      ]).mergedWith(photo([event('airport', miles: 1)]));

      expect(left.mergedWith(right).events.single.photos, 4);
    });

    test('an event with no distance sorts last, not first', () {
      // A null distance used to read as infinity and still does.
      final merged = photo([
        TagSuggestion(id: 'nodist', title: 'No distance', kind: 'event'),
        event('known', miles: 12),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events.map((e) => e.id).toList(), ['known', 'nodist']);
    });

    test('support beats a missing distance', () {
      final merged = photo([
        TagSuggestion(id: 'nodist', title: 'No distance', kind: 'event'),
      ]).mergedWith(
        photo([
          TagSuggestion(id: 'nodist', title: 'No distance', kind: 'event'),
          event('known', miles: 12),
        ]),
      );

      expect(merged.events.first.id, 'nodist');
    });
  });

  group("reading the server's own count", () {
    test('photos comes off the payload', () {
      final found = TagSuggestions.fromMap({
        'events': [
          {'id': '9', 'title': 'Yiannimize Live', 'distance_mi': 0.4,
            'photos': 4},
          {'id': '7', 'title': 'Something closer', 'distance_mi': 0.1,
            'photos': 1},
        ],
      });

      expect(found.events.first.photos, 4);
    });

    test('a server that does not send it counts as one', () {
      // The sweep and the on-phone scan are different code paths, and
      // an older deployment sends no count at all.
      final found = TagSuggestions.fromMap({
        'events': [
          {'id': '9', 'title': 'Yiannimize Live', 'distance_mi': 0.4},
        ],
      });

      expect(found.events.single.photos, 1);
    });

    test('the order the server sent is kept', () {
      // fromMap does not re-sort: the server has already ranked these,
      // and sorting again on distance alone here would undo it.
      final found = TagSuggestions.fromMap({
        'events': [
          {'id': 'airport', 'title': 'Airport', 'distance_mi': 0.9,
            'photos': 3},
          {'id': 'other', 'title': 'Other', 'distance_mi': 0.1, 'photos': 1},
        ],
      });

      expect(found.events.map((e) => e.id).toList(), ['airport', 'other']);
    });
  });

  group('one thing entered into WordPress twice', () {
    // One event entered twice is two results a few hundred yards apart
    // on the same day. Shown that way it is a confusing list; acted on
    // it is worse, since the nearest is applied without asking and
    // which copy wins comes down to a rounding difference.
    //
    // Only an EXACT title match counts. A venue ran two separate events
    // on one site called "Motorshow and Family Fun day" and "Motor Show
    // & Family Fun Day"; an earlier rule that set punctuation aside and
    // read "&" as "and" collapsed those two into one, which deleted a
    // real event from the list.
    TagSuggestion show(
      String id,
      String title, {
      required double lat,
      required double lng,
      required double miles,
      String from = '2026-08-23',
      String? to,
    }) => TagSuggestion(
      id: id,
      title: title,
      kind: 'event',
      latitude: lat,
      longitude: lng,
      distanceMiles: miles,
      startsOn: DateTime.parse(from),
      endsOn: DateTime.parse(to ?? from),
    );

    TagSuggestions only(List<TagSuggestion> events) =>
        TagSuggestions(events: events);

    test('two similar names on one site are left as two events', () {
      // The real Leicester listing. These are separate events, and
      // collapsing them loses one.
      final merged = only([
        show('1', 'Motorshow and Family Fun day',
            lat: 52.6063444, lng: -1.0348197, miles: 0.1),
        show('2', 'Motor Show & Family Fun Day',
            lat: 52.6061, lng: -1.0340, miles: 0.2),
        show('3', 'Yiannimize Live | Leicester Motor Show',
            lat: 52.5942859, lng: -1.0184131, miles: 1.0),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events.map((e) => e.id).toList(), ['1', '2', '3']);
    });

    test('the same title twice IS one event', () {
      // What a duplicate actually looks like: one record entered or
      // imported twice, so the titles agree.
      final merged = only([
        show('1', 'Cars & Coffee', lat: 52.60, lng: -1.03, miles: 0.1),
        show('2', 'Cars & Coffee',
            lat: 52.6005, lng: -1.0305, miles: 0.2),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(1));
    });

    test('case and stray spacing are not a different title', () {
      final merged = only([
        show('1', 'Cars & Coffee', lat: 52.60, lng: -1.03, miles: 0.1),
        show('2', '  cars &  coffee ',
            lat: 52.6005, lng: -1.0305, miles: 0.2),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(1));
    });

    test('the nearest copy is the one kept', () {
      final merged = only([
        show('near', 'Cars & Coffee',
            lat: 52.6063, lng: -1.0348, miles: 0.1),
        show('far', 'Cars & Coffee', lat: 52.6061, lng: -1.0340, miles: 0.2),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events.single.id, 'near');
    });

    test('two photos keeping different copies still collapse', () {
      // The reason this is done on the phone as well as on the server.
      // Each photo's list is already deduplicated when it arrives, but
      // one photo kept copy A and the other kept copy B, and the ids
      // differ so the merge treats them as two events.
      final merged = only([
        show('1', 'Cars & Coffee',
            lat: 52.6063444, lng: -1.0348197, miles: 0.1),
      ]).mergedWith(
        only([
          show('2', 'Cars & Coffee',
              lat: 52.6061, lng: -1.0340, miles: 0.15),
        ]),
      );

      expect(merged.events, hasLength(1));
    });

    test('the same name far away is a different round', () {
      final merged = only([
        show('leics', 'Cars & Coffee', lat: 52.60, lng: -1.03, miles: 0.1),
        show('sheff', 'Cars & Coffee', lat: 53.40, lng: -1.47, miles: 0.2),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(2));
    });

    test('the same name on days that do not overlap is two runs', () {
      final merged = only([
        show('aug', 'Cars & Coffee', lat: 52.60, lng: -1.03, miles: 0.1),
        show('sep', 'Cars & Coffee',
            lat: 52.6005, lng: -1.0305, miles: 0.2, from: '2026-09-20'),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(2));
    });

    test('a shared day within two runs does collapse them', () {
      final merged = only([
        show('a', 'Cars & Coffee', lat: 52.60, lng: -1.03, miles: 0.1,
            from: '2026-08-22', to: '2026-08-23'),
        show('b', 'Cars & Coffee', lat: 52.6005, lng: -1.0305, miles: 0.2,
            from: '2026-08-23', to: '2026-08-24'),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(1));
    });

    test('a venue is never collapsed into an event of the same name', () {
      // The Motorist is a venue AND hosts events called after it. One
      // is dated and the other is not, which is what separates them.
      final merged = TagSuggestions(
        locations: [
          TagSuggestion(
            id: 'venue',
            title: 'The Motorist',
            kind: 'venue',
            latitude: 52.60,
            longitude: -1.03,
            distanceMiles: 0.1,
          ),
          TagSuggestion(
            id: 'event',
            title: 'The Motorist',
            kind: 'event',
            latitude: 52.6005,
            longitude: -1.0305,
            distanceMiles: 0.2,
            startsOn: DateTime.parse('2026-08-23'),
          ),
        ],
      ).mergedWith(TagSuggestions.empty);

      expect(merged.locations, hasLength(2));
    });

    test('a blank title is not a match for another blank one', () {
      final merged = only([
        show('1', '   ', lat: 52.60, lng: -1.03, miles: 0.1),
        show('2', '', lat: 52.6005, lng: -1.0305, miles: 0.2),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(2));
    });

    test('no coordinates means no collapse, rather than a guess', () {
      final merged = only([
        TagSuggestion(
          id: '1',
          title: 'Cars & Coffee',
          kind: 'event',
          distanceMiles: 0.1,
          startsOn: DateTime.parse('2026-08-23'),
        ),
        TagSuggestion(
          id: '2',
          title: 'Cars & Coffee',
          kind: 'event',
          distanceMiles: 0.2,
          startsOn: DateTime.parse('2026-08-23'),
        ),
      ]).mergedWith(TagSuggestions.empty);

      expect(merged.events, hasLength(2));
    });
  });

  test('marking one as a guess keeps its count', () {
    // asGuess and copyWith rebuild the object field by field, so a new
    // field is easy to drop on the floor there.
    final guess = event('airport', miles: 0.4, photos: 3).asGuess();

    expect(guess.photos, 3);
    expect(guess.guessed, isTrue);
    expect(guess.copyWith(guessed: false).photos, 3);
  });
}
