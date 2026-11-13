import 'package:drivelife/models/tag_suggestion.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/screens/create-post/post_tag_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saving the tag screen.
///
/// Every case below is a bug that shipped. They all presented the same
/// way — "removing a tag does nothing" — and all four lived in this one
/// decision, which is why it is now a function that can be asked
/// directly rather than state inside a screen that needs a signed-in
/// account and a photo with GPS to reach.
void main() {
  TaggedEntity car(String id, {String label = 'DR12 LFE'}) =>
      TaggedEntity(index: 0, id: id, type: 'car', label: label);

  TaggedEntity event(String id) =>
      TaggedEntity(index: 0, id: id, type: 'event', label: 'Cops & Cars');

  TaggedEntity person(String id) =>
      TaggedEntity(index: 0, id: id, type: 'user', label: 'someone');

  TagSuggestion place({bool guessed = false}) => TagSuggestion(
    id: '12246',
    title: 'The Motorist',
    kind: 'venue',
    guessed: guessed,
  );

  group('offers are not saved once the post exists', () {
    test('a guessed tag is written while posting', () {
      // The whole point of finding it. This is the flow that ends at
      // Share, where nothing is on the post yet.
      final plan = planPostTags(
        editing: false,
        events: [event('99')],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: {'99'},
      );

      expect(plan.add.map((t) => t.id), ['99']);
    });

    test('the same tag is only an offer when editing', () {
      // By now the post has whatever it is going to have, so a guess is
      // something that was removed or never taken. Saving it put a
      // removed venue straight back, which is the bug this prevents.
      final plan = planPostTags(
        editing: true,
        events: [event('99')],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: {'99'},
      );

      expect(plan.add, isEmpty);
    });

    test('accepting one clears the guess and it saves', () {
      // Picking it in the sheet removes it from guessedIds. A vehicle
      // picker that forgot to do this drew the chip in italics and
      // filtered it back out of the save, so it could never be tagged.
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: [car('3448')],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
      );

      expect(plan.add.map((t) => t.id), ['3448']);
    });

    test('an offer left alone is not treated as kept, so nothing is removed',
        () {
      // It was never a row. Counting it as kept would be harmless here
      // but wrong in principle; counting it as GONE would delete a row
      // that does not exist.
      final plan = planPostTags(
        editing: true,
        events: [event('99')],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: {'99'},
      );

      expect(plan.remove, isEmpty);
    });
  });

  group('removing a tag', () {
    test('a tag taken off is deleted by row id', () {
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {'event:99': 1234},
        guessedIds: const {},
      );

      expect(plan.remove, [1234]);
    });

    test('a tag still held is left alone', () {
      final plan = planPostTags(
        editing: true,
        events: [event('99')],
        vehicles: const [],
        people: const [],
        tagIds: const {'event:99': 1234},
        guessedIds: const {},
      );

      expect(plan.remove, isEmpty);
      expect(plan.add, isEmpty, reason: 'it is already a row');
    });

    test('a guessed tag that IS a row is removed, not kept', () {
      // The sweep applies a venue and an event automatically, so an
      // auto tag can be both a real row AND marked as a guess. Opening
      // Edit tags and saving must not quietly keep it.
      final plan = planPostTags(
        editing: true,
        events: [event('99')],
        vehicles: const [],
        people: const [],
        tagIds: const {'event:99': 1234},
        guessedIds: {'99'},
      );

      expect(
        plan.remove,
        [1234],
        reason: 'an offer is not kept, so its row goes',
      );
    });
  });

  group('tags already on the post are not re-sent', () {
    test('a person tag is never re-sent', () {
      // Re-sending moves it to the first photo and loses the position
      // it was given in the per-photo tagger.
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: [person('67004')],
        tagIds: const {'user:67004': 55},
        guessedIds: const {},
      );

      expect(plan.add, isEmpty);
      expect(plan.remove, isEmpty);
    });

    test('a person is never filtered as an offer', () {
      // Nothing tags a person automatically, so guessedIds should never
      // name one — but if it did, dropping them silently would be worse
      // than the stray id.
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: [person('67004')],
        tagIds: const {},
        guessedIds: {'67004'},
      );

      expect(plan.add.map((t) => t.id), ['67004']);
    });
  });

  group('the place, which is columns rather than a row', () {
    test('a chosen place is written', () {
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
        place: place(),
      );

      expect(plan.location, PostLocationAction.set);
      expect(plan.place?.id, '12246');
    });

    test('taking it off clears the columns', () {
      // This did nothing at all: the write was inside
      // `if (location != null)`, so removing the chip meant removing
      // the only thing that could have cleared it.
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
        place: null,
        hadPlace: true,
        placeRemoved: true,
      );

      expect(plan.location, PostLocationAction.clear);
    });

    test('a post that never had one is left alone', () {
      // Clearing unconditionally would wipe a place the composer set on
      // a post that reached this screen without one being suggested.
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
        place: null,
      );

      expect(plan.location, PostLocationAction.leave);
    });

    test('a merely suggested place is not written when editing', () {
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
        place: place(guessed: true),
      );

      expect(plan.location, PostLocationAction.leave);
      expect(plan.place, isNull);
    });

    test('but it IS written on the way out of posting', () {
      final plan = planPostTags(
        editing: false,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
        place: place(guessed: true),
      );

      expect(plan.location, PostLocationAction.set);
    });

    test('declining a suggestion on a post that had one still clears it', () {
      // The order matters: the post had a venue, the screen offered a
      // different one, and the user took the chip off. The old code
      // returned early on the guess and never reached the clear.
      final plan = planPostTags(
        editing: true,
        events: const [],
        vehicles: const [],
        people: const [],
        tagIds: const {},
        guessedIds: const {},
        place: null,
        hadPlace: true,
      );

      expect(plan.location, PostLocationAction.clear);
    });
  });

  group('a whole edit', () {
    test('keeps one, removes one, adds one, and clears the place', () {
      final plan = planPostTags(
        editing: true,
        events: const [],
        // 3448 stays, 9999 is newly picked.
        vehicles: [car('3448'), car('9999', label: 'CT19 YPR')],
        people: [person('67004')],
        tagIds: const {
          'car:3448': 11,
          // Taken off.
          'event:99': 22,
          'user:67004': 33,
        },
        guessedIds: const {},
        place: null,
        hadPlace: true,
        placeRemoved: true,
      );

      expect(plan.remove, [22], reason: 'only the event was taken off');
      expect(plan.add.map((t) => t.id), ['9999'], reason: 'only the new one');
      expect(plan.location, PostLocationAction.clear);
    });
  });
}
