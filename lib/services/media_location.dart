import 'dart:io';

import 'package:drivelife/utils/exif_probe.dart';
import 'package:drivelife/utils/mp4_probe.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

/// Whether the OS will hand over the location tag on a photo.
enum MediaLocationAccess {
  /// Tags are readable.
  granted,

  /// Refused this time, and askable again.
  denied,

  /// Refused for good. Only app settings can change it.
  permanentlyDenied,

  /// No such permission on this platform or OS version.
  unavailable,
}

/// Why a photo produced no location.
///
/// ── WHY THIS IS AN ENUM AND NOT JUST NULL ───────────────────────────
///
/// These causes call for completely different responses, and they are
/// indistinguishable from the outside. [noExif] means the feature can
/// never work for that photo; [redacted] means the feature is
/// misconfigured and every reading is worthless. Reporting both as "no
/// location" is how you conclude that nobody's photos are tagged when
/// in fact a permission is missing.
enum MediaLocationMiss {
  /// A location was found.
  none,

  /// Permission was not granted, so the OS stripped the tag before we
  /// saw the file. Nothing can be concluded about this photo.
  redacted,

  /// No EXIF block at all: a screenshot, a download, a PNG, or
  /// something a messaging app re-saved.
  noExif,

  /// A real camera photo with no GPS tags, which means location was
  /// switched off when it was taken.
  noGpsTags,

  /// GPS tags present but unusable, including a camera that wrote them
  /// before it had a fix.
  unreadableGps,

  /// Videos are not probed. The gallery either knows or it does not.
  video,

  /// No file was available to probe.
  notProbed,
}

/// Where a photo says it was taken.
///
/// Read from the gallery, not from the uploaded file. By the time an
/// image has been through the crop and the compressor there is no EXIF
/// left to read, and Cloudflare Images strips metadata on ingest
/// anyway, so this has to be captured while the asset is still in hand.
@immutable
class MediaLocation {
  final double latitude;
  final double longitude;

  /// A readable place name, or null if there is not one.
  ///
  /// Only meaningful once [labelLoaded] is true: null before that means
  /// "still looking", and null after means "the geocoder had nothing".
  final String? label;

  /// Whether the reverse-geocode lookup has finished.
  ///
  /// Tracked separately so a lookup that legitimately finds nothing
  /// stops showing a spinner. Without it a failed lookup reads as
  /// permanently in progress.
  final bool labelLoaded;

  const MediaLocation({
    required this.latitude,
    required this.longitude,
    this.label,
    this.labelLoaded = false,
  });

  MediaLocation withLabel(String? value) => MediaLocation(
    latitude: latitude,
    longitude: longitude,
    label: value,
    labelLoaded: true,
  );

  /// Five decimal places is about a metre, which is as precise as this
  /// ever needs to be read aloud.
  String get coordinates =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  String toString() => 'MediaLocation($coordinates, $label)';
}

/// One photo's location, and the story behind it.
@immutable
class MediaLocationReading {
  final MediaLocation? location;

  /// True when the gallery gave nothing and the EXIF parser recovered
  /// it. Worth knowing: it means the platform path is unreliable here.
  final bool fromExif;

  final MediaLocationMiss miss;

  /// Camera maker, when the file names one.
  final String? cameraMake;

  const MediaLocationReading({
    this.location,
    this.fromExif = false,
    this.miss = MediaLocationMiss.none,
    this.cameraMake,
  });

  bool get hasLocation => location != null;

  MediaLocationReading withLocation(MediaLocation value) =>
      MediaLocationReading(
        location: value,
        fromExif: fromExif,
        miss: miss,
        cameraMake: cameraMake,
      );

