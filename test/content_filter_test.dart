import 'package:drivelife/services/content_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('leaves ordinary messages alone', () {
    const ordinary = [
      'Just picked up the new wheels, what do you think?',
      'Meet at the services at 7?',
      'That exhaust note is unreal',
      'Mate the turbo spooled and I nearly lost it',
      'How much did the respray set you back?',
      '',
      '   ',
    ];

    for (final message in ordinary) {
      test('"$message"', () {
        expect(ContentFilter.inspect(message), ContentFlag.none);
        expect(ContentFilter.shouldVeil(message), isFalse);
      });
    }
  });

  group('the Scunthorpe problem', () {
    // The reason _tokens matches whole words and never substrings. Every
    // one of these contains a listed word inside it, and every one is
    // ordinary vocabulary -- several of them specifically in a UK car
    // community, which is exactly the audience here.
    const innocent = [
      'Driving up to Scunthorpe on Saturday',
      'The cockpit is tight but the seats are superb',
      'Checked it with the dipstick, oil is fine',
      'Door knocker came loose again',
      'Needs a new drive shaft',
      'Torqued the wheel nuts to spec',
      'Classic shape, never gets old',
      'I need to assess the damage first',
      'Penistone Road, past the retail park',
      'Lake Titicaca was on the quiz',
      'He was a bit of a Cockburn about it',
      'Pass me the socket set',
      'Got it for a bargain, massive saving',
    ];

    for (final message in innocent) {
      test('"$message"', () {
        expect(
          ContentFilter.inspect(message),
          ContentFlag.none,
          reason: 'substring matching would wrongly flag this',
        );
      });
    }
  });

  group('casual swearing is mild, and is not veiled', () {
    const casual = [
      'That build is absolutely fucking incredible',
      'Shit, I forgot the meet was today',
      'Bloody hell that is quick',
      'The gearbox is knackered, what a bastard of a job',
    ];

    for (final message in casual) {
      test('"$message"', () {
        expect(ContentFilter.inspect(message), ContentFlag.mild);
        expect(
          ContentFilter.shouldVeil(message),
          isFalse,
          reason: 'veiling ordinary register trains people to tap through',
        );
      });
    }
  });

  group('spamming curse words escalates', () {
    test('four or more mild words is shouting, not conversation', () {
      expect(
        ContentFilter.inspect('fuck you you shit prick bastard'),
        ContentFlag.strong,
      );
      expect(
        ContentFilter.shouldVeil('fuck you you shit prick bastard'),
        isTrue,
      );
    });

    test('three is still conversation', () {
      expect(
        ContentFilter.inspect('shit mate that is a bloody damn mess'),
        ContentFlag.mild,
      );
    });
  });

  group('slurs veil on a single occurrence', () {
    const slurs = ['you absolute retard', 'go away you faggot', 'what a cunt'];

    for (final message in slurs) {
      test('"$message"', () {
        expect(ContentFilter.inspect(message), ContentFlag.strong);
        expect(ContentFilter.shouldVeil(message), isTrue);
      });
    }
  });

  group('threats, which is the point of the phrase list', () {
    const threats = [
      'kill yourself',
      'kys',
      'I know where you live',
      'watch your back mate',
      'im going to kill you',
      'youre dead',
    ];

    for (final message in threats) {
      test('"$message"', () {
        expect(
          ContentFilter.inspect(message),
          ContentFlag.strong,
          reason: 'none of these contain a listed word on their own',
        );
      });
    }

    test('a threat with no profanity in it still veils', () {
      // The case a swearing filter misses completely, and the one that
      // actually matters.
      expect(ContentFilter.shouldVeil('I know where you live.'), isTrue);
    });
  });

  group('obfuscation', () {
    test('leet substitution', () {
      expect(ContentFilter.inspect('you r3t4rd'), ContentFlag.strong);
    });

    test('asterisks and dots inside a word', () {
      expect(ContentFilter.inspect('you c*nt'), ContentFlag.strong);
      expect(ContentFilter.inspect('f.a.g.g.o.t'), ContentFlag.strong);
    });

    test('stretched letters', () {
      expect(ContentFilter.inspect('you retaaaaard'), ContentFlag.strong);
    });

    test('normalise collapses runs of three, not doubles', () {
      // Doubles must survive or ordinary English breaks: see the comment
      // on normalise().
      expect(ContentFilter.normalise('pass'), 'pass');
      expect(ContentFilter.normalise('assess'), 'assess');
      expect(ContentFilter.normalise('fuuuuck'), 'fuck');
    });
  });

  group('what this tier honestly cannot do', () {
    test('cruelty with no listed word gets through to tier two', () {
      // Not a bug. A word list cannot see this, which is the entire
      // argument for the Gemini pass in chat_webhook.php. Pinned as a
      // test so the limitation is visible rather than assumed.
      expect(
        ContentFilter.inspect(
          'everyone in the club thinks you are pathetic and nobody '
          'wants you at the meet',
        ),
        ContentFlag.none,
      );
    });
  });
}
