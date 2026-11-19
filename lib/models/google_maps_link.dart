import 'package:drivelife/models/driving_road.dart';

/// Pulling a route out of a Google Maps link.
///
/// ── WHY IMPORTING BEATS DRAWING ─────────────────────────────────────
///
/// Somebody who already has the road has already done this work. They
/// planned it in Google Maps, they have the link, and asking them to
/// tap it out again on a phone-sized map is asking them to do it worse
/// — a finger is less precise than the thing that produced the link.
///
/// ── WHAT A MAPS LINK ACTUALLY LOOKS LIKE ────────────────────────────
///
/// Three shapes, and they share almost nothing:
///
///   1. The documented one, which the Share button produces:
///      /maps/dir/?api=1&origin=53.2,-2.0&destination=53.3,-1.9
///        &waypoints=53.25,-1.95|53.28,-1.92
///
///   2. The one the browser URL bar shows, where the stops are PATH
///      segments and may be place names rather than coordinates:
///      /maps/dir/53.2,-2.0/Buxton/53.3,-1.9/@53.25,-1.95,11z/data=...
///
///   3. A short link, maps.app.goo.gl/XXXX, which contains nothing at
///      all until it has been followed. See [looksShortened] — resolving
///      it needs the network and so belongs to the caller.
///
/// ── THE ONE THAT BITES ──────────────────────────────────────────────
///
/// `@53.25,-1.95,11z` in shape 2 is the CAMERA — where the map was
/// looking when the link was made. It is a coordinate, it sits among
/// the stops, and it is not a stop. Taken as one it drops a waypoint in
/// the middle of the route at whatever the map happened to be centred
/// on, which on a long road is miles off it.
abstract final class GoogleMapsLink {
  const GoogleMapsLink._();

  /// Whether this looks like a Google Maps URL at all.
  static bool looksLikeMaps(String url) {
    final text = url.trim().toLowerCase();

    return text.contains('google.') && text.contains('/maps') ||
        text.contains('maps.app.goo.gl') ||
        text.contains('goo.gl/maps');
  }

  /// Whether it has to be followed before anything can be read from it.
  ///
  /// A short link is an identifier and nothing else. The caller resolves
  /// it — that needs the network, and a parser that reaches for the
  /// network cannot be tested without one.
  static bool looksShortened(String url) {
    final text = url.trim().toLowerCase();

    return text.contains('maps.app.goo.gl') || text.contains('goo.gl/maps');
  }

  /// The stops in this link, in order, or an empty list.
  ///
  /// Place names are skipped rather than guessed at: "Buxton" is a town
  /// and a road does not start in the middle of one. What comes back is
  /// the coordinates the link actually carried.
  static List<RoadPoint> pointsFrom(String url) {
    final text = url.trim();

    if (text.isEmpty) return const [];

    final Uri uri;

    try {
      uri = Uri.parse(text);
    } catch (_) {
      return const [];
    }

    // ── Shape 1: the documented parameters ──────────────────────────
    //
    // Taken first and taken alone. When a link carries these it carries
    // the whole route in them, and the path is decoration.
    final params = uri.queryParameters;

    final origin = _point(params['origin']);
    final destination = _point(params['destination']);
    final middle = (params['waypoints'] ?? '')
        .split(RegExp(r'[|]'))
        .map(_point)
        .whereType<RoadPoint>()
        .toList();

    if (origin != null || destination != null || middle.isNotEmpty) {
      return [
        if (origin != null) origin,
        ...middle,
        if (destination != null) destination,
      ];
    }

    // ── Shape 2: coordinates in the path ────────────────────────────
    final out = <RoadPoint>[];

    for (final raw in uri.pathSegments) {
      final segment = Uri.decodeComponent(raw);

      // THE CAMERA, NOT A STOP. See the note at the top of the file.
      if (segment.startsWith('@')) continue;

      // Everything from `data=` on is Google's own encoding of the
      // route and is full of numbers that are not coordinates.
      if (segment.startsWith('data=')) break;

      final point = _point(segment);

      if (point != null) out.add(point);
    }

    return out;
  }

  /// "53.2585,-2.0074" as a point, or null for anything else.
  ///
  /// Deliberately strict. A place name, a plus code, an empty segment
  /// and a Google data blob all arrive here, and the only safe answer
  /// for every one of them is no.
  static RoadPoint? _point(String? raw) {
    final text = (raw ?? '').trim();

    if (text.isEmpty) return null;

    // Exactly two numbers separated by one comma. Anything else is not
    // a coordinate pair, whatever else it may be.
    final match = RegExp(
      r'^(-?\d{1,3}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)$',
    ).firstMatch(text);

    if (match == null) return null;

    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);

    if (lat == null || lng == null) return null;

    final point = RoadPoint(lat, lng);

    // isReal refuses 0,0 and anything past the poles. A link can carry
    // either, and neither is a road.
    return point.isReal && lat.abs() <= 90 && lng.abs() <= 180 ? point : null;
  }
}