  /// A sentence for a human, explaining a miss or qualifying a hit.
  String get explanation {
    switch (miss) {
      case MediaLocationMiss.none:
        return fromExif
            ? 'Read from the file (the gallery did not report it)'
            : 'From the gallery';
      case MediaLocationMiss.redacted:
        return 'Hidden by the system, permission not granted';
      case MediaLocationMiss.noExif:
        return 'No camera data at all (screenshot, download or re-save)';
      case MediaLocationMiss.noGpsTags:
        return cameraMake == null
            ? 'Camera photo, location was off'
            : '$cameraMake photo, location was off';
      case MediaLocationMiss.unreadableGps:
        return 'Location tags present but unusable';
      case MediaLocationMiss.video:
        return 'Video, and no position in the file either';
      case MediaLocationMiss.notProbed:
        return 'Could not be checked';
    }
  }
}

/// Pulls the location off a picked asset, and names the place.
///
/// ── TWO WAYS IN, BECAUSE THE FIRST ONE IS UNRELIABLE ────────────────
///
/// photo_manager's own read goes through MediaStore, and on Android it
/// is gated twice over: without ACCESS_MEDIA_LOCATION, the plugin
/// silently downgrades `isOrigin` to false AND `setRequireOriginal`
/// throws inside its own try/catch. The result is null, with no
/// indication that anything was refused.
///
/// So when that comes back empty this falls back to reading the file's
/// EXIF directly, which both recovers positions the platform path drops
/// and — more usefully — says WHY when there is genuinely nothing.
class MediaLocationService {
  const MediaLocationService._();

  /// Cached only once granted. A refusal is re-checked, because it can
  /// be changed in settings while the app is running.
  static MediaLocationAccess? _access;

  /// Keyed on coordinates rounded to ~11m, so a burst of photos from
  /// one place is one lookup rather than ten.
  static final Map<String, String?> _labels = <String, String?>{};

  /// The last known access state, without asking.
  static MediaLocationAccess get lastAccess =>
      _access ?? MediaLocationAccess.denied;

  /// Requests the permission needed to read location tags.
  ///
  /// Worth calling once before a batch. NOT a gate: [read] is safe
  /// either way and reports [MediaLocationMiss.redacted] when the tag
  /// was stripped, which is what stops a refusal being mistaken for a
  /// library of untagged photos.
  static Future<MediaLocationAccess> ensureAccess() async {
    if (_access == MediaLocationAccess.granted) return _access!;

    // iOS has no separate permission for this: access to the asset
    // carries access to its metadata.
    if (!Platform.isAndroid) {
      _access = MediaLocationAccess.granted;
      return _access!;
    }

    try {
      var status = await Permission.accessMediaLocation.status;

      if (!status.isGranted) {
        status = await Permission.accessMediaLocation.request();
      }

      if (status.isGranted) {
        _access = MediaLocationAccess.granted;
      } else if (status.isPermanentlyDenied) {
        _access = MediaLocationAccess.permanentlyDenied;
      } else if (status.isRestricted) {
        // Below API 29 the permission does not exist and nothing is
        // redacted, so there is nothing to grant.
        _access = MediaLocationAccess.unavailable;
      } else {
        _access = MediaLocationAccess.denied;
      }
    } catch (e) {
      debugPrint('[MediaLocation] permission request failed: $e');
      _access = MediaLocationAccess.unavailable;
    }

    debugPrint('[MediaLocation] access: $_access');

    return _access!;
  }

  /// Opens the OS settings page, for a permission refused for good.
  static Future<void> openSettings() => openAppSettings();

