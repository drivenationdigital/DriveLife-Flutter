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

  TagSuggestion copyWith({bool? guessed}) => TagSuggestion(
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

    return TagSuggestions(
      locations: read('locations'),
      events: read('events'),
      why: ((map['why'] as List?) ?? const [])
          .map((e) => '$e')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  /// Merges another photo's answers in, nearest first and no repeats.
  ///
  /// A post is usually several photos of the same afternoon, so the
  /// lists overlap heavily. Keeping the nearest copy of each place
  /// means the top of the list is the one the user was most likely
  /// actually at, whichever photo saw it best.
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

      final mine = s.distanceMiles;
      final theirs = held.distanceMiles;

      if (mine != null && (theirs == null || mine < theirs)) byId[s.id] = s;
    }

    final out = byId.values.toList()
      ..sort((x, y) {
        final a0 = x.distanceMiles ?? double.infinity;
        final b0 = y.distanceMiles ?? double.infinity;
        return a0.compareTo(b0);
      });

    return out;
  }
}
