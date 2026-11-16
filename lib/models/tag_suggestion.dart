import 'dart:math' as math;

/// Somewhere a photo might have been taken, or something that was on
/// there that day.
///
/// ── WHY A GUESS IS MARKED AS ONE ────────────────────────────────────
///
/// The first of these is applied to the post without being asked, which
/// is the whole point: nobody tags a location if it costs three taps.
/// But an automatic tag the user never noticed is a claim made on their
/// behalf about where they were, so [guessed] exists to put a mark next
/// to it — the tag is removable, and it has to look removable.
class TagSuggestion {
  /// The WordPress post id of the venue, circuit or event.
  final String id;

  final String title;

  /// The town, or the dates — whatever tells two similar names apart.
  final String subtitle;

  /// Miles from the photo. Null when it did not come from coordinates.
  final double? distanceMiles;

  final String? imageUrl;

  /// The PLACE's own coordinates, not the photo's.
  ///
  /// A post tagged "Donington Park" should drop its pin on the circuit
  /// rather than on the spot in the car park the photographer stood in
  /// — and definitely not there when the chosen place is the second or
  /// third in the list, which can be miles from the photo.
  final double? latitude;
  final double? longitude;

  /// 'venue', 'track' or 'event' — which column on the post this
  /// belongs in. Empty when the server did not say.
  final String kind;

  /// When an event ran. Null for a venue, which has no dates.
  final DateTime? startsOn;
  final DateTime? endsOn;

  /// Set when the app applied this on its own rather than being told to.
  final bool guessed;

  /// How many of the post's photos matched this one.
  ///
  /// ── WHY THIS IS THE RANKING, NOT DISTANCE ─────────────────────────
  ///
  /// Distance answers "what was closest to a photo". The question is
  /// "what is this post about". Those differ: a set of pictures from a
  /// show gets tagged with a different event half a mile nearer that
  /// one frame caught the edge of, which is what happened to a batch
  /// of Leicester Airport photos.
  ///
  /// How many of the photos agree is the stronger signal, and distance
  /// decides between equals. A single-photo post has one of everything,
  /// so there it changes nothing.
  final int photos;

  const TagSuggestion({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.distanceMiles,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.kind = '',
    this.startsOn,
    this.endsOn,
    this.guessed = false,
    this.photos = 1,
  });

  factory TagSuggestion.fromMap(Map<String, dynamic> map) {
    final distance = map['distance_mi'];

    return TagSuggestion(
      id: '${map['id'] ?? ''}',
      title: '${map['title'] ?? ''}',
      subtitle: '${map['subtitle'] ?? ''}',
      distanceMiles: distance is num
          ? distance.toDouble()
          : double.tryParse('$distance'),
      imageUrl: (map['image'] == null || '${map['image']}'.isEmpty)
          ? null
          : '${map['image']}',
      latitude: _coord(map['lat']),
      longitude: _coord(map['lng']),
      kind: '${map['kind'] ?? ''}',
      startsOn: _date(map['starts_on']),
      endsOn: _date(map['ends_on']),
      // The server merges across photos too, for tags applied by the
      // sweep rather than on the phone, and sends its count.
      photos: int.tryParse('${map['photos'] ?? 1}') ?? 1,
    );
  }

  static double? _coord(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }

  TagSuggestion asGuess() => copyWith(guessed: true);

  TagSuggestion copyWith({bool? guessed, int? photos}) => TagSuggestion(
    id: id,
    title: title,
    subtitle: subtitle,
    distanceMiles: distanceMiles,
    imageUrl: imageUrl,
    latitude: latitude,
    longitude: longitude,
    kind: kind,
    startsOn: startsOn,
    endsOn: endsOn,
    guessed: guessed ?? this.guessed,
    photos: photos ?? this.photos,
  );

  /// "1 Aug 2026 · Ettington · 0.1 mi", or whichever parts exist.
  ///
  /// The date leads for an event, because that is what makes it the
  /// right one — a circuit has something on most weekends, and the
  /// name alone does not say which weekend this was.
  ///
  /// The distance is never shown as "0.0 mi", which reads as an error
  /// rather than as "you were standing in it".
  String get detail {
    final bits = <String>[];

    final when = _when;
    if (when != null) bits.add(when);

    if (subtitle.isNotEmpty) bits.add(subtitle);

    final miles = distanceMiles;

    if (miles != null) {
      bits.add(miles < 0.1 ? 'here' : '${miles.toStringAsFixed(1)} mi');
    }

    return bits.join(' · ');
  }