  /// Everything known about where [asset] was taken.
  ///
  /// [file] is the asset's file if one is already loaded, used for the
  /// EXIF fallback. Pass the ORIGINAL, before any crop: a cropped file
  /// is a freshly rendered bitmap with no EXIF at all, and probing it
  /// would report a camera photo as a screenshot.
  static Future<MediaLocationReading> read(
    AssetEntity asset, {
    File? file,
  }) async {
    final fromGallery = await _galleryLocation(asset);

    if (fromGallery != null) {
      return MediaLocationReading(location: fromGallery);
    }

    if (asset.type == AssetType.video) {
      // ── THE VIDEO FALLBACK ────────────────────────────────────────
      //
      // latlngAsync() reads MediaStore's LATITUDE and LONGITUDE, which
      // Android 10 removed — so it answers 0,0 for every video on a
      // modern phone, whatever the file holds. A photo survives that
      // through its EXIF; without this a video did not, and one shot at
      // an event reported no location while the phone's own gallery put
      // it on a map.
      //
      // Reads the file's own moov/udta/©xyz atom. See Mp4Probe.
      if (file != null) {
        final fromFile = await Mp4Probe.locationOf(file);

        if (fromFile != null) {
          return MediaLocationReading(
            location: MediaLocation(
              latitude: fromFile.latitude,
              longitude: fromFile.longitude,
            ),
            fromExif: true,
          );
        }

        // Nothing found, and every phone writes this somewhere slightly
        // different — so say what the file actually contains rather
        // than leaving it at "no location". Debug builds only.
        if (kDebugMode) {
          debugPrint(
            '[Mp4Probe] no position in ${file.path}. Atom tree:\n'
            '${await Mp4Probe.describe(file)}',
          );
        }
      }

      return const MediaLocationReading(miss: MediaLocationMiss.video);
    }

    if (file == null) {
      return const MediaLocationReading(miss: MediaLocationMiss.notProbed);
    }

    final probe = await _probeFile(file);

    if (probe.gps != null) {
      return MediaLocationReading(
        location: MediaLocation(
          latitude: probe.gps!.latitude,
          longitude: probe.gps!.longitude,
        ),
        fromExif: true,
        cameraMake: probe.make,
      );
    }

    // ── WHY THE PERMISSION CHECK COMES AFTER THE PROBE ───────────────
    //
    // Without ACCESS_MEDIA_LOCATION the OS strips GPS from the bytes we
    // are handed, so "no EXIF GPS" cannot be trusted to mean the photo
    // has none. Reporting the refusal instead is the honest answer, and
    // keeps a misconfiguration from being read as a finding.
    if (Platform.isAndroid && lastAccess != MediaLocationAccess.granted) {
      return MediaLocationReading(
        miss: MediaLocationMiss.redacted,
        cameraMake: probe.make,
      );
    }

    if (!probe.hasExif) {
      return const MediaLocationReading(miss: MediaLocationMiss.noExif);
    }

    return MediaLocationReading(
      miss: probe.hasGpsTags
          ? MediaLocationMiss.unreadableGps
          : MediaLocationMiss.noGpsTags,
      cameraMake: probe.make,
    );
  }

  /// photo_manager's own read.
  ///
  /// Always the async form. [AssetEntity.latitude] and `.longitude` are
  /// documented as ALWAYS NULL on Android 10 and above, where they come
  /// from a MediaStore column the OS stopped filling in; only this path
  /// falls back to reading EXIF.
  static Future<MediaLocation?> _galleryLocation(AssetEntity asset) async {
    try {
      final latLng = await asset.latlngAsync();

      if (latLng == null) return null;

      // photo_manager already rejects a 0,0 pair, which is what an
      // unset tag looks like rather than a position in the Atlantic.
      if (latLng.latitude == 0 && latLng.longitude == 0) return null;

      return MediaLocation(
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );
    } catch (e) {
      debugPrint('[MediaLocation] gallery read failed for ${asset.id}: $e');
      return null;
    }
  }

  /// Reads just enough of a file to find its EXIF block.
  static Future<ExifProbe> _probeFile(File file) async {
    RandomAccessFile? handle;

    try {
      handle = await file.open();

      final length = await handle.length();
      if (length <= 0) return ExifProbe.none;

      final take = length < kExifProbeBytes ? length : kExifProbeBytes;
      final bytes = await handle.read(take);

      return probeExif(Uint8List.fromList(bytes));
    } catch (e) {
      debugPrint('[MediaLocation] exif probe failed for ${file.path}: $e');
      return ExifProbe.none;
    } finally {
      try {
        await handle?.close();
      } catch (_) {
        // Nothing useful to do with a failed close.
      }
    }
  }

