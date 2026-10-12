import 'package:flutter/material.dart';

/// What a pin on the Discover map can be.
///
/// The mock also shows a "Business" category. There is no `business` post type
/// in WordPress yet — only `events`, `clubs` and `venues` — so adding a chip
/// for it would mean a filter that is permanently empty. It joins this enum,
/// and the chip row and the map pick it up automatically, the day the post
/// type and its radius query exist.
enum DiscoverKind {
  event(
    label: 'Events',
    colour: Color(0xFFD9A441),
    icon: Icons.calendar_today_rounded,
  ),
  venue(
    label: 'Venues',
    colour: Color(0xFF1C1C1E),
    icon: Icons.storefront_rounded,
  );

  const DiscoverKind({
    required this.label,
    required this.colour,
    required this.icon,
  });

  final String label;

  /// The pin colour, and the dot on this category's chip. The two have to be
  /// the same value or the legend stops being a legend.
  final Color colour;

  final IconData icon;

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

  static String? _text(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    return s.isEmpty ? null : s;
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
      raw: json,
    );
  }

  /// Reads an item from `app/v2/get-venues-trending`.
  ///
  /// Note the capital `ID`: the venues endpoint returns the raw column name
  /// where the events endpoint lower-cases it.
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
