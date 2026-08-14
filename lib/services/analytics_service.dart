import 'package:flutter/foundation.dart';
import 'package:flutter_piwikpro/flutter_piwikpro.dart';

/// Piwik PRO analytics for DriveLife.
///
/// Every method is a safe no-op when the tracker could not be configured or the
/// platform is unsupported (the plugin only ships Android and iOS), so callers
/// never need to guard their tracking calls.
class Analytics {
  Analytics._();

  static const String baseUrl = 'https://drivelife.piwik.pro';
  static const String siteId = 'bb5124e9-0358-4a58-808d-b97f548af309';

  static bool _ready = false;
  static bool get isReady => _ready;

  /// Echo every tracking call and the native SDK's reply to the console.
  ///
  /// The Piwik SDK uses Timber but never plants a tree, so it emits nothing to
  /// logcat on its own — these logs are the only visibility you get that a call
  /// reached the native tracker. On by default in debug builds.
  static bool debugLogging = kDebugMode;

  /// The plugin only ships Android and iOS implementations. Uses
  /// [defaultTargetPlatform] rather than `dart:io` so the web build still
  /// compiles.
  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static FlutterPiwikPro get _tracker => FlutterPiwikPro.sharedInstance;

  /// Configure the tracker. Call once from `main()` before `runApp`.
  static Future<void> initialize() async {
    if (_ready || !_supported) return;

    try {
      await _tracker.configureTracker(baseURL: baseUrl, siteId: siteId);
      _ready = true;
      debugPrint('✅ [Analytics] Piwik PRO tracker configured ($baseUrl)');

      // The native SDK only ever emits this once per install.
      await _tracker.trackAppInstall();
    } catch (e) {
      debugPrint('❌ [Analytics] Failed to configure tracker: $e');
    }
  }

  /// Track a screen view. [path] should look like a URL path, e.g. `/post-detail`.
  static Future<void> trackScreen(String path, {String? title}) =>
      _guard('trackScreen', () => _tracker.trackScreen(
            screenName: _sanitize(path),
            title: title,
          ));

  /// Track an interaction, e.g. `category: 'Post', action: 'like'`.
  static Future<void> trackEvent({
    required String category,
    required String action,
    String? name,
    double? value,
  }) =>
      _guard('trackEvent', () => _tracker.trackCustomEvent(
            category: category,
            action: action,
            name: name,
            value: value,
          ));

  static Future<void> trackSearch(
    String keyword, {
    String? category,
    int? numberOfHits,
  }) =>
      _guard('trackSearch', () => _tracker.trackSearch(
            keyword: keyword,
            category: category,
            numberOfHits: numberOfHits,
          ));

  static Future<void> trackShare({
    required String network,
    required String target,
  }) =>
      _guard('trackShare', () => _tracker.trackSocialInteraction(
            interaction: 'share',
            network: network,
            target: target,
          ));

  static Future<void> trackException(
    String description, {
    bool isFatal = false,
  }) =>
      _guard('trackException', () => _tracker.trackException(
            description: description,
            isFatal: isFatal,
          ));

  static Future<void> trackGoal(int goal, {double? revenue}) =>
      _guard('trackGoal', () => _tracker.trackGoal(goal: goal, revenue: revenue));

  /// Attach the logged-in user to the session. Call after login / profile load.
  static Future<void> setUserId(String id) =>
      _guard('setUserId', () => _tracker.setUserId(id));

  /// Detach the user on logout so the next visit is anonymous.
  static Future<void> clearUser() =>
      _guard('clearUser', () => _tracker.setUserId(null));

  /// Flush queued events immediately instead of waiting for the SDK's 30s
  /// dispatch timer. Useful when verifying tracking against the dashboard.
  ///
  /// Note: the plugin's `setDispatchInterval` is broken on Android — it calls
  /// `tracker.setSessionTimeout` instead — so this is the only reliable way to
  /// force a send.
  static Future<void> dispatch() => _guard('dispatch', () => _tracker.dispatch());

  /// Strips query strings so tokens carried by deep links (`?reset=`,
  /// `?verifyToken=`, `?qr=`) never reach the analytics backend.
  static String _sanitize(String path) {
    final cleaned = path.split('?').first.trim();
    if (cleaned.isEmpty) return '/';
    return cleaned.startsWith('/') ? cleaned : '/$cleaned';
  }

  static Future<void> _guard(String label, Future<String> Function() call) async {
    if (!_ready) {
      if (debugLogging) {
        debugPrint('⚠️ [Analytics] $label skipped — tracker not configured');
      }
      return;
    }

    try {
      final reply = await call();
      if (debugLogging) debugPrint('📊 [Analytics] $reply');
    } catch (e) {
      debugPrint('❌ [Analytics] $label failed: $e');
    }
  }
}
