import 'package:drivelife/services/revealed_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await RevealedMessages.clear('7');
    await RevealedMessages.clear('8');
  });

  test('a revealed message is remembered', () async {
    await RevealedMessages.add('7', 'msg-a');

    expect(await RevealedMessages.forUser('7'), contains('msg-a'));
    expect(RevealedMessages.cachedFor('7'), contains('msg-a'));
  });

  test(
    'it survives the cache being dropped, which is the whole point',
    () async {
      await RevealedMessages.add('7', 'msg-a');

      // Reopening the thread is a fresh read. Clearing only the in-memory
      // copy is how that looks from here.
      RevealedMessages.debugForgetCache();

      expect(RevealedMessages.cachedFor('7'), isEmpty);
      expect(await RevealedMessages.forUser('7'), contains('msg-a'));
    },
  );

  test('one account does not see another account\'s reveals', () async {
    await RevealedMessages.add('7', 'msg-a');

    expect(await RevealedMessages.forUser('8'), isNot(contains('msg-a')));
  });

  test('cachedFor is empty rather than throwing before a load', () {
    RevealedMessages.debugForgetCache();
    expect(RevealedMessages.cachedFor('99'), isEmpty);
  });

  test('revealing the same message twice is one entry', () async {
    await RevealedMessages.add('7', 'msg-a');
    await RevealedMessages.add('7', 'msg-a');

    expect((await RevealedMessages.forUser('7')).length, 1);
  });

  test('the set is capped, oldest dropped first', () async {
    for (var i = 0; i < 520; i++) {
      await RevealedMessages.add('7', 'msg-$i');
    }

    final set = await RevealedMessages.forUser('7');

    expect(set.length, 500);
    expect(set, isNot(contains('msg-0')), reason: 'oldest should fall off');
    expect(set, contains('msg-519'), reason: 'newest must be kept');
  });

  test('clear forgets everything for one account only', () async {
    await RevealedMessages.add('7', 'msg-a');
    await RevealedMessages.add('8', 'msg-b');

    await RevealedMessages.clear('7');

    expect(await RevealedMessages.forUser('7'), isEmpty);
    expect(await RevealedMessages.forUser('8'), contains('msg-b'));
  });
}
