import 'package:shared_preferences/shared_preferences.dart';

/// How hard we compress media before uploading.
enum UploadQuality {
  /// Sensible default — small enough for mobile data, good enough for the feed.
  standard,

  /// For photographers: far more detail, at the cost of upload time and data.
  high,
}

/// The user's upload-quality preference.
///
/// Deliberately in [SharedPreferences] rather than the secure storage the theme
/// uses — it isn't sensitive, and it's read on a hot path when picking media.
class UploadQualityPrefs {
  UploadQualityPrefs._();

  static const String _key = 'upload_high_quality';

  /// Cached so picking media doesn't await disk for every image.
  static bool? _cached;

  static Future<bool> isHighQuality() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_key) ?? false;
    _cached = value;
    return value;
  }

  static Future<UploadQuality> current() async =>
      await isHighQuality() ? UploadQuality.high : UploadQuality.standard;

  static Future<void> setHighQuality(bool value) async {
    _cached = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