  /// [detail] plus this place's OWN coordinates, for the debug panel.
  ///
  /// ── WHY THE PLACE'S, NOT THE PHOTO'S ────────────────────────────
  ///
  /// A distance is a claim about two points, and the panel on the
  /// composer already shows one of them. Showing the other turns "0.1
  /// mi looks wrong" into something checkable: either the photo's
  /// reading is off, or this event is not where it says it is, and
  /// those have completely different fixes.
  String get debugDetail {
    final lat = latitude;
    final lng = longitude;

    final where = (lat == null || lng == null)
        ? 'no coords'
        : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

    // One line: the picker's ListTile is not set up for a tall
    // subtitle, and a title that already wraps would push it out.
    final bits = detail;

    return bits.isEmpty ? '$where · #$id' : '$bits · $where · #$id';
  }

  /// "1 Aug 2026", or "1–3 Aug 2026" for a run of days.
  String? get _when {
    final from = startsOn;
    if (from == null) return null;

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final to = endsOn;

    if (to == null || (to.year == from.year &&
        to.month == from.month &&
        to.day == from.day)) {
      return '${from.day} ${months[from.month - 1]} ${from.year}';
    }

    // Same month reads as a range of days rather than two full dates.
    if (to.year == from.year && to.month == from.month) {
      return '${from.day}–${to.day} ${months[from.month - 1]} ${from.year}';
    }

    return '${from.day} ${months[from.month - 1]} — '
        '${to.day} ${months[to.month - 1]} ${to.year}';
  }

  @override
  bool operator ==(Object other) =>
      other is TagSuggestion && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// What was near one photo: the places, and the events on that day.
class TagSuggestions {
  final List<TagSuggestion> locations;
  final List<TagSuggestion> events;

  /// The place already saved on the post, if any.
  ///
  /// Not a suggestion — this is what the post currently says. It lives
  /// in columns on ce_social_posts rather than as a tag row, so nothing
  /// in the tag list carries it.
  final TagSuggestion? current;

  /// Why nothing was found, when nothing was.
  ///
  /// Four different problems produce an identical empty screen — no GPS
  /// on the photos, a place index that was never built, an endpoint that
  /// is not deployed, and genuinely nothing nearby. The server says
  /// which, because by the time anybody looks the coordinates that would
  /// settle it have been erased.
  final List<String> why;

  const TagSuggestions({
    this.locations = const [],
    this.events = const [],
    this.current,
    this.why = const [],
  });

  static const TagSuggestions empty = TagSuggestions();

  bool get isEmpty => locations.isEmpty && events.isEmpty;