  /// A readable name for a position, or null if there is not one.
  ///
  /// Reverse geocoding goes out to the platform, so this is slow enough
  /// to want off the path that builds a frame, and flaky enough that a
  /// failure must not matter.
  static Future<String?> describe(MediaLocation location) async {
    final key =
        '${location.latitude.toStringAsFixed(4)},'
        '${location.longitude.toStringAsFixed(4)}';

    if (_labels.containsKey(key)) return _labels[key];

    try {
      // Bounded, because the platform geocoder can simply never answer.
      //
      // On Android it is a Play Services call; with no network, no Play
      // Services, or a throttled quota it returns nothing and does not
      // say so. An unbounded await then leaves the label reading
      // "Finding place…" for the rest of the session, which looks like
      // the location was never read at all — when in fact the
      // coordinates were read perfectly and only the NAME is missing.
      final places = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 8));

      if (places.isEmpty) {
        _labels[key] = null;
        return null;
      }

      final label = formatPlacemark(places.first);
      _labels[key] = label;
      return label;
    } catch (e) {
      debugPrint('[MediaLocation] geocode failed for $key: $e');
      // NOT cached: this is usually no network, and the next attempt
      // may well succeed.
      return null;
    }
  }

  /// Builds a readable place from a [Placemark].
  ///
  /// ── WHY NOT JUST USE `name` ──────────────────────────────────────
  ///
  /// On Android `name` is `Address.getFeatureName()`, which is whatever
  /// the geocoder happened to key on. For a street address that is the
  /// HOUSE NUMBER, so taking it first produced labels like
  /// "57, Soho, London" — which looks like a bug and tells you nothing.
  /// It can also be a Plus Code, which is worse: it looks like data.
  ///
  /// So `name` is used only when it reads like an actual place name,
  /// and the street name is preferred over the number either way.
  ///
  /// Exposed for testing.
  static String? formatPlacemark(Placemark place) {
    final candidates = <String?>[
      if (_isPlaceName(place.name, place)) place.name,
      place.thoroughfare,
      place.subLocality,
      place.locality,
      place.administrativeArea,
      place.country,
    ];

    final parts = <String>[];
    final seen = <String>{};

    for (final candidate in candidates) {
      final value = (candidate ?? '').trim();
      if (value.isEmpty) continue;

      // A placemark repeats itself across fields constantly, and
      // "Soho, Soho, London" reads like a bug.
      if (!seen.add(value.toLowerCase())) continue;

      parts.add(value);

      // Three components is a place; more is an address, which is more
      // than anybody asked to have shown next to their photo.
      if (parts.length == 3) break;
    }

    if (parts.isEmpty) return null;

    return parts.join(', ');
  }

  /// Whether a `name` field is a place name rather than a number.
  static bool _isPlaceName(String? name, Placemark place) {
    final value = (name ?? '').trim();

    if (value.length < 3) return false;

    // A house number, with or without a letter suffix.
    if (RegExp(r'^\d+[A-Za-z]?$').hasMatch(value)) return false;

    // The street number field repeated.
    if (value == (place.subThoroughfare ?? '').trim()) return false;

    // A Plus Code, e.g. "9C3XGW4C+9F". Technically a location, but
    // meaningless to read.
    if (RegExp(r'^[0-9A-Z]{4,8}\+[0-9A-Z]{2,3}$').hasMatch(value)) {
      return false;
    }

    // A postcode: mostly digits, and short.
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits > 0 && digits >= value.replaceAll(' ', '').length - 2) {
      return false;
    }

    // Must contain a letter to be a name at all.
    return RegExp(r'[A-Za-z]').hasMatch(value);
  }
}
