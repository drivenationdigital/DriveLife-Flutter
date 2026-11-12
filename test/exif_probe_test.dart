import 'dart:typed_data';

import 'package:drivelife/utils/exif_probe.dart';
import 'package:flutter_test/flutter_test.dart';

/// The EXIF parser, which cannot be checked by looking at the app.
///
/// It decides whether a photo "has no location" or "was never checked",
/// and those two answers lead to opposite conclusions about whether the
/// venue-suggestion feature can work at all. A parser that quietly
/// returns nothing would make every camera roll look untagged.
void main() {
  group('probeExif on real-shaped files', () {
    test('a JPEG with GPS gives back the position', () {
      final probe = probeExif(_jpegWithGps());

      expect(probe.hasExif, isTrue);
      expect(probe.hasGpsTags, isTrue);
      expect(probe.gps, isNotNull);

      // 51 deg 30' 0" N, 0 deg 7' 30" W
      expect(probe.gps!.latitude, closeTo(51.5, 0.00001));
      expect(probe.gps!.longitude, closeTo(-0.125, 0.00001));
    });

    test('the camera maker comes through', () {
      final probe = probeExif(_jpegWithGps(make: 'Canon'));

      expect(probe.make, 'Canon');
    });

    test('big-endian files parse the same way', () {
      // Half the cameras in the world write "MM".
      final probe = probeExif(_jpegWithGps(little: false));

      expect(probe.gps, isNotNull);
      expect(probe.gps!.latitude, closeTo(51.5, 0.00001));
      expect(probe.gps!.longitude, closeTo(-0.125, 0.00001));
    });

    test('hemisphere refs flip the sign', () {
      final probe = probeExif(_jpegWithGps(latRef: 'S', lngRef: 'E'));

      expect(probe.gps!.latitude, closeTo(-51.5, 0.00001));
      expect(probe.gps!.longitude, closeTo(0.125, 0.00001));
    });

    test('EXIF with no GPS directory reads as tagless, not absent', () {
      // THE distinction this parser exists for: a real camera photo
      // taken with location off, which is not the same as a screenshot.
      final probe = probeExif(_jpegWithGps(includeGps: false, make: 'Apple'));

      expect(probe.hasExif, isTrue);
      expect(probe.hasGpsTags, isFalse);
      expect(probe.gps, isNull);
      expect(probe.make, 'Apple');
    });

    test('a zero fix is rejected but still counts as tagged', () {
      // Some cameras write the tags before they have a fix. 0,0 is in
      // the Atlantic, so it has to be refused rather than believed.
      final probe = probeExif(_jpegWithGps(lat: [0, 0, 0], lng: [0, 0, 0]));

      expect(probe.hasGpsTags, isTrue);
      expect(probe.gps, isNull);
    });

    test('an out-of-range latitude is refused', () {
      final probe = probeExif(_jpegWithGps(lat: [120, 0, 0]));

      expect(probe.hasGpsTags, isTrue);
      expect(probe.gps, isNull);
    });
  });

  group('probeExif on files it cannot use', () {
    test('a PNG screenshot has nothing to offer', () {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...List<int>.filled(64, 0),
      ]);

      expect(probeExif(png).hasExif, isFalse);
    });

    test('a JPEG with no EXIF segment', () {
      // SOI, then straight into a scan.
      final bare = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xDA, 0x00, 0x02,
        ...List<int>.filled(32, 0),
      ]);

      expect(probeExif(bare).hasExif, isFalse);
    });

    test('empty input', () {
      expect(probeExif(Uint8List(0)).hasExif, isFalse);
    });

    test('truncated mid-EXIF does not throw', () {
      final full = _jpegWithGps();

      // Every truncation point, because a short read is the normal way
      // this gets a partial file.
      for (var cut = 0; cut < full.length; cut++) {
        expect(
          () => probeExif(Uint8List.sublistView(full, 0, cut)),
          returnsNormally,
          reason: 'cut at $cut',
        );
      }
    });

    test('random bytes do not throw', () {
      // Fuzzing the segment walker: a corrupt length field used to be
      // how a parser walked off the end of a buffer.
      var seed = 7;
      int next() => seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;

      for (var attempt = 0; attempt < 200; attempt++) {
        final bytes = Uint8List.fromList([
          0xFF,
          0xD8,
          for (var i = 0; i < 96; i++) next() % 256,
        ]);

        expect(() => probeExif(bytes), returnsNormally);
      }
    });
  });
}

