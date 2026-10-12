import 'dart:convert';

import 'package:drivelife/screens/discover/discover_place.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the Discover map's parsing.
///
/// This is the layer where a map silently lies. A pin at the wrong
/// coordinates looks exactly like a pin at the right ones, and WordPress
/// stores latitude and longitude as post meta — which is to say as strings,
/// sometimes, depending on which endpoint cast them on the way out. These
/// tests pin down what the two endpoints actually send.
void main() {
  group('events', () {
    Map<String, dynamic> event({dynamic lat = 54.57, dynamic lng = -1.23}) => {
      'id': 1234,
      'title': 'Teesside Auto Show',
      'location': 'Middlesbrough',
      'thumbnail': 'https://example.test/cover.jpg',
      'site': 'GB',
      'latitude': lat,
      'longitude': lng,
    };

    test('reads a well-formed event', () {
      final place = DiscoverPlace.fromEvent(event())!;

      expect(place.id, '1234');
      expect(place.kind, DiscoverKind.event);
      expect(place.title, 'Teesside Auto Show');
      expect(place.subtitle, 'Middlesbrough');
      expect(place.latitude, closeTo(54.57, 1e-9));
      expect(place.longitude, closeTo(-1.23, 1e-9));
      expect(place.site, 'GB');
    });

    test('accepts coordinates as strings', () {
      // The meta is stored as text, so an endpoint that forgets to cast
      // sends "54.57". Refusing to parse that would empty the map.
      final place = DiscoverPlace.fromEvent(
        event(lat: '54.57', lng: '-1.23'),
      )!;

      expect(place.latitude, closeTo(54.57, 1e-9));
      expect(place.longitude, closeTo(-1.23, 1e-9));
    });

    test('accepts an integer coordinate', () {
      final place = DiscoverPlace.fromEvent(event(lat: 54, lng: -1))!;

      expect(place.latitude, 54.0);
      expect(place.longitude, -1.0);
    });

    test('rejects an event with no coordinates', () {
      expect(DiscoverPlace.fromEvent(event(lat: null, lng: null)), isNull);
      expect(DiscoverPlace.fromEvent(event(lng: null)), isNull);
    });

    test('rejects nonsense rather than pinning it somewhere', () {
      expect(DiscoverPlace.fromEvent(event(lat: '')), isNull);
      expect(DiscoverPlace.fromEvent(event(lat: 'TBC')), isNull);
    });

    test('rejects a zero coordinate', () {
      // Null Island is how an unset meta row reaches the client once
      // something has cast it. A pin 380 miles off the coast of Ghana is
      // worse than no pin, because it looks like a real result.
      expect(DiscoverPlace.fromEvent(event(lat: 0)), isNull);
      expect(DiscoverPlace.fromEvent(event(lng: '0')), isNull);
    });

    test('keeps the original JSON for the detail screen', () {
      final json = event();
      final place = DiscoverPlace.fromEvent(json)!;

      // The event detail route is handed the whole map every other list in
      // the app gives it, not a reconstruction from the typed fields.
      expect(place.raw, same(json));
    });
  });

  group('venues', () {
    test('reads the capitalised ID the venues endpoint sends', () {
      // The venues query returns the raw column name. Reading 'id' here
      // would give every venue the id "null" — and they would all collide.
      final place = DiscoverPlace.fromVenue({
        'ID': 88,
        'title': 'Croft Circuit',
        'venue_location': 'Darlington',
        'latitude': '54.4552',
        'longitude': '-1.5570',
        'distance': 12.4,
        'site': 'GB',
      })!;

      expect(place.id, '88');
      expect(place.kind, DiscoverKind.venue);
      expect(place.distance, closeTo(12.4, 1e-9));
    });

    test('falls back to the logo when there is no cover image', () {
      final place = DiscoverPlace.fromVenue({
        'ID': 1,
        'title': 'A venue',
        'latitude': 54.0,
        'longitude': -1.0,
        'cover_image': null,
        'logo': 'https://example.test/logo.png',
      })!;

      expect(place.thumbnail, 'https://example.test/logo.png');
    });
  });

  group('geojson', () {
    test('writes longitude first', () {
      // GeoJSON is [lng, lat]. Reversed, every UK pin lands in Somalia.
      final place = DiscoverPlace.fromEvent({
        'id': 7,
        'title': 'x',
        'latitude': 54.57,
        'longitude': -1.23,
      })!;

      final coords =
          place.toFeature()['geometry']['coordinates'] as List<dynamic>;

      expect(coords.first, closeTo(-1.23, 1e-9));
      expect(coords.last, closeTo(54.57, 1e-9));
    });

    test('carries the properties the style expressions read', () {
      final place = DiscoverPlace.fromVenue({
        'ID': 9,
        'title': 'A venue',
        'latitude': 54.0,
        'longitude': -1.0,
      })!;

      final props = place.toFeature()['properties'] as Map<String, dynamic>;

      // The pin layer picks its image with ['get', 'icon'] and the category
      // chip filters on ['get', 'kind']. Both must be plain strings: a style
      // expression cannot compare a Dart enum.
      expect(props['icon'], DiscoverKind.venue.iconId);
      expect(props['kind'], 'venue');
      expect(props['id'], '9');
    });

    test('an event and a venue sharing a post id stay distinct', () {
      // Post ids are only unique within a post type, so a feature id of
      // just the post id would have one overwrite the other in the source.
      final event = DiscoverPlace.fromEvent({
        'id': 42,
        'title': 'e',
        'latitude': 54.0,
        'longitude': -1.0,
      })!;
      final venue = DiscoverPlace.fromVenue({
        'ID': 42,
        'title': 'v',
        'latitude': 54.0,
        'longitude': -1.0,
      })!;

      expect(event.toFeature()['id'], isNot(venue.toFeature()['id']));
    });

    test('is encodable, which is how it reaches the map', () {
      final place = DiscoverPlace.fromEvent({
        'id': 1,
        'title': 'x',
        'latitude': 54.0,
        'longitude': -1.0,
      })!;

      expect(() => jsonEncode(place.toFeature()), returnsNormally);
    });
  });
}
