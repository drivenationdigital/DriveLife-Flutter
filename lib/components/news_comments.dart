import 'package:flutter/material.dart';

import '../api/interactions_api.dart';
import '../screens/comments_bottom_sheet.dart';
import '../widgets/comment_item.dart';

/// How many comments a thread holds, replies included.
///
/// The endpoint returns top-level comments with their replies nested, so the
/// length of the list is not the number a reader means by "12 comments" —
/// a story with one comment and eleven replies would read as 1. Anything
/// that is not a comment-shaped map is skipped rather than counted.
int newsCommentTotal(List<dynamic> comments) {
  var total = 0;

  for (final c in comments) {
    if (c is! Map) continue;
    total++;

    final replies = c['replies'];
    if (replies is List) total += replies.length;
  }

  return total;
}

/// The comments on one news article, held by the screen rather than by the
/// widget that draws them.
///
/// It lives up here because two places need it and only one of them is
/// reliably on screen. The count sits in the header, which is always built;
/// the thread sits at the foot of the article, which a lazily built list has
/// not created until the reader gets near it. A header that asked the foot
/// of the article for the count — or for a way to open the sheet — would
/// find nothing there on a long story.
class NewsCommentsController extends ChangeNotifier {
  /// The article's feed id — negative, as the news payload carries it.
  ///
  /// News articles are not rows in `ce_social_posts`; they live on the other
  /// site and pass through the feed. Comments key off this id, which is why
  /// the server lets a negative one through where it would otherwise insist
  /// the post exists. See dl_comment_is_news() in comments.php.
  final String postId;

  List<dynamic> _comments = const [];
  bool _loading = true;
  bool _disposed = false;

  NewsCommentsController({required this.postId, int? seed})
    : _total = seed ?? 0,
      _seeded = seed != null;

  int _total;
  final bool _seeded;

  List<dynamic> get comments => _comments;
  bool get loading => _loading;

  /// Null until there is a number worth showing — either the one the feed
  /// sent with the article or the one the thread actually came back with.
  /// A count that starts at 0 and jumps to 7 reads as a bug.
  int? get total => _loading && !_seeded ? null : _total;

  Future<void> load() async {
    final response = await InteractionsAPI.fetchComments(postId);
    if (_disposed) return;

    _comments = response.comments;
    _total = newsCommentTotal(_comments);
    _loading = false;
    notifyListeners();
  }

  /// The full thread, in the sheet the rest of the app uses.
  ///
  /// Reloads on the way back, so the count in the header and the preview at
  /// the foot of the article both reflect anything just written.
  Future<void> open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => CommentsBottomSheet(
          scrollController: scrollController,
          postId: postId,
        ),
      ),
    );

    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The comments at the foot of a news article.
///
/// A preview, not a second implementation. The first few are shown in place
/// so the article ends somewhere rather than stopping dead, and anything
/// past reading — replying, liking, deleting, tagging, GIFs — opens the one
/// [CommentsBottomSheet] the rest of the app already uses. A parallel
/// comment UI here would mean two of everything, and the second one would be
/// the one that fell behind.
class NewsComments extends StatelessWidget {
  final NewsCommentsController controller;

  const NewsComments({super.key, required this.controller});

  static const Color _ink = Color(0xFF111111);
  static const Color _muted = Color(0xFF8A8A8E);
  static const Color _gold = Color(0xFFAE9159);

  /// How many are shown before the reader is sent to the sheet. Three is
  /// enough to show that a conversation exists without turning the end of
  /// the article into a comment thread.
  static const int _preview = 3;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final comments = controller.comments;
        final total = controller.total;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total == null || total == 0 ? 'Comments' : 'Comments ($total)',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 12),
              if (controller.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (comments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'No comments yet.',
                    style: TextStyle(fontSize: 14, color: _muted),
                  ),
                )
              else
                // Read-only: no reply or delete handler, because both belong
                // to the sheet, where there is a composer to reply into.
                ...comments
                    .take(_preview)
                    .whereType<Map<String, dynamic>>()
                    .map((c) => CommentItem(comment: c)),
              const SizedBox(height: 8),
              _button(context, comments, total),
            ],
          ),
        );
      },
    );
  }

  Widget _button(BuildContext context, List<dynamic> comments, int? total) {
    final label = comments.isEmpty
        ? 'Be the first to comment'
        : comments.length > _preview
        ? 'View all $total comments'
        : 'Add a comment';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: controller.loading ? null : () => controller.open(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFE4E4E4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 17,
              color: _gold,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
