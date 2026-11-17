import 'dart:math' as math;

import 'package:drivelife/models/driving_road.dart';

/// The shape of a road, and what a camera has to do to see it.
///
/// ── WHY THE APP DECODES THESE AT ALL ────────────────────────────────
///
/// The server stores and sends an encoded polyline — the format Mapbox's
/// Directions and Map Matching APIs return — so nothing re-encodes what
/// came back from them and nothing can disagree about the shape.
///
/// But a GeoJSON LineString, which is how the map draws it, needs real
/// coordinates. So the string has to be opened here. This is the mirror
/// of dl_roads_polyline_decode() in endpoints/roads.php, and
/// php-api/tools/roads-test.php checks that one against the same worked
/// example this file's tests use — which is what keeps the two honest
/// about a format neither of them owns.
abstract final class RoadPolyline {
  const RoadPolyline._();

  /// An encoded polyline, as points.
  ///
  /// Precision 5, Google's algorithm. A truncated string gives back the
  /// points it COMPLETED rather than throwing: half a pair is not a
  /// point, and a latitude on its own would be a coordinate on the
  /// Greenwich meridian.
  static List<RoadPoint> decode(String encoded) {
    final points = <RoadPoint>[];

    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var deltas = <int>[];

      for (var axis = 0; axis < 2; axis++) {
        var shift = 0;
        var result = 0;
        int byte;

        do {
          if (index >= encoded.length) return points;

          byte = encoded.codeUnitAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (byte >= 0x20);

        // The low bit is the sign, and the rest is the magnitude shifted
        // up one. ~ rather than - because the encoder inverted all the
        // bits of a negative rather than negating it.
        deltas.add((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      }

      lat += deltas[0];
      lng += deltas[1];

      points.add(RoadPoint(_round5(lat * 1e-5), _round5(lng * 1e-5)));
    }

    return points;
  }

  /// Points, as an encoded polyline.
  static String encode(List<RoadPoint> points) {
    final out = StringBuffer();

    var prevLat = 0;
    var prevLng = 0;

    for (final point in points) {
      final lat = (point.lat * 1e5).round();
      final lng = (point.lng * 1e5).round();

      _chunk(out, lat - prevLat);
      _chunk(out, lng - prevLng);

      prevLat = lat;
      prevLng = lng;
    }

    return out.toString();
  }

  static void _chunk(StringBuffer out, int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);

    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }

    out.writeCharCode(v + 63);
  }

  /// Five decimal places, which is the precision the format carries.
  ///
  /// Without it the arithmetic leaves 53.2585 as 53.258500000000005, and
  /// a round trip through encode/decode stops comparing equal.
  static double _round5(double value) => (value * 100000).round() / 100000;

  /// GeoJSON wants [lng, lat]. Everything else here is [lat, lng].
  ///
  /// ── THE MOST REVERSIBLE MISTAKE IN MAPPING ──────────────────────
  ///
  /// Swapped, a road in Macclesfield draws somewhere in the Indian
  /// Ocean — and at UK latitudes the two numbers are a similar size, so
  /// nothing looks obviously wrong until the map is on screen. It is
  /// done in exactly one place for that reason.
  static List<List<double>> toGeoJson(List<RoadPoint> points) =>
      points.map((p) => [p.lng, p.lat]).toList();
}

/// The box a road fits inside.
class RoadBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const RoadBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  /// Null for an empty line — there is no box around nothing, and a box
  /// at 0,0 would send the camera to the Gulf of Guinea.
  static RoadBounds? of(List<RoadPoint> points) {
    if (points.isEmpty) return null;

    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;

    for (final point in points) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLng = math.min(minLng, point.lng);
      maxLng = math.max(maxLng, point.lng);
    }

    return RoadBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  RoadPoint get centre =>
      RoadPoint((minLat + maxLat) / 2, (minLng + maxLng) / 2);

  /// The zoom at which the whole road fits a viewport of this size.
  ///
  /// ── WHY THIS IS WORKED OUT HERE ─────────────────────────────────
  ///
  /// The SDK can fit a camera to a bounding box, but its signature has
  /// moved between plugin versions and it is an async platform call for
  /// something that is four lines of arithmetic. Done here it is
  /// synchronous, testable without a map, and cannot be broken by an
  /// SDK upgrade.
  ///
  /// Web Mercator: the world is 256 * 2^zoom pixels across, longitude
  /// maps linearly and latitude does not — which is why the two axes
  /// are measured differently and the tighter of the two wins.
  double zoomFor({
    required double widthPx,
    required double heightPx,
    double padding = 0.15,
  }) {
    const minZoom = 3.0;
    const maxZoom = 16.0;

    if (widthPx <= 0 || heightPx <= 0) return 12;

    final lngSpan = (maxLng - minLng).abs() / 360;
    final latSpan = (_mercator(maxLat) - _mercator(minLat)).abs();

    // A road shorter than the eye can see, or a single point. There is
    // no span to fit, so the answer is "as close as we go" rather than
    // the infinity the division would give.
    if (lngSpan <= 0 && latSpan <= 0) return maxZoom;

    final usable = 1 - padding.clamp(0.0, 0.8);

    final byLng = lngSpan > 0
        ? _log2((widthPx * usable) / (256 * lngSpan))
        : maxZoom;

    final byLat = latSpan > 0
        ? _log2((heightPx * usable) / (256 * latSpan))
        : maxZoom;

    // The tighter constraint wins: fitting one axis while the other
    // overflows is not fitting.
    return math.min(byLng, byLat).clamp(minZoom, maxZoom);
  }

  /// Latitude as a fraction of the Mercator world, 0 at the north edge
  /// and 1 at the south.
  static double _mercator(double lat) {
    // Mercator is infinite at the poles, so it is cut where every web
    // map cuts it.
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final radians = clamped * math.pi / 180;

    return (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
        2;
  }

  static double _log2(double value) =>
      value <= 0 ? 0 : math.log(value) / math.ln2;
}
