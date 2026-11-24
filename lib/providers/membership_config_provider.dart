import 'dart:async';
import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/models/membership_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The membership copy and the advert switch, kept current.
///
/// ── THREE SOURCES, IN THIS ORDER ────────────────────────────────────
///
///   1. the server, fetched on launch
///   2. the last server answer, cached on this device
///   3. what is compiled into the build
///
/// It starts at (3) so the paywall is drawable on the very first frame
/// with no await anywhere, moves to (2) the moment preferences are
/// read, and to (1) when the network answers. Nothing ever waits, and
/// nothing is ever blank.
///
/// ── WHY IT IS CACHED AND NOT JUST FETCHED ───────────────────────────
///
/// So a change survives being offline. Somebody who opens the app on a
/// train after the advert switch was flipped should get the new
/// behaviour, not the behaviour from whenever the build was made. The
/// cache is also what stops a launch-time fetch from being a
/// launch-time blocker.
class MembershipConfigProvider extends ChangeNotifier {
  static const String _cacheKey = 'membership_config_v1';

  /// Short, because this is a kill switch as much as a copy deck. An
  /// hour is long enough to be free and short enough that turning
  /// adverts off reaches people the same morning.
  static const Duration freshFor = Duration(hours: 1);

  MembershipConfig _config = MembershipConfig.bundled;
  DateTime? _fetchedAt;
  bool _loading = false;

  MembershipConfig get config => _config;

  /// Where the current values came from, for the demo screen to show.
  String source = 'bundled';

  /// Reads the cache, then refreshes from the network.
  ///
  /// Never throws and never blocks. Call it from startup and forget
  /// it — every failure leaves the app on the previous answer.
  Future<void> load() async {
    await _fromCache();

    unawaited(refresh());
  }

  Future<void> _fromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);

      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);

      if (decoded is! Map) return;

      _apply(
        MembershipConfig.fromMap(Map<String, dynamic>.from(decoded)),
        'cache',
      );
    } catch (e) {
      // A corrupt cache is not worth a crash, and the bundled config
      // is already in place.
      debugPrint('[MembershipConfig] cache unreadable: $e');
    }
  }

  /// Asks the server. Keeps whatever it has on any failure.
  Future<void> refresh({bool force = false}) async {
    if (_loading) return;

    if (!force && _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < freshFor) {
      return;
    }

    _loading = true;

    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppEnvironment.wordpressBase}'
              '/wp-json/app/v2/membership-config',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[MembershipConfig] ${response.statusCode}');

        return;
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) return;

      final map = Map<String, dynamic>.from(body);

      _apply(MembershipConfig.fromMap(map), 'server');
      _fetchedAt = DateTime.now();

      // Cached as RECEIVED rather than as parsed, so a later build
      // that understands more of the payload gets the whole thing
      // rather than what this build could make of it.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(map));
    } catch (e) {
      debugPrint('[MembershipConfig] refresh failed: $e');
    } finally {
      _loading = false;
    }
  }

  void _apply(MembershipConfig next, String from) {
    _config = next;
    source = from;

    notifyListeners();
  }

  /// The demo switch. Lets the advert toggle be tried without the
  /// server, and asserts rather than working in release.
  void debugSetAds({required bool enabled}) {
    assert(!kReleaseMode, 'debugSetAds must never run in release.');

    _apply(
      MembershipConfig(
        version: _config.version,
        ads: AdConfig(
          enabled: enabled,
          firstAfter: _config.ads.firstAfter,
          every: _config.ads.every,
        ),
        tiers: _config.tiers,
      ),
      'demo',
    );
  }
}
