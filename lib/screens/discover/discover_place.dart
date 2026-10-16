import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What a pin on the Discover map can be.
///
/// Four categories, because that is what the design shows. Only two of them
/// have anything behind them: WordPress has `events` and `venues` post types
/// with coordinates and a radius query, and nothing for businesses or
/// standalone locations. Those two are wired up end to end — chip, colour,
/// pin image, filter row — and simply fetch nothing, so the day a post type
/// exists the only change is the fetch itself.
///
/// [backed] is what tells them apart, and it is the honest bit: an unbacked
/// category reads "Coming soon" in the filters rather than "0", because 0
/// claims we looked and there was nothing there.
enum DiscoverKind {
  event(
    label: 'Events',
    colour: Color(0xFFC4A86A),
    icon: Icons.calendar_today_rounded,
    backed: true,
  ),
  venue(
    label: 'Venues',
    colour: Color(0xFF1C1C1E),
    icon: Icons.storefront_rounded,
    backed: true,
  ),
  track(
    label: 'Tracks',
    colour: Color(0xFFB4452F),
    icon: Icons.sports_score_rounded,
    backed: true,
  ),
  business(
    label: 'Businesses',
    colour: Color(0xFF5B7FA3),
    icon: Icons.build_rounded,
    backed: false,
  ),
  location(
    label: 'Locations',
    colour: Color(0xFF4E8C5A),
    icon: Icons.place_rounded,
    backed: false,
  );

  const DiscoverKind({
    required this.label,
    required this.colour,
    required this.icon,
    required this.backed,
  });

  /// The categories the map actually offers.
  ///
  /// Businesses and Locations are hidden for now. They were drawn as
  /// "Coming soon" chips — honest, but two of the five rows in the filter
  /// sheet were things nobody could switch on, and a chip you cannot use is
  /// a chip in the way.
  ///
  /// Hidden, not deleted: everything behind them — colour, pin image,
  /// filter plumbing — still works, so bringing them back is one line here
  /// plus the fetch. Use this wherever the UI lists categories, and
  /// `values` only where every case must be handled.
  static const List<DiscoverKind> shown = [event, venue, track];

  final String label;

  /// The pin colour, and the dot on this category's chip. The two have to be
  /// the same value or the legend stops being a legend.
  final Color colour;

  final IconData icon;

  /// Whether anything on the server can actually return one of these.
  final bool backed;

  /// The id this kind's pin image is registered under in the map style, which
  /// is also what each feature carries in its `icon` property.
  String get iconId => 'dl-pin-$name';
}

/// One thing on the map, and the same thing in the list below it.
///
/// Deliberately one type for both: the sheet and the pins are two views of a
/// single result set, and giving them separate models is how they drift into
/// disagreeing about how many results there are.
@immutable
class DiscoverPlace {
  final String id;
  final DiscoverKind kind;
  final String title;
  final String? subtitle;
  final String? thumbnail;
  final double latitude;
  final double longitude;

  /// Miles from the search centre, as the server worked it out. Null for
  /// events, whose endpoint computes a distance to sort by but does not
  /// return it.
  final double? distance;

  /// When the event starts. Null for anything that is not an event — a venue
  /// is open whenever it is open and has no single date to show.
  final DateTime? startsAt;

  /// 'GB' or 'US'. Carried because a post id is only unique within its blog,
  /// so opening the detail screen needs both.
  final String? site;

  /// The raw JSON this was read from, passed straight to the detail screen.
  ///
  /// The event detail screen takes the whole map the list endpoint produced
  /// and reads far more out of it than a pin needs. Re-deriving that from the
  /// typed fields here would mean reconstructing fields this class never
  /// looked at, so the original is kept intact.
  final Map<String, dynamic> raw;

  const DiscoverPlace({
    required this.id,
    required this.kind,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.raw,
    this.subtitle,
    this.thumbnail,
    this.distance,
    this.site,
    this.startsAt,
  });

  /// A coordinate from JSON, or null if it is not one.
  ///
  /// WordPress stores latitude and longitude as post meta, which is to say as
  /// strings, and whether a given endpoint casts them before encoding is not
  /// something the app should have to know. Anything unparseable returns null
  /// and the result is dropped from the map rather than pinned at (0, 0) —
  /// the Gulf of Guinea is a long way from Teesside.
  static double? _coord(dynamic value) {
    final parsed = switch (value) {
      final double v => v,
      final num v => v.toDouble(),
      final String v => double.tryParse(v.trim()),
      _ => null,
    };
    if (parsed == null || parsed == 0 || parsed.isNaN) return null;
    return parsed;
  }

  /// Reads the date format the events endpoint sends.
  ///
  /// That is `MM/DD/YYYY HH:MM` — month first, built by PHP with
  /// `date('m/d/Y', ...)`. DateTime.parse rejects it outright, and anything
  /// that guessed day-first would read 01/02 as 1 February rather than
  /// 2 January and be wrong for the first twelve days of every month without
  /// ever looking wrong.
  ///
  /// Null for anything unparseable, which simply leaves the date off the card
  /// rather than showing a wrong one.
  static DateTime? _date(dynamic value) {
    if (value == null) return null;

    final parts = '$value'.trim().split(' ').first.split('/');
    if (parts.length != 3) return null;

    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (month == null || day == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000) {
      return null;
    }

    final date = DateTime(year, month, day);
    // DateTime rolls 31 February over into March rather than refusing it, so
    // check the parts survived the trip.
    if (date.month != month || date.day != day) return null;
    return date;
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    // "false" as well as empty: PHP's wp_get_attachment_image_url returns
    // false for a missing attachment, which encodes as `false` and arrives
    // here as a four-letter string that is then handed to an image loader.
    if (s.isEmpty || s == 'null' || s == 'false') return null;
    return s;
  }

