import 'package:drivelife/utils/deeplinks_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deep links are otherwise only testable by installing the app and tapping a
/// link, so the parsing rule is pinned here instead.
void main() {
  String? idFrom(String url) => DeepLinkHandler.galleryIdFrom(Uri.parse(url));

  group('galleryIdFrom', () {
    test('reads the path form the app shares', () {
      expect(idFrom('https://app.mydrivelife.com/gallery/123'), '123');
    });

    test('ignores the ?ref=share the share sheet appends', () {
      expect(
        idFrom('https://app.mydrivelife.com/gallery/123?ref=share'),
        '123',
      );
    });

    test('reads the query form', () {
      expect(idFrom('https://app.mydrivelife.com/?dl-gallery=456'), '456');
    });

    test('the query form wins when both are present', () {
      expect(idFrom('https://app.mydrivelife.com/gallery/1?dl-gallery=2'), '2');
    });

    test('handles params glued onto the path segment', () {
      // Links built by hand sometimes arrive like this.
      expect(idFrom('https://app.mydrivelife.com/gallery/789&utm=x'), '789');
    });

    group('returns null for', () {
      test('another entity', () {
        expect(idFrom('https://app.mydrivelife.com/event/123'), isNull);
        expect(idFrom('https://app.mydrivelife.com/post/123'), isNull);
      });

      test('a bare gallery path with no id', () {
        expect(idFrom('https://app.mydrivelife.com/gallery'), isNull);
        expect(idFrom('https://app.mydrivelife.com/gallery/'), isNull);
      });

      test('a deeper path that merely contains gallery', () {
        expect(idFrom('https://app.mydrivelife.com/x/gallery/123'), isNull);
      });

      test('an empty query value', () {
        expect(idFrom('https://app.mydrivelife.com/?dl-gallery='), isNull);
      });

      test('an unrelated link', () {
        expect(idFrom('https://app.mydrivelife.com/?qr=0C013CE0'), isNull);
      });
    });
  });
}
