import 'package:drivelife/widgets/share/shared_post_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parser is the whole of how a shared post is recognised in a chat,
/// so the cases that matter are the ones where it must NOT fire: a link
/// to somewhere else, and a message that merely mentions a post.
void main() {
  group('finds a shared post', () {
    test('a bare post link', () {
      final link = SharedPostLink.parse(
        'https://app.mydrivelife.com/post/1234?ref=share',
      );

      expect(link, isNotNull);
      expect(link!.kind, 'post');
      expect(link.id, '1234');
      expect(link.isEvent, isFalse);
      // The query string is eaten, not left behind as a note.
      expect(link.note, '');
    });

    test('an event link', () {
      final link = SharedPostLink.parse(
        'https://app.mydrivelife.com/event/99?ref=share',
      );

      expect(link!.kind, 'event');
      expect(link.isEvent, isTrue);
      expect(link.id, '99');
    });

    test('the note is what is left once the link is removed', () {
      final link = SharedPostLink.parse(
        'look at this\nhttps://app.mydrivelife.com/post/7?ref=share',
      );

      expect(link!.id, '7');
      expect(link.note, 'look at this');
    });

    test('the blank lines the share text leaves are collapsed', () {
      final link = SharedPostLink.parse(
        'Check out this post on DriveLife by @dave.\n\n'
        'Nice wheels\n\n'
        'https://app.mydrivelife.com/post/12',
      );

      // Not three paragraphs with a hole where the link was.
      expect(link!.note.contains('\n\n'), isFalse);
      expect(link.note.endsWith('Nice wheels'), isTrue);
    });

    test('http and www both still match', () {
      expect(
        SharedPostLink.parse('http://www.app.mydrivelife.com/post/5')?.id,
        '5',
      );
    });

    test('only the first link becomes a card', () {
      final link = SharedPostLink.parse(
        'https://app.mydrivelife.com/post/1 and '
        'https://app.mydrivelife.com/post/2',
      );

      expect(link!.id, '1');
    });
  });

  group('leaves everything else alone', () {
    test('null and empty', () {
      expect(SharedPostLink.parse(null), isNull);
      expect(SharedPostLink.parse(''), isNull);
    });

    test('an ordinary message', () {
      expect(SharedPostLink.parse('have you seen his post?'), isNull);
    });

    test('ANOTHER SITE with the same path shape', () {
      // The one that matters. Without the host anchor this would render
      // a DriveLife card promising content that is not there.
      expect(
        SharedPostLink.parse('https://example.com/post/1234'),
        isNull,
      );
      expect(
        SharedPostLink.parse('https://notmydrivelife.com/post/1234'),
        isNull,
      );
    });

    test('a link with no id', () {
      expect(SharedPostLink.parse('https://app.mydrivelife.com/post/'), isNull);
    });

    test('some other DriveLife page', () {
      expect(
        SharedPostLink.parse('https://app.mydrivelife.com/profile/12'),
        isNull,
      );
    });
  });
}
