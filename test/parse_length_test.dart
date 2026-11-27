import 'package:drivelife/screens/media/video_upload_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The optional length somebody types when adding a YouTube video.
///
/// Worth testing because it is the one place a typo becomes a number
/// shown on a card as though it were a fact, and because the
/// bare-number case is a judgement rather than an obvious reading.
void main() {
  group('parseLength', () {
    test('mm:ss', () {
      expect(parseLength('38:14'), 38 * 60 + 14);
      expect(parseLength('0:45'), 45);
      expect(parseLength('8:12'), 8 * 60 + 12);
    });

    test('h:mm:ss', () {
      expect(parseLength('1:02:30'), 3600 + 2 * 60 + 30);
      expect(parseLength('2:00:00'), 7200);
    });

    test('a bare number is MINUTES, not seconds', () {
      // How somebody types the length of a podcast. Reading "38" as
      // thirty-eight seconds would be right by the clock and wrong by
      // every expectation.
      expect(parseLength('38'), 38 * 60);
      expect(parseLength('1'), 60);
    });

    test('whitespace is forgiven', () {
      expect(parseLength('  38:14  '), 38 * 60 + 14);
      expect(parseLength('1 : 02 : 30'), 3600 + 2 * 60 + 30);
    });

    test('nothing means nothing, not zero seconds shown as 0:00', () {
      expect(parseLength(''), 0);
      expect(parseLength('   '), 0);
    });

    test('rubbish is rejected whole, never partly accepted', () {
      // The danger is a half-read value: "38:ab" quietly becoming
      // thirty-eight minutes is worse than being ignored, because
      // nobody checks a number that looks plausible.
      expect(parseLength('38:ab'), 0);
      expect(parseLength('abc'), 0);
      expect(parseLength('1:2:3:4'), 0);
      expect(parseLength('-5'), 0);
      expect(parseLength('1:-2'), 0);
    });

    test('values that are not normalised still add up', () {
      // "90" seconds in the seconds slot is not a thing a person
      // types, but if they do it should mean ninety seconds rather
      // than be refused.
      expect(parseLength('0:90'), 90);
    });
  });
}
