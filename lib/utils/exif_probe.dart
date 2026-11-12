import 'dart:typed_data';

/// How much of a file to read when looking for its EXIF block.
///
/// EXIF lives in an APP1 segment near the start of a JPEG, so there is
/// no reason to pull a 12-megabyte photo off disk to read it. Generous
/// enough to clear a large embedded thumbnail, which some cameras put
/// in the same segment.
const int kExifProbeBytes = 256 * 1024;

/// A position read out of a file's own EXIF.
class ExifGps {
  final double latitude;
  final double longitude;

  const ExifGps(this.latitude, this.longitude);

  @override
  String toString() => 'ExifGps($latitude, $longitude)';
}

/// What a file's EXIF block turned out to contain.
///
/// ── WHY THE NEGATIVES ARE THE POINT ─────────────────────────────────
///
/// "No location" has several causes that look identical from outside,
/// and they call for different responses:
///
///   * no EXIF at all - a screenshot, a download, a PNG, or anything a
///     messaging app re-saved. Nothing to recover, ever.
///   * EXIF present, no GPS tags - a real camera photo taken with
///     location switched off. Also nothing to recover, but it proves
///     the pipeline is working.
///   * GPS tags present - recoverable, and if the gallery still said
///     null then something in the middle is dropping it.
///
/// Telling those apart is the difference between "this feature cannot
/// work" and "this feature is misconfigured".
class ExifProbe {
  /// An APP1 EXIF block was found and parsed.
  final bool hasExif;

  /// Camera maker, when the file names one. A strong hint that the file
  /// came off a camera rather than a screenshot.
  final String? make;

  /// A GPS sub-directory carried latitude AND longitude tags.
  final bool hasGpsTags;

  /// The decoded position, when the tags were readable and sane.
  final ExifGps? gps;

  const ExifProbe({
    required this.hasExif,
    this.make,
    this.hasGpsTags = false,
    this.gps,
  });

  /// Nothing found: not a JPEG, truncated, or carrying no EXIF.
  static const ExifProbe none = ExifProbe(hasExif: false);

  @override
  String toString() =>
      'ExifProbe(hasExif: $hasExif, make: $make, '
      'hasGpsTags: $hasGpsTags, gps: $gps)';
}

/// Reads what EXIF it can out of [bytes].
///
/// Total best effort: every malformed, truncated or simply unexpected
/// file returns [ExifProbe.none] rather than throwing. Camera rolls are
/// full of files that are nearly but not quite to spec.
ExifProbe probeExif(Uint8List bytes) {
  try {
    final tiff = _findExifApp1(bytes);
    if (tiff == null) return ExifProbe.none;

    return _parseTiff(bytes, tiff);
  } catch (_) {
    // Deliberately silent. A file that cannot be parsed is
    // indistinguishable from one with no EXIF, and both mean "no
    // location here".
    return ExifProbe.none;
  }
}

/// The offset of the TIFF header inside a JPEG's APP1 EXIF segment.
int? _findExifApp1(Uint8List b) {
  // SOI. Anything else is not a JPEG, which includes PNG screenshots
  // and HEIC, neither of which this parser handles.
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;

  var i = 2;

  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) {
      i++; // Resync rather than give up: padding happens.
      continue;
    }

    final marker = b[i + 1];

    // Fill bytes.
    if (marker == 0xFF) {
      i++;
      continue;
    }

    // Standalone markers, which carry no length field.
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }

    // Start of scan, or end of image: the metadata is all behind us.
    if (marker == 0xDA || marker == 0xD9) return null;

    final segmentLength = (b[i + 2] << 8) | b[i + 3];
    if (segmentLength < 2) return null;

    final dataStart = i + 4;

    if (marker == 0xE1 && dataStart + 6 <= b.length) {
      final isExif =
          b[dataStart] == 0x45 && // E
          b[dataStart + 1] == 0x78 && // x
          b[dataStart + 2] == 0x69 && // i
          b[dataStart + 3] == 0x66 && // f
          b[dataStart + 4] == 0x00 &&
          b[dataStart + 5] == 0x00;

      if (isExif) return dataStart + 6;
    }

    i = dataStart + segmentLength - 2;
  }

  return null;
}

/// EXIF tag numbers, which are the same in every file ever written.
const int _tagMake = 0x010F;
const int _tagGpsIfd = 0x8825;
const int _tagGpsLatRef = 0x0001;
const int _tagGpsLat = 0x0002;
const int _tagGpsLngRef = 0x0003;
const int _tagGpsLng = 0x0004;

const int _typeAscii = 2;
const int _typeLong = 4;
const int _typeRational = 5;

/// A directory is capped at a sane size: a corrupt count field is how a
/// parser ends up walking an entire file as though it were tag entries.
const int _maxEntries = 512;

