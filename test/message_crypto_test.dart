import 'dart:convert';

import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/services/message_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Message encryption.
///
/// Every assertion here is load-bearing in a way that is invisible on
/// screen. A round trip that quietly fails shows an empty bubble; a
/// plaintext passthrough that stops working makes years of existing
/// messages vanish; an envelope that opens under the wrong conversation
/// means ciphertext can be moved between threads.
void main() {
  const conversation = 'conv-abc-123';

  // 32 bytes, as base64. Not a real key.
  final testKey = base64Encode(List<int>.generate(32, (i) => i));
  final otherKey = base64Encode(List<int>.generate(32, (i) => 255 - i));

  setUp(() {
    MessageCrypto.clear();
    MessageCrypto.install(keyId: 'k1', keyBase64: testKey);
  });

  tearDown(MessageCrypto.clear);

  group('round trip', () {
    test('a message comes back exactly as it went in', () {
      const plain = 'Meet at the Ace at 7? Bring the Golf.';

      final sealed = MessageCrypto.encrypt(plain, conversationId: conversation);

      expect(sealed, isNotNull);
      expect(sealed, startsWith('dl1.k1.'));
      expect(sealed, isNot(contains('Ace')));

      final opened = MessageCrypto.decrypt(
        sealed,
        conversationId: conversation,
      );

      expect(opened.value, plain);
      expect(opened.kind, MessageTextKind.decrypted);
    });

    test('emoji and non-Latin text survive', () {
      // UTF-8 round trips through the byte layer, not the string one.
      for (final plain in ['🏎️💨 let\'s go', 'Grüße aus München', '你好，车友']) {
        final sealed = MessageCrypto.encrypt(
          plain,
          conversationId: conversation,
        );

        expect(
          MessageCrypto.decrypt(sealed, conversationId: conversation).value,
          plain,
          reason: plain,
        );
      }
    });

    test('a very long message round trips', () {
      final plain = 'a' * 20000;

      final sealed = MessageCrypto.encrypt(plain, conversationId: conversation);

      expect(
        MessageCrypto.decrypt(sealed, conversationId: conversation).value,
        plain,
      );
    });

    test('the same text encrypts differently every time', () {
      // A fresh IV per message. Without it, identical messages produce
      // identical ciphertext and the table leaks who said what.
      final a = MessageCrypto.encrypt('ok', conversationId: conversation);
      final b = MessageCrypto.encrypt('ok', conversationId: conversation);

      expect(a, isNot(b));
    });
  });

  group('living alongside plaintext', () {
    test('an old plaintext message passes straight through', () {
      // THE compatibility guarantee: years of existing messages.
      final result = MessageCrypto.decrypt(
        'just a normal message',
        conversationId: conversation,
      );

      expect(result.value, 'just a normal message');
      expect(result.kind, MessageTextKind.plaintext);
    });

    test('an empty body is left alone', () {
      // A photo with no caption.
      final result = MessageCrypto.decrypt('', conversationId: conversation);

      expect(result.value, '');
      expect(result.kind, MessageTextKind.plaintext);
    });

    test('null reads as empty plaintext', () {
      expect(
        MessageCrypto.decrypt(null, conversationId: conversation).kind,
        MessageTextKind.plaintext,
      );
    });

    test('text that merely mentions the prefix is still plaintext', () {
      // Someone typing about the format itself.
      const plain = 'the format is dl1 dot something';

      expect(
        MessageCrypto.decrypt(plain, conversationId: conversation).value,
        plain,
      );
    });

    test('an envelope with the padding stripped still opens', () {
      // What PHP produces. Its base64url convention drops '=', and
      // Dart refuses unpadded input unless it is normalised first — so
      // without that, every message written by the historical backfill
      // would read as unreadable.
      // Swept across lengths because whether base64 pads at all depends
      // on the payload length mod 3 — a single fixed message can
      // silently test nothing.
      var sawPadding = false;

      for (var length = 1; length <= 12; length++) {
        final plain = 'x' * length;

        final sealed = MessageCrypto.encrypt(
          plain,
          conversationId: conversation,
        )!;

        final parts = sealed.split('.');
        if (parts[2].contains('=')) sawPadding = true;

        final unpadded =
            '${parts[0]}.${parts[1]}.${parts[2].replaceAll('=', '')}';

        final opened = MessageCrypto.decrypt(
          unpadded,
          conversationId: conversation,
        );

        expect(opened.value, plain, reason: 'length $length');
        expect(opened.kind, MessageTextKind.decrypted, reason: 'length $length');
      }

      expect(sawPadding, isTrue, reason: 'the sweep must cover padded cases');
    });

    test('text that STARTS with the prefix but is not an envelope', () {
      // Worst case: a user types "dl1.hello". It is claimed as an
      // envelope, fails to open, and must not throw or show garbage.
      final result = MessageCrypto.decrypt(
        'dl1.hello there',
        conversationId: conversation,
      );

      expect(result.kind, MessageTextKind.unreadable);
      expect(result.value, '');
    });
  });

  group('refusing what it should refuse', () {
    test('a ciphertext will not open in another conversation', () {
      // conversation_id is bound in as associated data, so a row lifted
      // from one thread into another fails its tag check.
      final sealed = MessageCrypto.encrypt(
        'private',
        conversationId: conversation,
      );

      final result = MessageCrypto.decrypt(
        sealed,
        conversationId: 'some-other-conversation',
      );

      expect(result.kind, MessageTextKind.unreadable);
    });

    test('a tampered body fails its tag check', () {
      final sealed = MessageCrypto.encrypt(
        'transfer approved',
        conversationId: conversation,
      )!;

      // Flip a character in the payload.
      final parts = sealed.split('.');
      final body = parts[2];
      final altered =
          body.substring(0, body.length - 2) +
          (body.endsWith('A') ? 'B' : 'A') +
          body.substring(body.length - 1);

      final result = MessageCrypto.decrypt(
        '${parts[0]}.${parts[1]}.$altered',
        conversationId: conversation,
      );

      expect(result.kind, MessageTextKind.unreadable);
    });

    test('a message sealed under another key is unreadable', () {
      final sealed = MessageCrypto.encrypt(
        'secret',
        conversationId: conversation,
      );

      MessageCrypto.clear();
      MessageCrypto.install(keyId: 'k2', keyBase64: otherKey);

      expect(
        MessageCrypto.decrypt(sealed, conversationId: conversation).kind,
        MessageTextKind.unreadable,
      );
    });

    test('rubbish envelopes do not throw', () {
      for (final bad in [
        'dl1.',
        'dl1.k1.',
        'dl1.k1.!!!!not base64!!!!',
        'dl1.k1.AAAA', // too short to hold an IV
        'dl1.k1.extra.parts.here',
      ]) {
        expect(
          () => MessageCrypto.decrypt(bad, conversationId: conversation),
          returnsNormally,
          reason: bad,
        );
        expect(
          MessageCrypto.decrypt(bad, conversationId: conversation).kind,
          MessageTextKind.unreadable,
          reason: bad,
        );
      }
    });
  });

  group('without a key', () {
    test('plaintext still reads, which is what keeps chat working', () {
      MessageCrypto.clear();

      final result = MessageCrypto.decrypt(
        'an old message',
        conversationId: conversation,
      );

      expect(result.value, 'an old message');
      expect(result.kind, MessageTextKind.plaintext);
    });

    test('encrypt returns null so the caller falls back to plaintext', () {
      MessageCrypto.clear();

      expect(
        MessageCrypto.encrypt('hello', conversationId: conversation),
        isNull,
      );
    });

    test('an envelope is unreadable rather than an exception', () {
      final sealed = MessageCrypto.encrypt(
        'hello',
        conversationId: conversation,
      );

      MessageCrypto.clear();

      expect(
        MessageCrypto.decrypt(sealed, conversationId: conversation).kind,
        MessageTextKind.unreadable,
      );
    });
  });

  group('key handling', () {
    test('a key of the wrong length is refused', () {
      MessageCrypto.clear();

      final short = base64Encode(List<int>.filled(16, 7));

      expect(MessageCrypto.install(keyId: 'k1', keyBase64: short), isFalse);
      expect(MessageCrypto.ready, isFalse);
    });

    test('a key id containing a dot is refused', () {
      // It would split the envelope in the wrong place.
      MessageCrypto.clear();

      expect(
        MessageCrypto.install(keyId: 'k.1', keyBase64: testKey),
        isFalse,
      );
      expect(MessageCrypto.ready, isFalse);
    });

    test('rubbish base64 is refused rather than thrown', () {
      MessageCrypto.clear();

      expect(
        MessageCrypto.install(keyId: 'k1', keyBase64: 'not base64 at all'),
        isFalse,
      );
    });

    test('clear really forgets it', () {
      expect(MessageCrypto.ready, isTrue);

      MessageCrypto.clear();

      expect(MessageCrypto.ready, isFalse);
      expect(MessageCrypto.keyId, isNull);
    });
  });

  /// The repaint signal.
  ///
  /// The key is fetched without blocking the chat screens, so it can
  /// arrive after a thread has been drawn. decrypt() is synchronous and
  /// nothing else reliably rebuilds a message list — a realtime event
  /// only fires if somebody sends something — so this notifier is the
  /// only thing standing between a slow first fetch and a thread that
  /// shows base64 until it is closed and reopened.
  group('key arrival', () {
    setUp(MessageCrypto.clear);

    String aKey(int fill) => base64.encode(List<int>.filled(32, fill));

    test('installing a key signals a repaint', () {
      final seen = <int>[];
      void listener() => seen.add(MessageCrypto.revision.value);
      MessageCrypto.revision.addListener(listener);

      expect(MessageCrypto.install(keyId: 'k1', keyBase64: aKey(1)), isTrue);

      MessageCrypto.revision.removeListener(listener);
      expect(seen, hasLength(1));
    });

    test('a listener reading the key during the signal sees the new one', () {
      // The bump has to come AFTER the assignment. If it did not, the
      // rebuild it triggers would decrypt with the old key — or with no
      // key — and paint exactly the unreadable bubbles it exists to fix.
      String? idDuringNotification;
      void listener() => idDuringNotification = MessageCrypto.keyId;
      MessageCrypto.revision.addListener(listener);

      MessageCrypto.install(keyId: 'k2', keyBase64: aKey(2));

      MessageCrypto.revision.removeListener(listener);
      expect(idDuringNotification, 'k2');
    });

    test('a refused key does not signal anything', () {
      MessageCrypto.install(keyId: 'k3', keyBase64: aKey(3));

      var bumps = 0;
      void listener() => bumps++;
      MessageCrypto.revision.addListener(listener);

      expect(
        MessageCrypto.install(keyId: 'short', keyBase64: base64.encode(List<int>.filled(16, 4))),
        isFalse,
      );

      MessageCrypto.revision.removeListener(listener);
      expect(bumps, 0);
    });

    test('clearing nothing does not signal a repaint', () {
      // clear() is called defensively in several places. A bump per
      // call would rebuild every open thread for no reason.
      var bumps = 0;
      void listener() => bumps++;
      MessageCrypto.revision.addListener(listener);

      MessageCrypto.clear();

      MessageCrypto.revision.removeListener(listener);
      expect(bumps, 0);
    });

    test('clearing a held key does signal a repaint', () {
      MessageCrypto.install(keyId: 'k5', keyBase64: aKey(5));

      var bumps = 0;
      void listener() => bumps++;
      MessageCrypto.revision.addListener(listener);

      MessageCrypto.clear();

      MessageCrypto.revision.removeListener(listener);
      expect(bumps, 1);
    });
  });

  /// The rollout flag.
  ///
  /// Reading an envelope is always on; only writing is gated, and it is
  /// now ON — new messages seal as soon as every participant in a
  /// thread has announced they can open one.
  ///
  /// What stops that reaching somebody on an older build is
  /// ChatReadiness, not this flag, which is why there is no allowlist
  /// and no minimum-version gate. An earlier version of this file had
  /// a second switch that sealed a named thread WITHOUT the readiness
  /// check; it was removed deliberately, because a second route to
  /// sealing is a second route to putting an unreadable message in
  /// somebody's thread.
  group('chat encryption rollout', () {
    test('writing is on, and reading was never gated', () {
      expect(FeatureFlags.encryptChatMessages, isTrue);

      // The asymmetry that makes the rollout safe: a build can always
      // OPEN an envelope, whatever the flag says. Turning writing off
      // again is a real off switch for new messages; it is not a way
      // to make old ones unreadable.
      MessageCrypto.clear();
      expect(
        MessageCrypto.install(keyId: 'rollout', keyBase64: base64.encode(List<int>.filled(32, 7))),
        isTrue,
      );

      final sealed = MessageCrypto.encrypt('still readable', conversationId: 'c1');
      expect(sealed, isNotNull);
      expect(
        MessageCrypto.decrypt(sealed!, conversationId: 'c1').value,
        'still readable',
      );

      MessageCrypto.clear();
    });
  });
}