  factory TagSuggestions.fromMap(Map<String, dynamic> map) {
    List<TagSuggestion> read(String key) =>
        ((map[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TagSuggestion.fromMap(Map<String, dynamic>.from(e)))
            .where((s) => s.id.isNotEmpty && s.title.isNotEmpty)
            .toList();

    final saved = map['current_location'];

    return TagSuggestions(
      locations: read('locations'),
      events: read('events'),
      current: saved is Map
          ? TagSuggestion.fromMap({
              ...Map<String, dynamic>.from(saved),
              // The server sends it under `title`; fromMap reads the
              // same keys as a suggestion so one reader serves both.
              'title': '${saved['title'] ?? ''}',
            })
          : null,
      why: ((map['why'] as List?) ?? const [])
          .map((e) => '$e')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  /// Merges another photo's answers in, best first and no repeats.
  ///
  /// A post is usually several photos of the same afternoon, so the
  /// lists overlap heavily. Keeping the nearest copy of each place
  /// means its distance is the best any photo saw it at — and counting
  /// how many photos saw it at all is what decides the order. See
  /// [TagSuggestion.photos].
  TagSuggestions mergedWith(TagSuggestions other) => TagSuggestions(
    locations: _merge(locations, other.locations),
    events: _merge(events, other.events),
    why: {...why, ...other.why}.toList(),
  );

  static List<TagSuggestion> _merge(
    List<TagSuggestion> a,
    List<TagSuggestion> b,
  ) {
    final byId = <String, TagSuggestion>{};

    for (final s in [...a, ...b]) {
      final held = byId[s.id];

      if (held == null) {
        byId[s.id] = s;
        continue;
      }

      // Both lists can already be merged results, so the counts add
      // rather than stepping by one.
      final seen = held.photos + s.photos;

      final mine = s.distanceMiles;
      final theirs = held.distanceMiles;

      final best = (mine != null && (theirs == null || mine < theirs))
          ? s
          : held;

      byId[s.id] = best.copyWith(photos: seen);
    }

    final out = byId.values.toList()
      ..sort((x, y) {
        if (x.photos != y.photos) return y.photos.compareTo(x.photos);

        final a0 = x.distanceMiles ?? double.infinity;
        final b0 = y.distanceMiles ?? double.infinity;
        return a0.compareTo(b0);
      });

    return _collapseDuplicates(out);
  }

  /// Drops records of the same thing entered into WordPress twice.
  ///
  /// Only an exact title match counts — see [_slug]. Two events with
  /// similar names on one site are a real thing and must both survive.
  ///
  /// ── WHY IT IS DONE AGAIN HERE ───────────────────────────────────
  ///
  /// The server collapses each photo's answers before sending them, and
  /// that is not enough. The copies have different ids, so when one
  /// photo keeps the copy nearest to IT and another photo keeps the
  /// other, merging the two lists brings both back — keyed separately,
  /// looking for all the world like two events.
  ///
  /// The list is already in the order we want, so the first of each
  /// group survives.
  static List<TagSuggestion> _collapseDuplicates(List<TagSuggestion> items) {
    final out = <TagSuggestion>[];

    for (final item in items) {
      if (!out.any((held) => _sameThing(held, item))) out.add(item);
    }

    return out;
  }

  /// Same name, same days, same place — so, one thing.
  static bool _sameThing(TagSuggestion a, TagSuggestion b) {
    final name = _slug(a.title);

    // Nothing but punctuation. Two of those prove nothing.
    if (name.isEmpty || name != _slug(b.title)) return false;

    final aFrom = a.startsOn;
    final bFrom = b.startsOn;

    // One dated and one not is a venue beside an event, never a pair.
    if ((aFrom == null) != (bFrom == null)) return false;

    if (aFrom != null && bFrom != null) {
      final aTo = a.endsOn ?? aFrom;
      final bTo = b.endsOn ?? bFrom;

      // Any shared day. Two runs of one show that overlap on none are
      // two different runs.
      if (aTo.isBefore(bFrom) || bTo.isBefore(aFrom)) return false;
    }

    final apart = _milesApart(a, b);

    // Generous, because two hand-entered copies are pinned separately
    // and never agree exactly. The NAME is what identifies them; this
    // only keeps two identically named regional rounds apart.
    return apart != null && apart <= 1.0;
  }

  /// A title reduced to what it is actually called.
  ///
  /// ── WHY THIS IS DELIBERATELY STRICT ─────────────────────────────
  ///
  /// Case and spacing, and nothing else. An earlier version also
  /// stripped punctuation and read "&" as "and", which is right for one
  /// name typed twice and wrong here: a venue ran two separate events
  /// on one site called "Motorshow and Family Fun day" and "Motor Show
  /// & Family Fun Day", and that rule collapsed them, deleting a real
  /// event from the list.
  ///
  /// A duplicate is normally one record entered twice, so its titles
  /// agree exactly. Two titles that differ are two titles.
  static String _slug(String title) =>
      title.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Miles between two places, or null if either has no coordinates.
  static double? _milesApart(TagSuggestion a, TagSuggestion b) {
    final aLat = a.latitude, aLng = a.longitude;
    final bLat = b.latitude, bLng = b.longitude;

    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return null;
    }

    const toRad = math.pi / 180;

    final lat1 = aLat * toRad;
    final lat2 = bLat * toRad;
    final dLat = lat2 - lat1;
    final dLng = (bLng - aLng) * toRad;

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) *
            math.sin(dLng / 2);

    return 2 * 3959 * math.asin(math.min(1.0, math.sqrt(h)));
  }
}
