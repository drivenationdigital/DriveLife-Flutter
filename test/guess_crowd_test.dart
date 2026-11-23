import 'package:drivelife/models/guess_crowd.dart';
import 'package:flutter_test/flutter_test.dart';

/// What everybody else picked, and how it is said back.
///
/// Worth testing because every line it produces is a claim about a
/// number, and the ways of getting it wrong all read as perfectly
/// confident sentences: a lone picker rounded to "0%", a percentage of
/// two people presented as a finding, a boast about agreeing with
/// everybody.
void main() {
  group('the arithmetic', () {
    test('a share is a share of everyone who played', () {
      const crowd = GuessCrowd([10, 30, 40, 20]);

      expect(crowd.total, 100);
      expect(crowd.shareOf(1), 0.3);
      expect(crowd.percentOf(2), '40%');
    });

    test('nobody is 0%', () {
      const crowd = GuessCrowd([10, 0, 0, 0]);

      expect(crowd.percentOf(1), '0%');
    });

    test('somebody who rounds away is not nobody', () {
      // One picker in four hundred is the most interesting answer on
      // the card, and "0%" says they do not exist.
      const crowd = GuessCrowd([399, 1, 0, 0]);

      expect(crowd.percentOf(1), '<1%');
    });

    test('an index past the end is nothing, not a crash', () {
      const crowd = GuessCrowd([1, 2]);

      expect(crowd.countOf(9), 0);
      expect(crowd.shareOf(9), 0);
      expect(crowd.percentOf(-1), '0%');
    });

    test('an empty breakdown divides by nothing', () {
      expect(GuessCrowd.none.total, 0);
      expect(GuessCrowd.none.shareOf(0), 0);
      expect(GuessCrowd.none.hasCrowd, isFalse);
    });
  });

  group('when there is no crowd to speak of', () {
    test('a handful of people is not a percentage', () {
      // "67% agreed with you" out of two others reads as a finding and
      // is noise.
      const crowd = GuessCrowd([1, 2, 1, 0]);

      expect(crowd.hasCrowd, isFalse);
      expect(crowd.noteFor(myChoice: 1, correct: true), isNull);
    });

    test('exactly the minimum counts', () {
      const crowd = GuessCrowd([1, 2, 1, 1]);

      expect(crowd.total, GuessCrowd.minimumPlayers);
      expect(crowd.hasCrowd, isTrue);
    });

    test('somebody who did not play is told nothing', () {
      const crowd = GuessCrowd([10, 30, 40, 20]);

      expect(crowd.noteFor(myChoice: null, correct: null), isNull);
    });

    test('a game that has not revealed yet says nothing', () {
      // correct is null until the server will say, and a note built
      // without it would be a note about an unknown.
      const crowd = GuessCrowd([10, 30, 40, 20]);

      expect(crowd.noteFor(myChoice: 2, correct: null), isNull);
    });
  });

  group('what it says', () {
    test('right and rare is a boast', () {
      const crowd = GuessCrowd([80, 10, 7, 3]);

      expect(
        crowd.noteFor(myChoice: 3, correct: true),
        'Only 3% got this one. Nice spot.',
      );
    });

    test('right and common is gentle, because everybody got it', () {
      const crowd = GuessCrowd([70, 10, 10, 10]);

      expect(crowd.noteFor(myChoice: 0, correct: true), '70% got this one.');
    });

    test('right and ordinary just reports it', () {
      const crowd = GuessCrowd([40, 30, 20, 10]);

      expect(
        crowd.noteFor(myChoice: 0, correct: true),
        '40% of players got it right.',
      );
    });

    test('wrong and common is the whole point of the feature', () {
      const crowd = GuessCrowd([54, 30, 10, 6]);

      expect(
        crowd.noteFor(myChoice: 0, correct: false),
        'You were not alone - 54% said the same.',
      );
    });

    test('wrong and rare is said plainly, with no consoling', () {
      // Nobody needs comforting about a car quiz, and a sympathetic
      // line would be worse than the number.
      const crowd = GuessCrowd([90, 6, 3, 1]);

      expect(
        crowd.noteFor(myChoice: 3, correct: false),
        'Only 1% picked that one.',
      );
    });

    test('wrong and middling is neither', () {
      const crowd = GuessCrowd([60, 25, 10, 5]);

      expect(
        crowd.noteFor(myChoice: 1, correct: false),
        '25% picked the same.',
      );
    });
  });

  // For the list of old games, where the interesting number is not
  // what anybody picked but how hard the car turned out to be.
  group('how hard it was', () {
    test('the share on the answer', () {
      const crowd = GuessCrowd([80, 10, 7, 3]);

      expect(crowd.solvedLabel(3), '3% got it');
    });

    test('a car almost nobody got still names them', () {
      const crowd = GuessCrowd([399, 1, 0, 0]);

      expect(crowd.solvedLabel(1), '<1% got it');
    });

    test('no answer index, nothing to say', () {
      const crowd = GuessCrowd([80, 10, 7, 3]);

      expect(crowd.solvedLabel(null), isNull);
    });

    test('too few players, nothing to say', () {
      // A row that shrugs is worse than a row that does not mention it.
      const crowd = GuessCrowd([1, 2, 0, 0]);

      expect(crowd.solvedLabel(1), isNull);
    });

    test('a game with no breakdown at all', () {
      expect(GuessCrowd.none.solvedLabel(0), isNull);
    });
  });

  group('reading what the server sent', () {
    test('ordinary numbers', () {
      expect(GuessCrowd.fromMap([1, 2, 3]).counts, [1, 2, 3]);
    });

    test('strings, because MySQL columns arrive as text', () {
      expect(GuessCrowd.fromMap(['4', '0', '12']).counts, [4, 0, 12]);
    });

    test('a server that does not send it yet', () {
      // The breakdown is decoration on a screen that works without it.
      expect(GuessCrowd.fromMap(null).counts, isEmpty);
      expect(GuessCrowd.fromMap('nonsense').counts, isEmpty);
      expect(GuessCrowd.fromMap(null).hasCrowd, isFalse);
    });

    test('rubbish inside the list is a zero, not a crash', () {
      expect(GuessCrowd.fromMap([5, null, 'x']).counts, [5, 0, 0]);
    });
  });
}
