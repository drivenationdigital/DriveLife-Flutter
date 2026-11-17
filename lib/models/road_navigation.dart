import 'package:drivelife/models/driving_road.dart';

/// Handing a road to the thing that actually gives directions.
///
/// ── WHY THIS IS A HANDOFF AND NOT A FEATURE ─────────────────────────
///
/// Turn-by-turn navigation is a product, not a screen. It needs live
/// traffic, rerouting, lane guidance, speech, offline tiles and a
/// phone mount — and the person driving already has an app that does
/// all of it, with their settings, their voice and their history.
///
/// So this builds a URL and gets out of the way.
///
/// ── AND WHY THE ORIGIN IS LEFT OUT ──────────────────────────────────
///
/// Omitting it makes the maps app start from wherever the driver is,
/// which is right both times it matters: planning at home on Friday,
/// and standing next to the car on Sunday. A stored origin would be
/// wrong on at least one of those.
///
/// The road's own start then becomes the first WAYPOINT, so the route
/// is "get to the beginning, then drive the road" rather than "get to
/// the end" — which would happily send somebody down the motorway that
/// bypasses the whole thing.
abstract final class RoadNavigation {
  const RoadNavigation._();

  /// How many coordinates the URL may carry, start and end included.
  ///
  /// Google Maps takes nine free waypoints plus a destination. Ten is
  /// comfortably inside that, and more would not help anyway: the
  /// points are there to pin the route to the right road, not to
  /// describe it.
  static const int maxStops = 10;

  /// A directions URL for driving this road, or null if there is no
  /// road to drive.
  ///
  /// Universal link rather than a scheme: it opens the Google Maps app
  /// where there is one and the website where there is not, which
  /// covers both platforms and a desktop browser without asking which
  /// it is talking to.
  static Uri? directionsUrl(List<RoadPoint> points) {
    final stops = sample(points, maxStops);

    if (stops.length < 2) return null;

    final destination = stops.last;
    final waypoints = stops.sublist(0, stops.length - 1);

    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&travelmode=driving'
      '&destination=${_coord(destination)}'
      '&waypoints=${waypoints.map(_coord).join('|')}',
    );
  }

  /// Just the start, for getting there in the first place.
  static Uri? startUrl(List<RoadPoint> points) {
    if (points.isEmpty) return null;

    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&travelmode=driving'
      '&destination=${_coord(points.first)}',
    );
  }

  /// At most [count] points, evenly spaced, always including both ends.
  ///
  /// A snapped road is hundreds of points and a URL cannot carry them.
  /// Spacing them evenly keeps the route pinned along the whole road
  /// rather than clustered at one end, which is what taking the first
  /// nine would do — and a route pinned only at the start is free to
  /// rejoin the main road for the rest of it.
  static List<RoadPoint> sample(List<RoadPoint> points, int count) {
    final usable = points.where((p) => p.isReal).toList();

    if (usable.length <= count) return usable;
    if (count < 2) return usable.isEmpty ? const [] : [usable.first];

    final out = <RoadPoint>[];
    final step = (usable.length - 1) / (count - 1);

    for (var i = 0; i < count; i++) {
      // Rounded, so the last index lands exactly on the last point
      // rather than one short of it.
      out.add(usable[(i * step).round()]);
    }

    return out;
  }

  /// "53.258500,-2.007400".
  ///
  /// Latitude first — the opposite order to GeoJSON, and the order
  /// every maps URL on earth uses. Six decimal places is about a tenth
  /// of a metre, which is more than enough to name a road and short
  /// enough to keep ten of them in a URL.
  static String _coord(RoadPoint point) =>
      '${point.lat.toStringAsFixed(6)},${point.lng.toStringAsFixed(6)}';
}
