import 'dart:math' as math;

import 'package:drivelife/api/cloudflare_images.dart';

/// A stretch of road somebody thinks is worth driving.
///
/// ── NOT A POST, AND NOT A VENUE ─────────────────────────────────────
///
/// It lives in its own table rather than as a WordPress post type —
/// see php-api/sql/roads.sql — because the thing that matters about it
/// is a line on a map, and a line on a map is not something a post can
/// index. Nothing here shares a table, a route or a code path with
/// anything already shipping.
class DrivingRoad {
  final int id;

  /// Which site it was submitted through. Roads are stored once,
  /// globally, with their origin recorded rather than deciding where
  /// they live.
  final String site;

  final String title;
  final String slug;
  final String summary;
  final String region;
  final String country;
  final String coverImage;

  /// How long the ROAD is, following every bend — not the distance
  /// between its ends. On the roads this exists for those two numbers
  /// are nothing like each other.
  final double lengthMiles;

  /// How far the midpoint is from wherever the question was asked.
  /// Zero when it was not a "near me" query.
  final double distanceMiles;

  /// pending | published | rejected | hidden.
  ///
  /// A pending road is visible to the person who submitted it and to
  /// nobody else, so a submission does not appear to vanish.
  final String status;

  final int droveCount;
  final int savedCount;
  final int ownerId;

  final RoadPoint start;
  final RoadPoint end;

  /// The point halfway ALONG the line, which is what "near me"
  /// measures against. It is always a point on the road; the average
  /// of the ends is not, and on a road that doubles back it can be in
  /// the middle of a lake.
  final RoadPoint mid;

  final bool iDrove;
  final bool iSaved;

  /// The garage id of whatever they drove it in, or 0.
  ///
  /// ── WHY BOTH OF THESE CAN BE EMPTY ON A DRIVE ───────────────────
  ///
  /// Because being asked which car and when is a question, and
  /// somebody ticking a road off while scrolling should not be stopped
  /// by one. A road driven in a hire car, from the passenger seat, or
  /// in something sold years ago is still driven.
  ///
  /// So 0 and '' mean "they did not say" rather than "it did not
  /// happen" — [iDrove] is the fact, and these two are the story.
  final int myVehicleId;

  /// YYYY-MM-DD, or empty.
  final String myDroveOn;

  /// When the drive THIS LISTING is about happened.
  ///
  /// ── WHY IT IS NOT [myDroveOn] ───────────────────────────────────
  ///
  /// A road fetched for a vehicle is answering "when did this CAR go
  /// down here", and the car may belong to somebody else — a vehicle
  /// page is public. Folding that into a field called "my" would make
  /// every such row claim the viewer had driven it.
  ///
  /// Empty everywhere except that listing, which is why
  /// [droveOnLabel] falls back to the viewer's own date.
  final String droveOn;

  /// The shape, as an encoded polyline — the format Mapbox returns and
  /// draws, so it is stored and sent exactly as it arrives.
  ///
  /// EMPTY ON A LIST. Only the detail response carries it: twenty
  /// roads' worth of geometry is most of a megabyte for a screen that
  /// draws none of it.
  final String polyline;

  final String description;

  const DrivingRoad({
    required this.id,
    this.site = '',
    this.title = '',
    this.slug = '',
    this.summary = '',
    this.region = '',
    this.country = '',
    this.coverImage = '',
    this.lengthMiles = 0,
    this.distanceMiles = 0,
    this.status = '',
    this.droveCount = 0,
    this.savedCount = 0,
    this.ownerId = 0,
    this.start = RoadPoint.none,
    this.end = RoadPoint.none,
    this.mid = RoadPoint.none,
    this.iDrove = false,
    this.iSaved = false,
    this.myVehicleId = 0,
    this.myDroveOn = '',
    this.droveOn = '',
    this.polyline = '',
    this.description = '',
  });

  /// Whether the detail call has been made for this one.
  bool get hasShape => polyline.isNotEmpty;

