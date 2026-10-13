import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// The Mapbox account the Discover map draws through.
///
/// **The token lives in one file: `assets/config/mapbox.json`.**
///
/// ```json
/// { "accessToken": "pk.xxxxx" }
/// ```
///
/// That file is gitignored. `assets/config/mapbox.example.json` is committed
/// beside it so the shape is discoverable, and so the asset directory exists
/// even on a fresh clone — pubspec declares the directory rather than the
/// file, because naming a missing file there fails the build.
///
/// Changing the token is editing that one file. No build arguments, no
/// launch-configuration entries, nothing to remember at release time.
///
/// Read at runtime rather than compiled in with `--dart-define`, which is the
/// whole point: a dart-define is a compile-time constant and has to be passed
/// on every single build command, so forgetting it on the one release build
/// that matters ships a blank map.
///
/// Mapbox *public* tokens (`pk.`) are not secrets in the usual sense — every
/// Mapbox web map ships one in its page source, and they are restricted by
/// URL and scope rather than by being hidden. Bundling one in the app is how
/// Mapbox expects it to be done, and a `--dart-define` would be equally
/// readable in the binary. It is kept out of the repo anyway so that rotating
/// it needs no code change, and so a leaked repo does not hand over the
/// billing account.
///
/// A *secret* token (`sk.`) must never go here. None is needed: the v3 plugin
/// fetches the Android SDK from an unauthenticated Maven repo and iOS takes
/// MapboxMaps from public CocoaPods.
abstract final class MapboxConfig {
  const MapboxConfig._();

  static const String _assetPath = 'assets/config/mapbox.json';

  /// An override for build machines that should not hold the file, such as
  /// CI. Ignored unless [_assetPath] is missing or unusable, so the file
  /// stays the one place to look.
  static const String _fromBuildArgs = String.fromEnvironment('MAPBOX_TOKEN');

  static String _token = '';
  static bool _loaded = false;

  /// Whether this build can draw a map at all.
  ///
  /// Checked rather than assumed because the failure is otherwise silent:
  /// with no token the SDK renders an empty grey rectangle and logs nothing
  /// useful, which looks like a broken screen rather than missing config.
  static bool get isConfigured => _token.startsWith('pk.');

  /// Whether [load] has run, whatever it found.
  static bool get isLoaded => _loaded;

  /// Mapbox's own light style. Standard is the 3D-capable default and renders
  /// closest to the design: muted land, clear road hierarchy, no competing
  /// POI colour to fight the pins for attention.
  static const String styleUri = MapboxStyles.STANDARD;

  /// Reads the token and hands it to the SDK.
  ///
  /// Called once from `main()`, before `runApp`, so the map is ready the
  /// instant Discover is opened rather than flashing a placeholder while an
  /// asset read completes.
  ///
  /// Never throws. A missing or malformed file leaves the app working and
  /// Discover showing its "map unavailable" screen, which says what to fix —
  /// far better than taking down launch for a feature the user may not open.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    _token = await _fromAsset() ?? _fromBuildArgs.trim();

    if (isConfigured) {
      MapboxOptions.setAccessToken(_token);
    } else {
      debugPrint(
        '[mapbox] No usable access token. Put one in $_assetPath as '
        '{"accessToken": "pk...."} — see assets/config/mapbox.example.json.',
      );
    }
  }

  static Future<String?> _fromAsset() async {
    try {
      return parseToken(await rootBundle.loadString(_assetPath));
    } catch (_) {
      // Absent on a fresh clone. Nothing to use, and the caller falls back.
      return null;
    }
  }

  /// The token in a mapbox.json, or null if there isn't a usable one.
  ///
  /// Separate from the asset read so it can be tested without an asset
  /// bundle, and because every way this can go wrong is a content problem
  /// rather than an IO one.
  @visibleForTesting
  static String? parseToken(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final token = '${decoded['accessToken'] ?? ''}'.trim();

    // A public token, and not the committed placeholder.
    //
    // The placeholder check matters: on a fresh clone the example file is the
    // only thing in the directory, and it starts with 'pk.' like a real one.
    // Accepting it would start the SDK with a token Mapbox rejects, which
    // renders a blank grey map — harder to diagnose than no token at all.
    //
    // An 'sk.' secret token is refused too. It is not needed by this plugin,
    // it would be readable by anyone with the APK, and it carries account
    // scopes a map has no business holding.
    if (!token.startsWith('pk.') || token.contains('replace_this')) {
      return null;
    }
    return token;
  }

  /// Lets a test supply a token without an asset bundle.
  @visibleForTesting
  static void debugSetToken(String? token) {
    _token = token ?? '';
    _loaded = token != null;
  }
}
