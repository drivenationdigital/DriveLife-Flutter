import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Somewhere an admin can pretend to be.
class TestRegion {
  final String key;
  final String label;

  /// 'GB' or 'US' — which catalogue this switches to.
  final String site;

  const TestRegion({
    required this.key,
    required this.label,
    required this.site,
  });

  factory TestRegion.fromJson(Map<String, dynamic> json) {
    return TestRegion(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      site: (json['site'] ?? '').toString(),
    );
  }
}

/// What the server will tell us about pretending.
class TestLocationState {
  /// Whether this account may do it at all. False for everyone who is not
  /// an administrator, and the tile draws nothing.
  final bool available;

  /// The region key in force, or null for "use my real location".
  final String? current;
  final String? currentLabel;

  final List<TestRegion> regions;

  const TestLocationState({
    this.available = false,
    this.current,
    this.currentLabel,
    this.regions = const [],
  });
}

/// Pretending to be in another country, for testing.
///
/// Almost everything regional — which blog the events, venues, tracks and
/// clubs come from, and the point every radius is measured from — is resolved
/// from the signed-in user's stored location. There was no way to see what an
/// American user sees from a desk in Britain, which is how the US catalogue
/// came to be a narrow strip through Colorado without anybody noticing.
///
/// Administrators only, enforced on the server. The app does not check:
/// [TestLocationState.available] is the server's answer, so losing admin
/// rights takes the option away without a new build.
class TestLocationApi {
  static final AuthService _authService = AuthService();

  static Future<Map<String, String>> _headers() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = await _authService.getToken();

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  static Uri _uri() =>
      Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/test-location');

  /// Where we are pretending to be, and the choices.
  ///
  /// Returns a state with `available: false` on any failure, which is also
  /// what a non-admin gets — in both cases the right thing is to draw
  /// nothing, so they do not need telling apart.
  static Future<TestLocationState> fetch() async {
    try {
      final response = await http.get(_uri(), headers: await _headers());

      if (response.statusCode != 200) {
        return const TestLocationState();
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) {
        return const TestLocationState();
      }

      return TestLocationState(
        available: body['available'] == true,
        current: body['current']?.toString(),
        currentLabel: body['current_label']?.toString(),
        regions: (body['regions'] as List? ?? [])
            .whereType<Map>()
            .map((raw) => TestRegion.fromJson(Map<String, dynamic>.from(raw)))
            .toList(),
      );
    } catch (error) {
      debugPrint('TestLocationApi.fetch failed: $error');

      return const TestLocationState();
    }
  }

  /// Pretend to be in [regionKey], or pass null to go back to the real
  /// location. Returns true when the server accepted it.
  static Future<bool> set(String? regionKey) async {
    try {
      final response = await http.post(
        _uri(),
        headers: await _headers(),
        body: jsonEncode(
          regionKey == null ? {'clear': true} : {'region': regionKey},
        ),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'TestLocationApi.set: ${response.statusCode} ${response.body}',
        );

        return false;
      }

      final body = jsonDecode(response.body);

      return body is Map && body['success'] == true;
    } catch (error) {
      debugPrint('TestLocationApi.set failed: $error');

      return false;
    }
  }
}
