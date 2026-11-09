import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// What came back from an unlink attempt.
///
/// A refusal is not an error here — "this account was created with
/// Google" is the correct answer to a reasonable question, and the
/// screen needs to act on it rather than just show it. So the code is
/// kept rather than flattened into a thrown exception.
class UnlinkResult {
  final bool success;
  final String message;

  /// Server code: `password_setup_required`, `weak_password`,
  /// `reauth_failed`, `not_linked`, `password_required`, `bad_password`,
  /// `password_set` on success, or null.
  final String? code;

  /// Providers still linked after the call. Empty on a refusal.
  final List<String> providers;

  const UnlinkResult({
    required this.success,
    required this.message,
    this.code,
    this.providers = const [],
  });

  /// This provider is currently the only way into the account, so a
  /// password has to be chosen before it can go.
  ///
  /// NOT a refusal to help and NOT a reason to delete anything — the
  /// account is kept either way. The screen collects a password and
  /// calls again.
  bool get needsPasswordFirst => code == 'password_setup_required';

  bool get wrongPassword => code == 'bad_password';
  bool get weakPassword => code == 'weak_password';
  bool get reauthFailed => code == 'reauth_failed';
}

class SocialApi {
  const SocialApi._();

  static final AuthService _auth = AuthService();

  static String get _base => '${AppEnvironment.wordpressBase}/wp-json/app/v2';

  /// Disconnects Apple or Google from the signed-in account.
  ///
  /// ── THE ACCOUNT IS NEVER DELETED BY THIS ─────────────────────────
  ///
  /// Two shapes, neither of which removes anything but the link:
  ///
  ///   * **Already has a password** — pass [password]. It confirms the
  ///     owner is present and proves a second way in exists, so the
  ///     unlink cannot strand anybody.
  ///   * **Provider is the only way in** — the first call comes back
  ///     [UnlinkResult.needsPasswordFirst]. Call again with
  ///     [newPassword] and a fresh [idToken] from the provider sheet;
  ///     the server sets the password, then unlinks, and the account
  ///     carries on.
  ///
  /// [idToken] is required for that second shape because there is no
  /// old password to ask for — without it, an unlocked phone could set
  /// a password and unlink, taking the account for good.
  ///
  /// Never throws for an expected refusal; network trouble comes back
  /// as an unsuccessful result too, so callers have one path.
  static Future<UnlinkResult> unlink({
    required String provider,
    String? password,
    String? newPassword,
    String? idToken,
    String? newEmail,
  }) async {
    try {
      final token = await _auth.getToken();

      if (token == null || token.isEmpty) {
        return const UnlinkResult(
          success: false,
          message: 'You need to sign in again before changing this.',
        );
      }

      final response = await http
          .post(
            Uri.parse('$_base/auth/social/unlink'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'provider': provider,
              if (password != null && password.isNotEmpty)
                'password': password,
              if (newPassword != null && newPassword.isNotEmpty)
                'new_password': newPassword,
              if (idToken != null && idToken.isNotEmpty) 'id_token': idToken,
              // Only sent when they actually changed it. The server
              // compares against the current address anyway, but not
              // sending it keeps "unchanged" unambiguous.
              if (newEmail != null && newEmail.isNotEmpty)
                'new_email': newEmail,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final body = json.decode(response.body);

      if (body is! Map) {
        return const UnlinkResult(
          success: false,
          message: 'Unexpected response from the server.',
        );
      }

      return UnlinkResult(
        success: body['success'] == true,
        message: (body['message'] ?? 'Could not disconnect.').toString(),
        code: body['code']?.toString(),
        providers: body['providers'] is List
            ? (body['providers'] as List).map((e) => e.toString()).toList()
            : const [],
      );
    } catch (e) {
      debugPrint('[SocialApi] unlink failed: $e');

      return const UnlinkResult(
        success: false,
        message: 'Could not reach the server. Check your connection.',
      );
    }
  }
}
