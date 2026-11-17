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
    this.polyline = '',
    this.description = '',
  });

  /// Whether the detail call has been made for this one.
  bool get hasShape => polyline.isNotEmpty;

  bool get isPublished => status == 'published';
  bool get isPending => status == 'pending';

  /// "12.4 miles", for a list row.
  String get lengthLabel {
    if (lengthMiles <= 0) return '';

    return lengthMiles >= 10
        ? '${lengthMiles.round()} miles'
        : '${lengthMiles.toStringAsFixed(1)} miles';
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
    distanceMiles: distanceMiles,
    status: status,
    droveCount: droveCount ?? this.droveCount,
    savedCount: savedCount ?? this.savedCount,
    ownerId: ownerId,
    start: start,
    end: end,
    mid: mid,
    iDrove: iDrove ?? this.iDrove,
    iSaved: iSaved ?? this.iSaved,
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

  factory RoadPoint.fromMap(dynamic raw) {
    if (raw is! Map) return none;

    return RoadPoint(
      DrivingRoad.asDouble(raw['lat']),
      DrivingRoad.asDouble(raw['lng']),
    );
  }
}
