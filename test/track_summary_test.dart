import 'package:drivelife/screens/discover/discover_place.dart';
import 'package:drivelife/screens/tracks/tracks_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for reading tracks.
///
/// Tracks were briefly served by the venue endpoints with a post type passed
/// through them. That produced two bugs on the first run: the venue blog
/// locator only accepted `venues` posts, so every track came back 404, and
/// "My tracks" ran the venue query and listed the user's venues.
///
/// They now have their own endpoints with their own field names, so these
/// check the reader is reading the right ones — a track's location is
/// `track_location`, not `venue_location`, and reading the wrong key gives a
/// card with no address rather than an error.
void main() {
  Map<String, dynamic> row({
    dynamic id = 88,
    dynamic location = 'West Ln, Dalton-on-Tees, Darlington',
  }) => {
    'ID': id,
    'title': 'Croft Circuit',
    'track_location': location,
    'cover_image': 'https://example.test/cover.jpg',
    'logo': 'https://example.test/logo.png',
    'latitude': '54.4552',
    'longitude': '-1.5570',
    'distance': 12.4,
    'site': 'GB',
  };

  group('list rows', () {
    test('reads a track', () {
      final track = TrackSummary.fromJson(row());

      expect(track.id, '88');
      expect(track.title, 'Croft Circuit');
      expect(track.location, 'West Ln, Dalton-on-Tees, Darlington');
      expect(track.distance, closeTo(12.4, 1e-9));
      expect(track.site, 'GB');
    });

    test('reads the capitalised ID the endpoint sends', () {
      // Reading 'id' would give every track the id "null", and they would
      // all collide into one.
      expect(TrackSummary.fromJson(row(id: 7)).id, '7');
    });

    test('falls back to the logo when there is no cover image', () {
      final json = row()..['cover_image'] = null;
      expect(TrackSummary.fromJson(json).image, 'https://example.test/logo.png');
    });

    test('survives a track with no location', () {
      expect(TrackSummary.fromJson(row(location: null)).location, isNull);
      expect(TrackSummary.fromJson(row(location: '')).location, isNull);
    });

    test('treats a missing attachment as no image, not an image at "false"', () {
      // wp_get_attachment_image_url() returns FALSE when the attachment has
      // gone. That encodes as `false`, arrives as the four-letter string,
      // and was handed straight to the image loader — which is why tracks
      // showed broken tiles rather than the placeholder.
      final json = row()
        ..['cover_image'] = false
        ..['logo'] = false;

      expect(TrackSummary.fromJson(json).image, isNull);
    });

    test('ignores anything that is not a URL', () {
      // An attachment id that was never resolved to an address is a
      // guaranteed failed request.
      final json = row()
        ..['cover_image'] = 4821
        ..['logo'] = '';

      expect(TrackSummary.fromJson(json).image, isNull);
    });

    test('treats the string "null" as absent', () {
      // ACF text fields come back this way often enough to matter, and the
      // word "null" under a track name looks like a bug to a user.
      expect(TrackSummary.fromJson(row(location: 'null')).location, isNull);
    });
  });

  group('track types', () {
    test('reads the disciplines a track runs', () {
      // A track can be several at once — the admin screen says so: "tick
      // everything that applies - a venue can be a race circuit and a drag
      // strip" — so this is always a list.
      final json = row()..['types'] = ['Race circuit', 'Drag strip'];

      expect(TrackSummary.fromJson(json).types, ['Race circuit', 'Drag strip']);
    });

    test('is empty when the field is absent', () {
      // The field is found by its label on the server, and a track that has
      // never been given a type simply has none. No badges is tidier than a
      // wrong badge.
      expect(TrackSummary.fromJson(row()).types, isEmpty);
    });

    test('survives a field that is not a list', () {
      final json = row()..['types'] = 'Race circuit';
      expect(TrackSummary.fromJson(json).types, isEmpty);
    });

    test('drops blanks rather than showing an empty badge', () {
      final json = row()..['types'] = ['Race circuit', '', null, 'null'];
      expect(TrackSummary.fromJson(json).types, ['Race circuit']);
    });
  });

  group('map pins', () {
    test('reads a track onto the map', () {
      final place = DiscoverPlace.fromTrack(row())!;

      expect(place.kind, DiscoverKind.track);
      expect(place.title, 'Croft Circuit');
      // track_location, not venue_location: the endpoints are separate and
      // so are their field names.
      expect(place.subtitle, 'West Ln, Dalton-on-Tees, Darlington');
      expect(place.latitude, closeTo(54.4552, 1e-9));
    });

    test('a track and a venue sharing a post id stay distinct', () {
      // Post ids are only unique within a post type, and the two live in
      // the same GeoJSON source.
      final track = DiscoverPlace.fromTrack(row(id: 42))!;
      final venue = DiscoverPlace.fromVenue({
        'ID': 42,
        'title': 'A venue',
        'latitude': 54.0,
        'longitude': -1.0,
      })!;

      expect(track.toFeature()['id'], isNot(venue.toFeature()['id']));
      expect(track.kind, isNot(venue.kind));
    });

    test('a track with no coordinates is dropped, not pinned at zero', () {
      final json = row()
        ..['latitude'] = null
        ..['longitude'] = null;

      expect(DiscoverPlace.fromTrack(json), isNull);
    });
  });
}