/// Builds a minimal but strictly valid EXIF JPEG.
///
/// Only the header is real — there is no image behind it, which the
/// parser neither needs nor looks at.
Uint8List _jpegWithGps({
  bool little = true,
  bool includeGps = true,
  String? make,
  String latRef = 'N',
  String lngRef = 'W',
  List<int> lat = const [51, 30, 0],
  List<int> lng = const [0, 7, 30],
}) {
  final tiff = <int>[];

  void u16(int v) => little
      ? tiff.addAll([v & 0xFF, (v >> 8) & 0xFF])
      : tiff.addAll([(v >> 8) & 0xFF, v & 0xFF]);

  void u32(int v) => little
      ? tiff.addAll([
          v & 0xFF,
          (v >> 8) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 24) & 0xFF,
        ])
      : tiff.addAll([
          (v >> 24) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 8) & 0xFF,
          v & 0xFF,
        ]);

  // ── TIFF header ────────────────────────────────────────────────────
  tiff.addAll(little ? [0x49, 0x49] : [0x4D, 0x4D]);
  u16(42);
  u32(8); // IFD0 begins immediately after

  final makeBytes = make == null
      ? const <int>[]
      : [...make.codeUnits, 0];

  // ── IFD0 ───────────────────────────────────────────────────────────
  final ifd0Entries = (includeGps ? 1 : 0) + (make == null ? 0 : 1);

  // IFD0 occupies 2 + 12n + 4 bytes starting at 8.
  final afterIfd0 = 8 + 2 + (12 * ifd0Entries) + 4;

  // Make's string, when it does not fit in the entry, goes first.
  final makeInline = makeBytes.length <= 4;
  final makeAt = afterIfd0;
  final gpsIfdAt = afterIfd0 + (makeInline ? 0 : makeBytes.length);

  u16(ifd0Entries);

  if (make != null) {
    u16(0x010F); // Make
    u16(2); // ASCII
    u32(makeBytes.length);
    if (makeInline) {
      tiff.addAll([
        ...makeBytes,
        ...List<int>.filled(4 - makeBytes.length, 0),
      ]);
    } else {
      u32(makeAt);
    }
  }

  if (includeGps) {
    u16(0x8825); // GPS IFD pointer
    u16(4); // LONG
    u32(1);
    u32(gpsIfdAt);
  }

  u32(0); // no IFD1

  if (!makeInline) tiff.addAll(makeBytes);

  // ── GPS IFD ────────────────────────────────────────────────────────
  if (includeGps) {
    // 4 entries: 2 + 48 + 4 = 54 bytes, then the two rational triples.
    final latAt = gpsIfdAt + 2 + (12 * 4) + 4;
    final lngAt = latAt + 24;

    u16(4);

    u16(0x0001); // GPSLatitudeRef
    u16(2);
    u32(2);
    tiff.addAll([latRef.codeUnitAt(0), 0, 0, 0]);

    u16(0x0002); // GPSLatitude
    u16(5); // RATIONAL
    u32(3);
    u32(latAt);

    u16(0x0003); // GPSLongitudeRef
    u16(2);
    u32(2);
    tiff.addAll([lngRef.codeUnitAt(0), 0, 0, 0]);

    u16(0x0004); // GPSLongitude
    u16(5);
    u32(3);
    u32(lngAt);

    u32(0); // end of directory

    for (final v in lat) {
      u32(v);
      u32(1);
    }
    for (final v in lng) {
      u32(v);
      u32(1);
    }
  }

  // ── Wrap in an APP1 segment ────────────────────────────────────────
  const exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  final segmentLength = 2 + exifHeader.length + tiff.length;

  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, // APP1
    (segmentLength >> 8) & 0xFF, segmentLength & 0xFF,
    ...exifHeader,
    ...tiff,
    0xFF, 0xD9, // EOI
  ]);
}
