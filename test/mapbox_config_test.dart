import 'dart:convert';
import 'dart:io';

import 'package:drivelife/config/mapbox_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for reading the Mapbox token.
///
/// The token lives in one gitignored file, `assets/config/mapbox.json`, read
/// at runtime. Everything here is about failing in a way that says what to
/// fix, rather than handing the Maps SDK something it will reject and leaving
/// a blank grey rectangle to diagnose.
void main() {
  group('parseToken', () {
    test('reads a public token', () {
      expect(
        MapboxConfig.parseToken('{"accessToken": "pk.abc123"}'),
        'pk.abc123',
      );
    });

    test('trims surrounding whitespace', () {
      // Pasting a token out of the Mapbox dashboard tends to bring a newline.
      expect(
        MapboxConfig.parseToken('{"accessToken": "  pk.abc123\\n"}'),
        'pk.abc123',
      );
    });

    test('refuses the committed placeholder', () {
      // On a fresh clone the example file is the only thing in the directory
      // and it starts with 'pk.' like a real one. Accepting it would start
      // the SDK with a token Mapbox rejects.
      expect(
        MapboxConfig.parseToken(
          '{"accessToken": "pk.replace_this_with_your_public_mapbox_token"}',
        ),
        isNull,
      );
    });

    test('refuses a secret token', () {
      // An sk. token is not needed, would be readable by anyone with the
      // APK, and carries account scopes a map has no business holding.
      expect(MapboxConfig.parseToken('{"accessToken": "sk.abc123"}'), isNull);
    });

    test('survives a file that is not JSON', () {
      expect(MapboxConfig.parseToken('pk.abc123'), isNull);
      expect(MapboxConfig.parseToken(''), isNull);
      expect(MapboxConfig.parseToken('{ oops'), isNull);
    });

    test('survives JSON of the wrong shape', () {
      expect(MapboxConfig.parseToken('["pk.abc123"]'), isNull);
      expect(MapboxConfig.parseToken('{"token": "pk.abc123"}'), isNull);
      expect(MapboxConfig.parseToken('{"accessToken": null}'), isNull);
      expect(MapboxConfig.parseToken('{"accessToken": 42}'), isNull);
    });
  });

  group('the committed example', () {
    final example = File('assets/config/mapbox.example.json');

    test('exists, so the asset directory survives a fresh clone', () {
      // pubspec declares the directory rather than the file. If the directory
      // were empty, a clone with no real mapbox.json would fail to build.
      expect(
        example.existsSync(),
        isTrue,
        reason: 'assets/config/mapbox.example.json must stay committed',
      );
    });

    test('is valid JSON of the shape the app reads', () {
      final decoded = jsonDecode(example.readAsStringSync());
      expect(decoded, isA<Map>());
      expect((decoded as Map).containsKey('accessToken'), isTrue);
    });

    test('is not mistaken for a real token', () {
      expect(MapboxConfig.parseToken(example.readAsStringSync()), isNull);
    });
  });

  group('the real token file', () {
    final real = File('assets/config/mapbox.json');

    test('is gitignored', () {
      final ignore = File('.gitignore').readAsStringSync();
      expect(
        ignore.contains('assets/config/mapbox.json'),
        isTrue,
        reason: 'the real token must never be committable',
      );
    });

    test('if present, holds something the app can actually use', () {
      // Skipped on a machine that has not been set up. Where it does exist, a
      // token the app will silently reject is worth catching here rather than
      // at the point someone opens Discover in a release build.
      if (!real.existsSync()) return;

      expect(
        MapboxConfig.parseToken(real.readAsStringSync()),
        isNotNull,
        reason: 'assets/config/mapbox.json exists but has no usable pk. token',
      );
    });
  });
}