  /// The cover photograph, as something Image.network can take.
  ///
  /// ── WHY [coverImage] IS NOT ALREADY ONE ─────────────────────────
  ///
  /// What is stored is the Cloudflare image ID, which is what the rest
  /// of this codebase stores: the URL is built at render time so the
  /// variant and the account hash stay changeable in one place rather
  /// than being baked into every row.
  ///
  /// Drawn with the 'public' variant, which keeps the aspect ratio.
  /// The default is 'thumbnail', a 400x400 SQUARE that crops anything
  /// that is not one already — right for an avatar, wrong for a
  /// landscape photograph of a road.
  ///
  /// A full URL is passed through untouched, because a row filled in
  /// by hand over SQL may well hold one.
  String get coverUrl {
    if (coverImage.isEmpty) return '';

    if (coverImage.startsWith('http')) return coverImage;

    return CloudflareImages.urlFor(
      coverImage,
      variant: CloudflareImages.photo,
    );
  }

  bool get isPublished => status == 'published';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get isHidden => status == 'hidden';

  /// What the status means, said to the person who submitted it.
  ///
  /// ── WHY NOT JUST THE WORD ───────────────────────────────────────
  ///
  /// Because "pending" and "hidden" are our words for our process, and
  /// neither tells somebody whether they need to do anything. The
  /// question behind this label is always the same — did my road work,
  /// and is it my turn — so the label answers that instead.
  ///
  /// Empty for a road in a normal listing, where every road is
  /// published and saying so is noise.
  String get statusLabel {
    switch (status) {
      case 'published':
        return 'Live';
      case 'pending':
        return 'Waiting to be checked';
      case 'rejected':
        return 'Not accepted';
      case 'hidden':
        return 'Hidden';
      default:
        return '';
    }
  }

  /// Whether this status is the person's to do something about.
  ///
  /// Nothing currently is: a rejected road has no reason attached and
  /// no way to edit it, so the honest answer is "no, and we will not
  /// pretend otherwise". Kept as a getter so the screen asks a
  /// question rather than hard-coding the answer, and so adding a
  /// reason later changes one place.
  bool get needsOwnerAction => false;

  /// "12.4 miles", for a list row.
  String get lengthLabel {
    if (lengthMiles <= 0) return '';

    return lengthMiles >= 10
        ? '${lengthMiles.round()} miles'
        : '${lengthMiles.toStringAsFixed(1)} miles';
  }

  /// "August 2019", from a stored YYYY-MM-DD.
  ///
  /// The month, not the day. Somebody recalling a drive from years ago
  /// picked a date off a calendar to the nearest thing they could
  /// remember, and showing "23 August 2019" back to them claims a
  /// precision the answer never had.
  String get droveOnLabel {
    // The listing's own date first. On a vehicle page that is the car's
    // drive; everywhere else it is empty and this is the viewer's.
    final source = droveOn.isNotEmpty ? droveOn : myDroveOn;

    final parts = source.split('-');

    if (parts.length < 2) return '';

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);

