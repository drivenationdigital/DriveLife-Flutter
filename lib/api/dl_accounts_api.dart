import 'dart:convert';

import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the dashboard's event API (`dl-accounts/v1`).
///
/// This is the same endpoint the Next.js editor uses, called unchanged — it
/// returns the whole event including the sections the app's own `app/v2`
/// endpoint knows nothing about (discounts, show cars, car clubs, traders).
///
/// Two things differ from the rest of the app's API calls:
///
///  * **Events are addressed by an encrypted id**, not the numeric post id.
///    The server runs `make_crypt($eid, 'd')` and 400s on anything that does
///    not decrypt, so the app cannot simply pass the id it already holds — see
///    [fetchEventForEdit].
///  * **`site` is a region slug** — `uk` or `us` — not the `gb` country code
///    the app uses elsewhere. [siteForCountry] does that translation.
class DlAccountsAPI {
  DlAccountsAPI._();

  static final AuthService _authService = AuthService();

  static const String _base =
      'https://www.carevents.com/uk/wp-json/dl-accounts/v1';

  /// The app stores countries as `gb`/`us`; this API expects `uk`/`us`.
  static String siteForCountry(String? country) {
    final normalised = (country ?? 'gb').toLowerCase();
    return normalised == 'us' ? 'us' : 'uk';
  }

  /// Sends the one token under both header names.
  ///
  /// The two APIs read it differently: `app/v1` and `app/v2` verify
  /// `Authorization: Bearer`, while `dl-accounts` reads **`X-WP-Token`** and
  /// 401s with "X-WP-Token header is required" if it is missing. It is the
  /// same token either way — the dashboard does exactly this, for the same
  /// reason (see `lib/clubAdmins.ts`), so whichever verifier runs finds it and
  /// a call can cross between the two namespaces without knowing which is on
  /// the other end.
  static Map<String, String> authHeaders(String token) => {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
    'X-WP-Token': token,
  };

  /// Fetches an event in the shape the editor needs.
  ///
  /// [encryptedEventId] is the `eid` — the encrypted form. If you only have the
  /// numeric post id, this call cannot be made: the encryption is server-side
  /// with no app equivalent. Lists that feed the editor need to carry
  /// `encrypted_id` through for this to be reachable.
  ///
  /// Throws on failure, with the server's message where it gives one, so the
  /// caller can show something better than "something went wrong". Auth
  /// failures surface as-is rather than being swallowed.
  static Future<Map<String, dynamic>> fetchEventForEdit({
    required String encryptedEventId,
    String? country,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }

    final site = siteForCountry(country);
    final uri = Uri.parse(
      '$_base/event-edit'
      '?eid=${Uri.encodeQueryComponent(encryptedEventId)}'
      '&site=${Uri.encodeQueryComponent(site)}',
    );

    debugPrint('DlAccountsAPI.fetchEventForEdit → $uri');

    final response = await http.get(uri, headers: authHeaders(token));

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Unexpected response (${response.statusCode}) from event-edit',
      );
    }

    if (response.statusCode != 200) {
      // WP_Error serialises as {code, message, data:{status}}.
      final message = body['message']?.toString();
      throw Exception(
        message == null || message.isEmpty
            ? 'event-edit failed (${response.statusCode})'
            : message,
      );
    }

    return body;
  }
}
