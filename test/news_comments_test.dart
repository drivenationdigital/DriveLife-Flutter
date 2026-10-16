import 'package:drivelife/components/news_comments.dart';
import 'package:flutter_test/flutter_test.dart';

/// The count shown at the top of a news article.
///
/// The endpoint nests replies inside their parent, so the length of the list
/// is not the number anyone means by "12 comments" — an article with one
/// comment and eleven replies to it would have read as 1.
void main() {
  Map<String, dynamic> comment(String text, {List<dynamic>? replies}) => {
    'id': text.hashCode,
    'comment': text,
    if (replies != null) 'replies': replies,
  };

  test('counts nothing as nothing', () {
    expect(newsCommentTotal(const []), 0);
  });

  test('counts top-level comments', () {
    expect(newsCommentTotal([comment('a'), comment('b')]), 2);
  });

  test('counts replies too', () {
    final comments = [
      comment('a', replies: [comment('a1'), comment('a2')]),
      comment('b'),
      comment('c', replies: [comment('c1')]),
    ];

    expect(newsCommentTotal(comments), 6);
  });

  test('ignores an empty replies list', () {
    expect(newsCommentTotal([comment('a', replies: const [])]), 1);
  });

  test('skips anything that is not a comment', () {
    // The endpoint has more than one shape in the wild, and a stray null in
    // the list should cost a count, not a crash.
    expect(newsCommentTotal([comment('a'), null, 'nonsense', 7]), 1);
  });

  test('survives replies arriving as something other than a list', () {
    expect(
      newsCommentTotal([
        {'id': 1, 'replies': 'two'},
      ]),
      1,
    );
  });

  group('the count shown in the header', () {
    test('is nothing at all until there is a number worth showing', () {
      // Rather than 0. An article that turns out to have seven comments
      // would otherwise show 0 for as long as the fetch takes and then
      // jump, which reads as a bug rather than as loading.
      final controller = NewsCommentsController(postId: '-1');

      expect(controller.total, isNull);
      expect(controller.loading, isTrue);
    });

    test('starts from what the feed already said', () {
      // The feed sends a count with every news post, so the header has a
      // number from the first frame and only corrects it if it was wrong.
      final controller = NewsCommentsController(postId: '-1', seed: 4);

      expect(controller.total, 4);
    });

    test('shows a seeded zero, because zero is an answer', () {
      final controller = NewsCommentsController(postId: '-1', seed: 0);

      expect(controller.total, 0);
    });
  });
}
