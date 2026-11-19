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
///
/// ── THE ONE THAT BIT ────────────────────────────────────────────────
///
/// In shape 2 a stop is written as a NAME whenever it was picked from
/// search rather than dropped as a pin. Real routes are planned exactly
/// that way at the ends — you start at a car park and finish at one —
/// and so a seven-stop route arrives as
///
///     /dir/Helmsley Market Place Parking/54.4,-0.9/…/Eastgate Car Park/
///
/// where only the five in the middle are numbers. Reading the path
/// alone returns those five: a road beginning and ending two stops
/// short of where it was drawn, with nothing to say anything was lost.
///
/// Google's own `data=` blob has those coordinates, and ONLY those.
/// See [_fromData]. It is read to fill the gaps the path leaves.
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
  static List<RoadPoint> pointsFrom(String url) => read(url).points;

  /// What a link describes: the stops that could be PLACED, and how
  /// many it listed in all.
  ///
  /// ── WHY THE COUNT COMES BACK TOO ────────────────────────────────
  ///
  /// Because the two differ, and when they do something was lost. A
  /// stop written as a name and left unplaced simply does not appear
  /// in [points], and a caller holding only that list cannot tell five
  /// stops from seven with two dropped. That is how a route came back
  /// missing both of its ends with nothing said about it.
  ///
  /// [_fromData] now rescues most of those. This is for the rest.
  static ({List<RoadPoint> points, int stops}) read(String url) {
    const nothing = (points: <RoadPoint>[], stops: 0);

    final text = url.trim();

    if (text.isEmpty) return nothing;

    final Uri uri;

    try {
      uri = Uri.parse(text);
    } catch (_) {
      return nothing;
    }

    // ── Shape 1: the documented parameters ──────────────────────────
    //
    // Taken first and taken alone. When a link carries these it carries
    // the whole route in them, and the path is decoration.
    final params = uri.queryParameters;

    final listed = <String>[
      params['origin'] ?? '',
      ...(params['waypoints'] ?? '').split(RegExp(r'[|]')),
      params['destination'] ?? '',
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final placed = listed.map(_point).whereType<RoadPoint>().toList();

    // Not `listed.isNotEmpty`: a link whose origin and destination are
    // both names carries these parameters and no route we can read, and
    // the path below may still hold one.
    if (placed.isNotEmpty) {
      return (points: placed, stops: listed.length);
    }

    // ── Shape 2: the stops are path segments ────────────────────────
    final found = _scan(uri);

    // Nulls kept rather than dropped. A null IS the information here:
    // it marks a stop the path named and did not place, which is the
    // slot the blob below is read to fill. Dropping it first is how
    // the ends of a route went missing with nothing to say they had.
    final fromPath = found.stops.map(_point).toList();
    final gaps = fromPath.where((point) => point == null).length;

    final filler = _fromData(found.data);

    // ── WHY THE BLOB FILLS GAPS RATHER THAN REPLACING EVERYTHING ────
    //
    // Because it only HAS the gaps. A real seven-stop link reads
    //
    //   !1m5!1m1!1s0x487ecf…!2m2!1d-1.0613535!2d54.2461552   ← Helmsley
    //   !1m0!1m0!1m0!1m0!1m0                                 ← five pins
    //   !1m5!1m1!1s0x487f28…!2m2!1d-0.7744189!2d54.2438582   ← Pickering
    //
    // One entry per stop, in order, but a stop already written in the
    // path as numbers is encoded as an EMPTY `!1m0` — its coordinates
    // are in the path and Google does not repeat them. Only a stop
    // identified as a place carries its own pair, because a name alone
    // is not a location.
    //
    // So the pairs line up with the stops the path could not place,
    // one for one, and the count is the check that they do. Anything
    // else is a route the two halves disagree about: fall back to the
    // path, which is the half that needs no guessing, and let the
    // caller see `stops` exceed the points it got.
    if (gaps > 0 && filler.length == gaps) {
      var next = 0;

      return (
        points: [for (final point in fromPath) point ?? filler[next++]],
        stops: found.stops.length,
      );
    }

    return (
      points: fromPath.whereType<RoadPoint>().toList(),
      stops: found.stops.length,
    );
  }

  /// The stop segments of a shape 2 path, as TEXT, and its data blob.
  ///
  /// Text rather than points because the COUNT of the stops is what
  /// decides whether the blob can be trusted, and reading them as
  /// coordinates first throws away the names — which are exactly the
  /// ones the count is there to notice.
  static ({List<String> stops, String data}) _scan(Uri uri) {
    final stops = <String>[];
    var data = '';

    for (final segment in uri.pathSegments) {
      // Already decoded. pathSegments decodes for us, and decoding a
      // second time turns a '%' in a place name into a FormatException
      // thrown out of a parser nobody is catching.
      if (segment.isEmpty) continue;

      // The route's address, not stops on it.
      if (segment == 'maps' || segment == 'dir' || segment == 'preview') {
        continue;
      }

      // THE CAMERA, NOT A STOP. See the note at the top of the file.
      if (segment.startsWith('@')) continue;

      if (segment.startsWith('data=')) {
        data = segment.substring('data='.length);

        // Everything past it belongs to the blob.
        break;
      }

      stops.add(segment);
    }

    return (stops: stops, data: data);
  }

  /// The coordinates inside Google's `data=` blob, in route order.
  ///
  /// ── WHAT IS IN THERE ────────────────────────────────────────────
  ///
  /// The blob is Google's own encoding of the route, written as a flat
  /// run of `!<n><type><value>` fields. A stop identified as a PLACE
  /// contributes
  ///
  ///     !1m5!1m1!1s<feature id>!2m2!1d<longitude>!2d<latitude>
  ///
  /// and a stop that was a dropped pin contributes `!1m0` and nothing
  /// else, because its coordinates are already in the path. So what
  /// comes back here is the named stops only — see the merge at the
  /// call site, which is where they are put back in place.
  ///
  /// NOTE THE ORDER. `1d` is longitude and `2d` is latitude, the
  /// opposite way round from every other coordinate in this file.
  /// Reading them in the order they are written puts a route through
  /// the North York Moors into the Gulf of Guinea.
  ///
  /// Anything that is not a believable pair is dropped, which shortens
  /// the list, which fails the count check at the call site and falls
  /// back to the path. Silence here is not silent there.
  static List<RoadPoint> _fromData(String data) {
    if (data.isEmpty) return const [];

    final out = <RoadPoint>[];

    final matches = RegExp(
      r'!2m2!1d(-?\d{1,3}(?:\.\d+)?)!2d(-?\d{1,3}(?:\.\d+)?)',
    ).allMatches(data);

    for (final match in matches) {
      final lng = double.tryParse(match.group(1)!);
      final lat = double.tryParse(match.group(2)!);

      if (lat == null || lng == null) continue;

      final point = RoadPoint(lat, lng);

      if (point.isReal && lat.abs() <= 90 && lng.abs() <= 180) {
        out.add(point);
      }
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