  /// Reads an item from `app/v2/get-events-trending`.
  ///
  /// Null when the event has no usable coordinates, which happens for the odd
  /// online or TBC event. Callers drop those rather than guessing a location.
  static DiscoverPlace? fromEvent(Map<String, dynamic> json) {
    final lat = _coord(json['latitude']);
    final lng = _coord(json['longitude']);
    if (lat == null || lng == null) return null;

    return DiscoverPlace(
      id: '${json['id']}',
      kind: DiscoverKind.event,
      title: _text(json['title']) ?? 'Untitled event',
      subtitle: _text(json['location']),
      thumbnail: _text(json['thumbnail']),
      latitude: lat,
      longitude: lng,
      site: _text(json['site']),
      startsAt: _date(json['start_date']),
      raw: json,
    );
  }

  /// Reads an item from `app/v2/get-venues-trending`.
  ///
  /// Note the capital `ID`: this endpoint returns the raw column name where
  /// the events endpoint lower-cases it.
  static DiscoverPlace? fromVenue(Map<String, dynamic> json) {
    final lat = _coord(json['latitude']);
    final lng = _coord(json['longitude']);
    if (lat == null || lng == null) return null;

    return DiscoverPlace(
      id: '${json['ID'] ?? json['id']}',
      kind: DiscoverKind.venue,
      title: _text(json['title']) ?? 'Untitled venue',
      subtitle: _text(json['venue_location']),
      thumbnail: _text(json['cover_image']) ?? _text(json['logo']),
      latitude: lat,
      longitude: lng,
      distance: _coord(json['distance']),
      site: _text(json['site']),
      raw: json,
    );
  }

  /// Reads an item from `app/v2/get-tracks-trending`.
  ///
  /// A separate endpoint from venues with its own field names, so a separate
  /// reader. The shared version of these two is what put the user's venues
  /// under "My tracks".
  static DiscoverPlace? fromTrack(Map<String, dynamic> json) {
    final lat = _coord(json['latitude']);
    final lng = _coord(json['longitude']);
    if (lat == null || lng == null) return null;

    return DiscoverPlace(
      id: '${json['ID'] ?? json['id']}',
      kind: DiscoverKind.track,
      title: _text(json['title']) ?? 'Untitled track',
      subtitle: _text(json['track_location']),
      thumbnail: _text(json['cover_image']) ?? _text(json['logo']),
      latitude: lat,
      longitude: lng,
      distance: _coord(json['distance']),
      site: _text(json['site']),
      raw: json,
    );
  }

  /// This place as a GeoJSON feature for the map source.
  ///
  /// `icon` names the registered pin image and `kind` is what the category
  /// filter matches on — both as plain strings, because a style expression
  /// can compare those and cannot compare a Dart enum.
  Map<String, dynamic> toFeature() => {
    'type': 'Feature',
    'id': '${kind.name}-$id',
    'properties': {
      'id': id,
      'kind': kind.name,
      'icon': kind.iconId,
      'title': title,
    },
    'geometry': {
      'type': 'Point',
      // GeoJSON is longitude first. Getting this the wrong way round puts
      // every UK pin in Somalia, which at least fails obviously.
      'coordinates': [longitude, latitude],
    },
  };
}

/// The places on offer, after the filter sheet, the chip row and the search
/// box have each had their say.
///
/// One function, used for both the map's GeoJSON source and the results
/// sheet. That is the point: the pins, the cluster counts and the "N nearby"
/// heading are three views of this list, and when they were computed
/// separately they disagreed — the clusters counted categories that were
/// filtered out, because clustering runs on the source before any layer
/// filter, and the search box narrowed the list while the map showed
/// everything.
///
/// [kinds] is what the filter sheet allows; [category] is the single chip
/// focused in the row above the map, or null for all of them; [query] matches
/// a title or its subtitle, case-insensitively.
List<DiscoverPlace> discoverVisible(
  List<DiscoverPlace> places, {
  required Set<DiscoverKind> kinds,
  DiscoverKind? category,
  String query = '',
}) {
  final q = query.trim().toLowerCase();

  return places.where((p) {
    if (!kinds.contains(p.kind)) return false;
    if (category != null && p.kind != category) return false;
    if (q.isEmpty) return true;
    return p.title.toLowerCase().contains(q) ||
        (p.subtitle?.toLowerCase().contains(q) ?? false);
  }).toList();
}

/// An event's date, as it reads on a result card.
///
/// "Sat 18 Oct", with the year appended only when it is not the current one.
/// The cards are narrow and the date shares its line with the location, so
/// four characters of "2026" on every row — which is nearly always this year
/// — would push the place name out for nothing.
///
/// Null when there is no date, which is every venue.
String? discoverDateLabel(DateTime? when, {DateTime? now}) {
  if (when == null) return null;

  final today = now ?? DateTime.now();
  final format = when.year == today.year ? 'EEE d MMM' : 'EEE d MMM yy';
  return DateFormat(format).format(when);
}
