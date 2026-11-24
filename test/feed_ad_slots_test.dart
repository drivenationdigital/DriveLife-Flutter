import 'package:drivelife/models/feed_ad_slots.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where adverts land in the feed.
///
/// Worth testing hard because the failure is SILENT. Get the index
/// translation wrong and the feed swallows one post for every advert
/// shown: nothing crashes, nothing logs, and the only symptom is that
/// people quietly see less of what they came for. That is the bug
/// every ad-supported feed ships at least once.
void main() {
  const slots = FeedAdSlots();

  /// Walks the whole list and returns what each row is: a post index,
  /// or 'AD'. The clearest way to see the shape.
  List<String> rows(int postCount, [FeedAdSlots s = slots]) => [
    for (var i = 0; i < s.displayCount(postCount); i++)
      s.isAd(i, postCount) ? 'AD' : '${s.postIndexFor(i, postCount)}',
  ];

  group('the shape of it', () {
    test('four posts, no advert - the feed opens on content', () {
      expect(rows(4), ['0', '1', '2', '3']);
    });

    test('five posts, one advert after the fourth', () {
      expect(rows(5), ['0', '1', '2', '3', 'AD', '4']);
    });

    test('eleven posts, two adverts, six posts apart', () {
      expect(rows(11), [
        '0', '1', '2', '3',
        'AD',
        '4', '5', '6', '7', '8', '9',
        'AD',
        '10',
      ]);
    });
  });

  group('no post is ever swallowed', () {
    test('every post appears exactly once, at every length', () {
      // THE test. An index translation that drops a post loses it
      // silently, and nobody notices until engagement quietly drops.
      for (var count = 0; count < 60; count++) {
        final shown = rows(count).where((r) => r != 'AD').toList();

        expect(
          shown,
          List.generate(count, (i) => '$i'),
          reason: 'at $count posts',
        );
      }
    });

    test('the list grows by exactly the number of adverts', () {
      for (var count = 0; count < 60; count++) {
        expect(
          slots.displayCount(count),
          count + slots.adCount(count),
          reason: 'at $count posts',
        );
      }
    });
  });

  group('what must never happen', () {
    test('the first row is never an advert', () {
      for (var count = 0; count < 60; count++) {
        expect(slots.isAd(0, count), isFalse, reason: 'at $count posts');
      }
    });

    test('the feed never ENDS on an advert', () {
      // A spinner under an advert reads as "that is all, here is an
      // advert". Last impressions matter as much as first ones.
      for (var count = 1; count < 60; count++) {
        final last = slots.displayCount(count) - 1;

        expect(slots.isAd(last, count), isFalse, reason: 'at $count posts');
      }
    });

    test('two adverts are never next to each other', () {
      for (var count = 0; count < 60; count++) {
        final all = rows(count);

        for (var i = 1; i < all.length; i++) {
          expect(
            all[i] == 'AD' && all[i - 1] == 'AD',
            isFalse,
            reason: 'adjacent at $i, $count posts',
          );
        }
      }
    });

    test('the gap between adverts is always the same', () {
      final all = rows(50);
      final at = [
        for (var i = 0; i < all.length; i++)
          if (all[i] == 'AD') i,
      ];

      for (var i = 1; i < at.length; i++) {
        expect(at[i] - at[i - 1], slots.every + 1);
      }
    });
  });

  group('a member sees none', () {
    test('nothing is placed at any length', () {
      for (var count = 0; count < 60; count++) {
        expect(FeedAdSlots.none.adCount(count), 0, reason: 'at $count');
        expect(FeedAdSlots.none.displayCount(count), count);
        expect(FeedAdSlots.none.isAd(0, count), isFalse);
        expect(FeedAdSlots.none.isAd(4, count), isFalse);
      }
    });

    test('and the indices pass straight through', () {
      for (var i = 0; i < 20; i++) {
        expect(FeedAdSlots.none.postIndexFor(i, 20), i);
      }
    });
  });

  group('which advert is which', () {
    test('they are numbered in order', () {
      expect(slots.adIndexAt(4, 30), 0);
      expect(slots.adIndexAt(11, 30), 1);
      expect(slots.adIndexAt(18, 30), 2);
    });

    test('a post row has no advert number', () {
      expect(slots.adIndexAt(0, 30), isNull);
      expect(slots.adIndexAt(5, 30), isNull);
    });
  });

  group('other spacings', () {
    test('a tighter one still never opens on an advert', () {
      const tight = FeedAdSlots(firstAfter: 2, every: 3);

      expect(rows(10, tight), [
        '0', '1',
        'AD',
        '2', '3', '4',
        'AD',
        '5', '6', '7',
        'AD',
        '8', '9',
      ]);
    });

    test('and loses no posts either', () {
      const tight = FeedAdSlots(firstAfter: 2, every: 3);

      for (var count = 0; count < 40; count++) {
        final shown = rows(count, tight).where((r) => r != 'AD').toList();

        expect(shown.length, count, reason: 'at $count posts');
      }
    });
  });
}