    if (year == null || month == null || month < 1 || month > 12) return '';

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return '${months[month - 1]} $year';
  }

  /// "4 miles away", or empty when this was not a nearby query.
  String get awayLabel {
    if (distanceMiles <= 0) return '';

    return distanceMiles < 1
        ? 'Less than a mile away'
        : '${distanceMiles.round()} miles away';
  }

  DrivingRoad copyWith({
    bool? iDrove,
    bool? iSaved,
    int? droveCount,
    int? savedCount,
    String? polyline,
    String? description,
    double? distanceMiles,
    int? myVehicleId,
    String? myDroveOn,
    String? droveOn,
  }) => DrivingRoad(
    id: id,
    site: site,
    title: title,
    slug: slug,
    summary: summary,
    region: region,
    country: country,
    coverImage: coverImage,
    lengthMiles: lengthMiles,
    distanceMiles: distanceMiles ?? this.distanceMiles,
    status: status,
    droveCount: droveCount ?? this.droveCount,
    savedCount: savedCount ?? this.savedCount,
    ownerId: ownerId,
    start: start,
    end: end,
    mid: mid,
    iDrove: iDrove ?? this.iDrove,
    iSaved: iSaved ?? this.iSaved,
    myVehicleId: myVehicleId ?? this.myVehicleId,
    myDroveOn: myDroveOn ?? this.myDroveOn,
    droveOn: droveOn ?? this.droveOn,
    polyline: polyline ?? this.polyline,
    description: description ?? this.description,
  );

  factory DrivingRoad.fromMap(Map<String, dynamic> map) => DrivingRoad(
    id: asInt(map['id']),
    site: asText(map['site']),
    title: asText(map['title']),
    slug: asText(map['slug']),
    summary: asText(map['summary']),
    region: asText(map['region']),
    country: asText(map['country']),
    coverImage: asText(map['cover_image']),
    lengthMiles: asDouble(map['length_miles']),
    distanceMiles: asDouble(map['distance_miles']),
    status: asText(map['status']),
    droveCount: asInt(map['drove_count']),
    savedCount: asInt(map['saved_count']),
    ownerId: asInt(map['owner_id']),
    start: RoadPoint.fromMap(map['start']),
    end: RoadPoint.fromMap(map['end']),
    mid: RoadPoint.fromMap(map['mid']),
    iDrove: map['i_drove'] == true,
    iSaved: map['i_saved'] == true,
    myVehicleId: asInt(map['my_vehicle_id']),
    myDroveOn: asText(map['my_drove_on']),
    droveOn: asText(map['drove_on']),
    polyline: asText(map['polyline']),
    description: asText(map['description']),
  );

  /// ── WHY EVERY NUMBER GOES THROUGH A READER ────────────────────────
  ///
  /// PHP hands integers back as JSON numbers normally and as STRINGS
  /// when a column comes straight out of MySQL without a cast, and
  /// `as num` throws on a string rather than returning null. DECIMAL
  /// columns are the worst of it: `length_miles` is DECIMAL(7,2) and
  /// arrives as "12.40".
  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static double asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static String asText(dynamic value) => value == null ? '' : '$value'.trim();
}

/// One coordinate.
class RoadPoint {
  final double lat;
  final double lng;

  const RoadPoint(this.lat, this.lng);

  static const RoadPoint none = RoadPoint(0, 0);

  /// Whether this is a real place.
  ///
  /// Exactly 0,0 is in the Gulf of Guinea and is, every time, a
  /// coordinate that failed to parse rather than somewhere a road is.
  /// The server refuses it on the way in; this is the same rule on the
  /// way back out, for a row that predates it.
  bool get isReal => !(lat == 0 && lng == 0) && lat.abs() <= 90;

  /// Statute miles from here to there.
  ///
  /// ── WHY THE APP CAN DO THIS AT ALL ──────────────────────────────
  ///
  /// Every road in a list carries its midpoint, so a list fetched
  /// WITHOUT a location can still be ordered by distance once one is
  /// known — which is what lets the roads screen fall back to the
  /// national list and still put the nearest first.
  ///
  /// The same haversine as dl_roads_distance() in roads.php, and for
  /// the same reason it is written out rather than approximated: at
  /// these latitudes a flat-earth version is wrong by several miles
  /// over a couple of counties, which is enough to reorder a list.
  double milesTo(RoadPoint other) {
    const earthMiles = 7917.5 / 2;

    double radians(double degrees) => degrees * math.pi / 180;

    final dLat = radians(other.lat - lat);
    final dLng = radians(other.lng - lng);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(lat)) *
            math.cos(radians(other.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    // asin of a clamped root rather than atan2: with two identical
    // points, floating point can hand sqrt() a hair over 1, and the
    // result is NaN rather than the zero it should be.
    return 2 * earthMiles * math.asin(math.min(1.0, math.sqrt(a)));
  }

  factory RoadPoint.fromMap(dynamic raw) {
    if (raw is! Map) return none;

    return RoadPoint(
      DrivingRoad.asDouble(raw['lat']),
      DrivingRoad.asDouble(raw['lng']),
    );
  }
}
