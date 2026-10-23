import 'package:drivelife/screens/chat/message_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

/// The grouping rules for a message thread.
///
/// Worth pinning because the list they serve is `reverse: true`: index 0 is
/// the NEWEST message and sits at the bottom, so "above" is a higher index.
/// Reading that backwards puts the avatar at the top of a block instead of
/// the bottom and the timestamp on the first message instead of the last —
/// which still renders perfectly, so nothing fails and the only symptom is
/// a thread that looks subtly wrong.

/// A message, reduced to the two fields grouping cares about.
class _M {
  final String sender;
  final DateTime at;
  const _M(this.sender, this.at);
}

void main() {
  final t0 = DateTime(2026, 3, 14, 9, 0);

  _M m(String sender, int minutesAfterT0) =>
      _M(sender, t0.add(Duration(minutes: minutesAfterT0)));

  /// Newest first, the order the thread holds them in.
  List<RunPosition> positions(List<_M> newestFirst) => [
    for (var i = 0; i < newestFirst.length; i++)
      runPositionAt<_M>(
        newestFirst,
        i,
        senderOf: (x) => x.sender,
        timeOf: (x) => x.at,
      ),
  ];

  group('continuesRun', () {
    test('same sender, close together', () {
      expect(
        continuesRun(
          earlierSender: 'a',
          earlierAt: t0,
          laterSender: 'a',
          laterAt: t0.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
    });

    test('a different sender always breaks the run', () {
      expect(
        continuesRun(
          earlierSender: 'a',
          earlierAt: t0,
          laterSender: 'b',
          laterAt: t0.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test('too long a gap breaks the run', () {
      expect(
        continuesRun(
          earlierSender: 'a',
          earlierAt: t0,
          laterSender: 'a',
          laterAt: t0.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('an out-of-order pair is still close together', () {
      // An optimistic local send can carry a timestamp a moment ahead of
      // the server's for the message before it. Without abs() that reads
      // as a negative gap, which is less than the window either way --
      // this pins the intent rather than the accident.
      expect(
        continuesRun(
          earlierSender: 'a',
          earlierAt: t0.add(const Duration(minutes: 1)),
          laterSender: 'a',
          laterAt: t0,
        ),
        isTrue,
      );
    });
  });

  group('runPositionAt', () {
    test('a lone message both starts and ends its run', () {
      final p = positions([m('a', 0)]).single;

      expect(p.startsRun, isTrue);
      expect(p.endsRun, isTrue);
      expect(p.startsDay, isTrue, reason: 'nothing above it');
    });

    test('a block of three: the oldest starts it, the newest ends it', () {
      // Newest first: index 0 is the last thing said.
      final p = positions([m('a', 4), m('a', 2), m('a', 0)]);

      // index 2 is the OLDEST, drawn at the top of the block.
      expect(p[2].startsRun, isTrue, reason: 'oldest is the top of the block');
      expect(p[2].endsRun, isFalse);

      expect(p[1].startsRun, isFalse, reason: 'middle');
      expect(p[1].endsRun, isFalse);

      // index 0 is the NEWEST, drawn at the bottom — this is the one that
      // carries the avatar and the timestamp.
      expect(p[0].startsRun, isFalse);
      expect(p[0].endsRun, isTrue, reason: 'newest is the bottom of the block');
    });

    test('a different sender splits one block into two', () {
      final p = positions([m('b', 2), m('a', 1), m('a', 0)]);

      expect(p[2].startsRun, isTrue);
      expect(p[2].endsRun, isFalse);
      expect(p[1].startsRun, isFalse);
      expect(p[1].endsRun, isTrue, reason: "a's block ends here");

      expect(p[0].startsRun, isTrue, reason: "b's block starts here");
      expect(p[0].endsRun, isTrue);
    });

    test('a long gap splits one sender into two blocks', () {
      final p = positions([m('a', 90), m('a', 1), m('a', 0)]);

      expect(p[1].endsRun, isTrue, reason: 'the early block ends');
      expect(p[0].startsRun, isTrue, reason: 'the late one starts fresh');
    });

    test('the day separator lands on the first message of each day', () {
      final day1 = DateTime(2026, 3, 14, 23, 50);
      final day2 = DateTime(2026, 3, 15, 0, 10);

      // Newest first: the day-2 message is index 0.
      final list = [_M('a', day2), _M('a', day1)];
      final p = positions(list);

      expect(
        p[0].startsDay,
        isTrue,
        reason: 'the first message of the new day carries the separator',
      );
      expect(p[1].startsDay, isTrue, reason: 'oldest: nothing above it');
    });

    test('twenty minutes apart on the same day is one day, two blocks', () {
      final p = positions([m('a', 20), m('a', 0)]);

      expect(p[0].startsDay, isFalse, reason: 'same calendar day');
      expect(p[0].startsRun, isTrue, reason: 'but a new block');
    });
  });

  group('sameCalendarDay', () {
    test('a minute either side of midnight is two days', () {
      expect(
        sameCalendarDay(
          DateTime(2026, 3, 14, 23, 59),
          DateTime(2026, 3, 15, 0, 1),
        ),
        isFalse,
      );
    });

    test('the same day a year apart is not the same day', () {
      expect(
        sameCalendarDay(DateTime(2025, 3, 14), DateTime(2026, 3, 14)),
        isFalse,
      );
    });
  });
}