ExifProbe _parseTiff(Uint8List b, int tiff) {
  if (tiff + 8 > b.length) return ExifProbe.none;

  final order = (b[tiff] << 8) | b[tiff + 1];
  final little = order == 0x4949; // "II"

  if (!little && order != 0x4D4D) return ExifProbe.none; // not "MM" either

  if (_u16(b, tiff + 2, little) != 42) return ExifProbe.none;

  final ifd0 = _u32(b, tiff + 4, little);
  if (ifd0 == null) return ExifProbe.none;

  String? make;
  int? gpsIfd;

  _walkIfd(b, tiff, tiff + ifd0, little, (tag, type, count, valueAt) {
    if (tag == _tagMake && type == _typeAscii) {
      make = _ascii(b, valueAt, count);
    } else if (tag == _tagGpsIfd && type == _typeLong) {
      gpsIfd = _u32(b, valueAt, little);
    }
  });

  final gpsOffset = gpsIfd;

  if (gpsOffset == null) {
    return ExifProbe(hasExif: true, make: make);
  }

  List<double>? lat;
  List<double>? lng;
  String? latRef;
  String? lngRef;

  _walkIfd(b, tiff, tiff + gpsOffset, little, (tag, type, count, valueAt) {
    switch (tag) {
      case _tagGpsLat:
        if (type == _typeRational) lat = _rationals(b, valueAt, count, little);
      case _tagGpsLng:
        if (type == _typeRational) lng = _rationals(b, valueAt, count, little);
      case _tagGpsLatRef:
        if (type == _typeAscii) latRef = _ascii(b, valueAt, count);
      case _tagGpsLngRef:
        if (type == _typeAscii) lngRef = _ascii(b, valueAt, count);
    }
  });

  final latValues = lat;
  final lngValues = lng;

  if (latValues == null || lngValues == null) {
    return ExifProbe(hasExif: true, make: make);
  }

  final latitude = _degrees(latValues, latRef, 90);
  final longitude = _degrees(lngValues, lngRef, 180);

  // Tags present but unusable still counts as HAVING tags: that is a
  // different story from a photo which never recorded a position.
  if (latitude == null || longitude == null) {
    return ExifProbe(hasExif: true, make: make, hasGpsTags: true);
  }

  // A camera that wrote the tags but never got a fix stores zeroes, and
  // the resulting position is in the Atlantic rather than merely a bit
  // off.
  if (latitude == 0 && longitude == 0) {
    return ExifProbe(hasExif: true, make: make, hasGpsTags: true);
  }

  return ExifProbe(
    hasExif: true,
    make: make,
    hasGpsTags: true,
    gps: ExifGps(latitude, longitude),
  );
}

/// Visits each entry of one IFD, handing over where its value lives.
///
/// A value of four bytes or fewer is stored IN the entry; anything
/// larger is stored elsewhere and the entry holds an offset, which is
/// measured from the TIFF header rather than from the file. Getting
/// that wrong is the classic way to read the wrong bytes entirely.
void _walkIfd(
  Uint8List b,
  int tiff,
  int ifd,
  bool little,
  void Function(int tag, int type, int count, int valueAt) onEntry,
) {
  if (ifd < 0 || ifd + 2 > b.length) return;

  final entries = _u16(b, ifd, little);
  if (entries == null || entries == 0 || entries > _maxEntries) return;

  for (var i = 0; i < entries; i++) {
    final at = ifd + 2 + (i * 12);
    if (at + 12 > b.length) return;

    final tag = _u16(b, at, little);
    final type = _u16(b, at + 2, little);
    final count = _u32(b, at + 4, little);

    if (tag == null || type == null || count == null) return;

    final size = _typeSize(type);
    if (size == 0) continue;

    // A count field large enough to overflow is corrupt, not ambitious.
    if (count > b.length) continue;

    final total = size * count;

    final int valueAt;
    if (total <= 4) {
      valueAt = at + 8;
    } else {
      final offset = _u32(b, at + 8, little);
      if (offset == null) continue;
      valueAt = tiff + offset;
    }

    if (valueAt < 0 || valueAt + total > b.length) continue;

    onEntry(tag, type, count, valueAt);
  }
}

int _typeSize(int type) {
  switch (type) {
    case 1: // BYTE
    case 2: // ASCII
    case 6: // SBYTE
    case 7: // UNDEFINED
      return 1;
    case 3: // SHORT
    case 8: // SSHORT
      return 2;
    case 4: // LONG
    case 9: // SLONG
    case 11: // FLOAT
      return 4;
    case 5: // RATIONAL
    case 10: // SRATIONAL
    case 12: // DOUBLE
      return 8;
    default:
      return 0;
  }
}

String? _ascii(Uint8List b, int at, int count) {
  if (at < 0 || at + count > b.length) return null;

  final out = StringBuffer();

  for (var i = 0; i < count; i++) {
    final c = b[at + i];
    if (c == 0) break; // NUL terminated, and the count includes the NUL
    if (c < 0x20 || c > 0x7E) continue; // junk, not text
    out.writeCharCode(c);
  }

  final text = out.toString().trim();
  return text.isEmpty ? null : text;
}

List<double>? _rationals(Uint8List b, int at, int count, bool little) {
  if (count == 0 || at + (count * 8) > b.length) return null;

  final out = <double>[];

  for (var i = 0; i < count; i++) {
    final numerator = _u32(b, at + (i * 8), little);
    final denominator = _u32(b, at + (i * 8) + 4, little);

    if (numerator == null || denominator == null) return null;

    // A zero denominator is how an unset tag is sometimes written.
    out.add(denominator == 0 ? 0 : numerator / denominator);
  }

  return out;
}

/// Degrees, minutes and seconds to a signed decimal degree.
double? _degrees(List<double> dms, String? ref, double limit) {
  if (dms.isEmpty) return null;

  final degrees = dms[0];
  final minutes = dms.length > 1 ? dms[1] : 0.0;
  final seconds = dms.length > 2 ? dms[2] : 0.0;

  var value = degrees + (minutes / 60) + (seconds / 3600);

  if (!value.isFinite) return null;

  final hemisphere = (ref ?? '').toUpperCase();
  if (hemisphere == 'S' || hemisphere == 'W') value = -value;

  // Out of range means misparsed, and a confidently wrong position is
  // worse than none at all.
  if (value.abs() > limit) return null;

  return value;
}

int? _u16(Uint8List b, int at, bool little) {
  if (at < 0 || at + 2 > b.length) return null;
  return little ? b[at] | (b[at + 1] << 8) : (b[at] << 8) | b[at + 1];
}

int? _u32(Uint8List b, int at, bool little) {
  if (at < 0 || at + 4 > b.length) return null;

  return little
      ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
      : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
}
