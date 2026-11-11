import 'dart:convert';

// Prefixed because `Key` is also a Flutter widget key, and an
// unprefixed import makes every use of it ambiguous.
import 'package:encrypt/encrypt.dart' as crypt;
import 'package:flutter/foundation.dart';

/// The envelope that marks a stored message as encrypted.
///
/// `dl1.<key id>.<base64url(iv ‖ ciphertext ‖ tag)>`
///
/// ── WHY AN ENVELOPE AND NOT A COLUMN ────────────────────────────────
///
/// Plaintext and ciphertext have to live in the same `content` column
/// at the same time, for a long time: there are years of existing
/// messages, and app versions that will never be updated. A second
/// column would mean every reader checking two places and every writer
/// deciding between them.
///
/// A prefix makes the question local to the value itself: a row either
/// announces that it is encrypted or it does not, and anything that is
/// not an envelope is returned untouched.
const String _kEnvelopePrefix = 'dl1.';

/// GCM's standard nonce length. Twelve bytes is what the mode is
/// specified around; other lengths are legal but get rehashed
/// internally, which buys nothing and loses interoperability.
const int _kIvLength = 12;

/// How a stored value came back.
enum MessageTextKind {
  /// Not an envelope. An old message, stored before encryption, and
  /// returned exactly as it was.
  plaintext,

  /// An envelope that opened.
  decrypted,

  /// An envelope that did not open: no key loaded yet, the wrong key,
  /// or a value that has been tampered with.
  unreadable,
}

/// A stored message's text, and whether it could be read.
@immutable
class MessageText {
  final String value;
  final MessageTextKind kind;

  const MessageText(this.value, this.kind);

  bool get isUnreadable => kind == MessageTextKind.unreadable;
}

/// Encrypts message bodies so Supabase never holds the words.
///
/// ── WHAT THIS DOES AND DOES NOT PROTECT ─────────────────────────────
///
/// The key is held by WordPress and handed to signed-in clients. It is
/// never given to Supabase, so a dump of the messages table, a stray
/// backup, a leaked service key or anybody browsing the dashboard sees
/// ciphertext and nothing else. That is the whole point: today those
/// all read as plain English.
///
/// It is NOT end-to-end, and must not be described as such. Every
/// signed-in device holds the same key, so anyone who can pull it out
/// of an app binary can read any message they can also fetch. That is
/// the price of server-side moderation — dl_scan_record() has to see
/// the words, which rules out a key the server cannot use.
///
/// ── WHY EVERY FAILURE IS SILENT ─────────────────────────────────────
///
/// A thread that will not open is worse than one showing a placeholder
/// for a single message. Nothing here throws: an unreadable value
/// comes back as [MessageTextKind.unreadable] and the caller decides
/// what to draw.
class MessageCrypto {
  const MessageCrypto._();

  static Uint8List? _key;
  static String? _keyId;

  /// Whether a key is loaded and messages can be encrypted.
  ///
  /// Reading does not need this — plaintext passes through regardless —
  /// but WRITING does, and a writer without a key must send plaintext
  /// rather than nothing.
  static bool get ready => _key != null && _keyId != null;

  /// The id of the loaded key, for diagnostics.
  static String? get keyId => _keyId;

  /// Bumped whenever the key changes.
  ///
  /// ── WHY A SCREEN NEEDS TO KNOW ───────────────────────────────────
  ///
  /// [decrypt] is synchronous, so a key that arrives after a thread has
  /// already been drawn leaves unreadable bubbles with nothing to
  /// trigger a repaint — and nothing else is guaranteed to rebuild the
  /// list, because a realtime event only fires if somebody happens to
  /// send a message.
  ///
  /// The alternative was blocking the thread on the key fetch before it
  /// could draw anything, which is worse: it puts a network request in
  /// front of the UI on every cold start, and leaves the screen empty
  /// if the request is slow.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Installs the key. Called by whatever fetched it.
  ///
  /// [keyBase64] is 32 raw bytes, base64 encoded. A key of any other
  /// length is refused rather than padded: silently encrypting under a
  /// key nobody meant to use is worse than not encrypting.
  static bool install({required String keyId, required String keyBase64}) {
    try {
      final bytes = base64Decode(keyBase64);

      if (bytes.length != 32) {
        debugPrint('[MessageCrypto] refused a ${bytes.length}-byte key');
        return false;
      }

      if (keyId.isEmpty || keyId.contains('.')) {
        // A dot would split the envelope in the wrong place.
        debugPrint('[MessageCrypto] refused key id "$keyId"');
        return false;
      }

      _key = Uint8List.fromList(bytes);
      _keyId = keyId;

      // After the assignment, so a listener that reads the key during
      // the notification sees the new one.
      revision.value++;

      return true;
    } catch (e) {
      debugPrint('[MessageCrypto] install failed: $e');
      return false;
    }
  }

