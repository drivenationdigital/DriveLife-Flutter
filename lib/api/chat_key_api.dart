import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/services/message_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Fetches the message key and hands it to [MessageCrypto].
///
/// ── WHY IT IS CACHED ────────────────────────────────────────────────
///
/// Chat has to work on a bad connection, and a thread that opens to a
/// screen of unreadable messages because one request timed out is a
/// broken app. The key is therefore kept in secure storage and loaded
/// from there first, with the network only used to pick up a rotation.
///
/// Secure storage is the Keychain on iOS and the EncryptedSharedPrefs
/// on Android, which is the same place the auth token already lives.
/// It is not a stronger guarantee than the token itself — anybody who
/// can read one can read the other — and it does not need to be: this
/// key protects the DATABASE, not the device.
class ChatKeyAPI {
  const ChatKeyAPI._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _keyIdSlot = 'dl_chat_key_id';
  static const String _keySlot = 'dl_chat_key';

  static final AuthService _auth = AuthService();

  /// Loads the key, cache first, then the network.
  ///
  /// Safe to call more than once and safe to call without a signed-in
  /// user. Never throws: a failure leaves [MessageCrypto] without a
  /// key, which means plaintext is still readable and new messages are
  /// sent as plaintext — exactly today's behaviour.
  static Future<void> load() async {
    if (MessageCrypto.ready) return;

    await _loadFromCache();

    // Refreshed even when the cache worked, so a rotated key is picked
    // up without the app being reinstalled. Not awaited for the cached
    // case, because chat should not wait on it.
    final refresh = _refreshFromServer();

    if (!MessageCrypto.ready) await refresh;
  }

  /// Re-reads the key from the server, for a rotation or a new sign-in.
  static Future<void> refresh() => _refreshFromServer();

  /// Forgets the key. For sign-out: the next user may not be allowed
  /// to read what this one could.
  static Future<void> clear() async {
    MessageCrypto.clear();

    try {
      await _storage.delete(key: _keyIdSlot);
      await _storage.delete(key: _keySlot);
    } catch (e) {
      debugPrint('[ChatKey] could not clear the cache: $e');
    }
  }

  static Future<void> _loadFromCache() async {
    try {
      final id = await _storage.read(key: _keyIdSlot);
      final key = await _storage.read(key: _keySlot);

      if (id == null || key == null) return;

      MessageCrypto.install(keyId: id, keyBase64: key);
    } catch (e) {
      debugPrint('[ChatKey] cache read failed: $e');
    }
  }

  static Future<void> _refreshFromServer() async {
    try {
      final token = await _auth.getToken();

      if (token == null) return;

      final response = await http
          .get(
            Uri.parse('${AppEnvironment.wordpressBase}/wp-json/app/v2/chat/key'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[ChatKey] server said ${response.statusCode}');
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      // A server without encryption configured answers 200 with
      // configured:false. That is a valid state, not a failure — it is
      // how chat keeps working on an environment that has no key.
      if (body['configured'] != true) {
        debugPrint('[ChatKey] server has no key configured');
        return;
      }

      final id = '${body['key_id'] ?? ''}';
      final key = '${body['key'] ?? ''}';

      if (id.isEmpty || key.isEmpty) return;

      if (!MessageCrypto.install(keyId: id, keyBase64: key)) return;

      await _storage.write(key: _keyIdSlot, value: id);
      await _storage.write(key: _keySlot, value: key);
    } catch (e) {
      // Offline, timed out, or malformed. The cached key stands.
      debugPrint('[ChatKey] refresh failed: $e');
    }
  }
}
