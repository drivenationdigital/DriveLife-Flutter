import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// The Mapbox account the Discover map draws through.
///
/// The token is supplied at build time rather than committed:
///
///   flutter run --dart-define=MAPBOX_TOKEN=pk.xxxxx
///
/// A Mapbox *public* token (`pk.`) is all that is needed. Mapbox used to also
/// require a secret `sk.` download token in `android/gradle.properties` and a
/// `~/.netrc` entry to fetch the native SDKs; as of the v3 plugin the Android
/// artefacts come from an unauthenticated Maven repo and iOS pulls MapboxMaps
/// from public CocoaPods, so there is nothing to configure on the build
/// machines.
///
/// Public tokens are not secrets in the usual sense — every Mapbox web map
/// ships one in its page source, and they are restricted by URL/scope rather
/// than by being hidden. It is kept out of the repo anyway so that rotating it
/// does not need a code change, and so a leaked repo does not hand over the
/// billing account.
abstract final class MapboxConfig {
  const MapboxConfig._();

  static const String accessToken = String.fromEnvironment('MAPBOX_TOKEN');

  /// Whether this build can draw a map at all.
  ///
  /// Checked rather than assumed because the failure is otherwise silent: with
  /// no token the SDK renders an empty grey rectangle and logs nothing useful,
  /// which looks like a broken screen rather than a missing build argument.
  static bool get isConfigured => accessToken.startsWith('pk.');

  /// Mapbox's own light style. Standard is the 3D-capable default and renders
  /// closest to the mock: muted land, clear road hierarchy, no competing POI
  /// colour to fight the pins for attention.
  static const String styleUri = MapboxStyles.STANDARD;

  static bool _applied = false;

  /// Hands the token to the SDK, once.
  ///
  /// Called from the map screen rather than `main()` so that a build with no
  /// token still starts normally and only the Discover tab is affected. The
  /// SDK keeps this globally, so calling it twice is harmless but pointless.
  static void ensureInitialised() {
    if (_applied || !isConfigured) return;
    MapboxOptions.setAccessToken(accessToken);
    _applied = true;
  }
}