  /// Forgets the key. For sign-out.
  static void clear() {
    final had = ready;

    _key = null;
    _keyId = null;

    // Only when something actually changed: clear() is called
    // defensively in several places, and a notification per call would
    // rebuild every open thread for nothing.
    if (had) revision.value++;
  }

  /// Whether [stored] is one of our envelopes.
  static bool isEnvelope(String? stored) =>
      stored != null && stored.startsWith(_kEnvelopePrefix);

  /// Turns a message body into what should be written to the column.
  ///
  /// Returns null when there is no key, which the caller must treat as
  /// "send it as plaintext" rather than "fail". A message that will not
  /// send is a worse outcome than one stored the way every message
  /// before it was.
  ///
  /// [conversationId] is bound in as associated data, so a ciphertext
  /// lifted from one thread will not open in another.
  static String? encrypt(String plaintext, {required String conversationId}) {
    final key = _key;
    final id = _keyId;

    if (key == null || id == null) return null;
    if (plaintext.isEmpty) return null; // nothing to hide

    try {
      final iv = crypt.IV.fromSecureRandom(_kIvLength);

      final encrypter = crypt.Encrypter(crypt.AES(crypt.Key(key), mode: crypt.AESMode.gcm));

      final sealed = encrypter.encryptBytes(
        Uint8List.fromList(utf8.encode(plaintext)),
        iv: iv,
        associatedData: Uint8List.fromList(utf8.encode(conversationId)),
      );

      final payload = Uint8List(iv.bytes.length + sealed.bytes.length)
        ..setAll(0, iv.bytes)
        ..setAll(iv.bytes.length, sealed.bytes);

      return '$_kEnvelopePrefix$id.${base64Url.encode(payload)}';
    } catch (e) {
      debugPrint('[MessageCrypto] encrypt failed: $e');
      return null;
    }
  }

  /// Turns a stored value into text to show.
  ///
  /// Synchronous on purpose: this is called from ChatMessage.fromMap,
  /// which is a factory constructor on the read path of every message
  /// in a thread. Making it async would mean reworking every caller and
  /// holding a thread's worth of futures.
  static MessageText decrypt(String? stored, {required String conversationId}) {
    final text = stored ?? '';

    // The overwhelmingly common case for a long time yet: a message
    // written before any of this existed.
    if (!isEnvelope(text)) {
      return MessageText(text, MessageTextKind.plaintext);
    }

    final key = _key;

    // An envelope arriving before the key has loaded. Not an error —
    // the key fetch is a network call and a thread can open first.
    if (key == null) {
      return const MessageText('', MessageTextKind.unreadable);
    }

    try {
      final parts = text.split('.');

      // prefix, key id, payload
      if (parts.length != 3) {
        return const MessageText('', MessageTextKind.unreadable);
      }

      // A message sealed under a key this client does not hold. Will
      // matter the first time a key is rotated.
      if (parts[1] != _keyId) {
        debugPrint('[MessageCrypto] message sealed under key ${parts[1]}');
        return const MessageText('', MessageTextKind.unreadable);
      }

      // ── NORMALISED, BECAUSE PHP STRIPS THE PADDING ───────────────
      //
      // Dart writes base64url WITH '=' padding and refuses input
      // without it. PHP's base64url convention drops it, and the
      // historical backfill is encrypted in PHP — so envelopes written
      // there would be rejected here as malformed, and a backfilled
      // conversation would read as a wall of unreadable messages.
      //
      // normalize() puts the padding back when it is missing and
      // leaves it alone when it is not, so both sides decode either.
      final payload = base64Url.decode(base64Url.normalize(parts[2]));

      if (payload.length <= _kIvLength) {
        return const MessageText('', MessageTextKind.unreadable);
      }

      final iv = crypt.IV(Uint8List.sublistView(payload, 0, _kIvLength));
      final body = Uint8List.sublistView(payload, _kIvLength);

      final encrypter = crypt.Encrypter(crypt.AES(crypt.Key(key), mode: crypt.AESMode.gcm));

      final opened = encrypter.decryptBytes(
        crypt.Encrypted(body),
        iv: iv,
        associatedData: Uint8List.fromList(utf8.encode(conversationId)),
      );

      return MessageText(utf8.decode(opened), MessageTextKind.decrypted);
    } catch (e) {
      // Includes a failed GCM tag check, which means the value was
      // altered in the database. Worth a line in the log and nothing
      // more alarming on screen.
      debugPrint('[MessageCrypto] could not open an envelope: $e');
      return const MessageText('', MessageTextKind.unreadable);
    }
  }

  /// Convenience for the many read sites that only want the text.
  static String decryptText(String? stored, {required String conversationId}) =>
      decrypt(stored, conversationId: conversationId).value;
}
