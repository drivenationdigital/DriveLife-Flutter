import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_polyline.dart';

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
/// ── AND WHY THE ROUTE IS THE ROAD, NOT THE WAY TO IT ────────────────
///
/// The origin used to be left out, so the maps app started from
/// wherever the driver was and the road's own start became the first
/// WAYPOINT. That read well — "get to the beginning, then drive it" —
/// and it cost a waypoint slot, which is the one thing here in genuinely
/// short supply.
///
/// Google takes nine free waypoints plus a destination. Spending one of
/// them on the start means a road imported with ten points cannot be
/// sent at all, and every other road loses a point of the detail that
/// keeps the route pinned to the right tarmac.
///
/// So the origin IS the start now. The route is the road and nothing
/// else — no guess about where the driver is, no leg across a county
/// drawn over the top of it. Getting to the start is a different
/// question, and [startUrl] is the answer to it.
abstract final class RoadNavigation {
  const RoadNavigation._();

  /// The points to hand a maps app for [road].
  ///
  /// ── THE DRAWN POINTS, NOT THE DRAWN LINE ────────────────────────
  ///
  /// `polyline` is the snapped line: hundreds of points along the real
  /// tarmac. A URL holds eleven of them, so sending it means [sample]
  /// picking eleven evenly spaced ones — and an evenly spaced point is
  /// nowhere in particular. A road built from seven stops arrived in
  /// Google as eleven stops somewhere else, which is neither the road
  /// somebody drew nor anything that looks like it.
  ///
  /// `waypoints` ARE the road: the junctions somebody picked, which is
  /// what a maps app wants and how the route was built to begin with.
  /// Google joins them up the same way it did for them, and a route
  /// imported from a link comes back out identical to the link.
  ///
  /// The line is the fallback, for a road saved before waypoints were
  /// kept — see [DrivingRoad.waypoints]. Worse, and still the only
  /// thing those roads have.
  static List<RoadPoint> routeFor(DrivingRoad road) {
    final drawn = RoadPolyline.decode(road.waypoints);

    return drawn.length >= 2 ? drawn : RoadPolyline.decode(road.polyline);
  }

  /// How many coordinates the URL may carry, start and end included.
  ///
  /// Google Maps takes an origin, a destination and nine waypoints
  /// between them. Eleven in all — and all eleven are usable now that
  /// the origin is the road's own start rather than the driver's
  /// location.
  ///
  /// More would not help anyway: the points are there to pin the route
  /// to the right road, not to describe it.
  static const int maxStops = 11;

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

    final origin = stops.first;
    final destination = stops.last;
    final waypoints = stops.sublist(1, stops.length - 1);

    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&travelmode=driving'
      '&origin=${_coord(origin)}'
      '&destination=${_coord(destination)}'
      // Omitted entirely when there are none. An empty waypoints
      // parameter is not the same as no parameter, and Google reads
      // the empty one as a stop it cannot find.
      '${waypoints.isEmpty ? '' : '&waypoints=${waypoints.map(_coord).join('|')}'}',
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
  ///
  /// Mostly a fallback now. [routeFor] hands over the drawn waypoints
  /// where a road has them, and there are rarely eleven of those. This
  /// still runs for the roads saved before they were kept, and for the
  /// rare road drawn with more points than a URL holds.
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
