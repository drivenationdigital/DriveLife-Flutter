import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/services/posts_service.dart';
import 'package:drivelife/widgets/share/shared_post_link.dart';
import 'package:flutter/material.dart';

/// A shared post, drawn inside a chat bubble.
///
/// ── WHAT IT DOES WHEN IT CANNOT LOAD ─────────────────────────────────
///
/// Nothing. It returns an empty box and the bubble falls back to showing
/// the URL as text, which is what the message actually contains.
///
/// That matters more than it sounds. The card is a RECOGNITION of a link
/// rather than a structured attachment — see SharedPostLink — so a post
/// that was deleted, made private, or simply fails to fetch must leave
/// the message readable rather than blank. A bubble that renders nothing
/// because a fetch failed is worse than a link.
class SharedPostCard extends StatefulWidget {
  final SharedPostLink link;

  /// Light text and borders, for a card drawn on a dark surface.
  ///
  /// False everywhere today. The chat used to pass `isMe` here, because
  /// the sender's bubble is gold and the card sat inside it — but a
  /// shared post has no bubble now, so both sides draw it on the
  /// thread's own background and the light treatment is right for both.
  ///
  /// Kept because the card is a general thing and the next surface that
  /// wants one may well be dark.
  final bool onDarkBubble;

  const SharedPostCard({
    super.key,
    required this.link,
    this.onDarkBubble = false,
  });

  @override
  State<SharedPostCard> createState() => _SharedPostCardState();
}

class _SharedPostCardState extends State<SharedPostCard> {
  /// Posts already fetched, for the lifetime of the app.
  ///
  /// A chat scrolls, and every scroll rebuilds the bubbles that come
  /// back into view. Without this, scrolling past the same shared post
  /// three times is three identical requests.
  ///
  /// Keyed by id and holding null for "asked, and there was nothing
  /// there" — so a deleted post is not re-requested on every rebuild
  /// either.
  static final Map<String, Map<String, dynamic>?> _cache = {};

  Map<String, dynamic>? _post;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.link.id;

    if (_cache.containsKey(id)) {
      setState(() {
        _post = _cache[id];
        _loading = false;
      });
      return;
    }

    try {
      // PostsService, NOT PostsAPI.getPostById.
      //
      // They look interchangeable and are not. PostsAPI's version
      // builds its URL from the bare site root -- no /wp-json/app/v1 --
      // and sends no auth token, so it 404s. Nothing else in the app
      // calls it; every working caller uses this one, which is why the
      // breakage was not already known.
      //
      // It also has PostCache behind it, so a post already opened in
      // the app is not fetched again for the card.
      final post = await PostsService().getPostById(postId: id);

      _cache[id] = post;

      if (!mounted) return;

      setState(() {
        _post = post;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[SharedPostCard] $id failed: $e');

      // Cached as a miss, so a post that cannot be fetched is asked for
      // once rather than on every rebuild.
      _cache[id] = null;

      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String? get _image {
    final media = _post?['media'];

    if (media is List && media.isNotEmpty && media.first is Map) {
      final url = media.first['media_url']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }

    return null;
  }

  void _open() {
    if (widget.link.isEvent) {
      Navigator.pushNamed(
        context,
        AppRoutes.eventDetail,
        arguments: {
          'event': {'id': widget.link.id},
        },
      );
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.postDetail,
      arguments: {'postId': widget.link.id, 'highlightCommentId': null},
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── A FAILED FETCH STILL DRAWS A CARD ────────────────────────────
    //
    // This used to `return const SizedBox.shrink()` when the post could
    // not be loaded, on the reasoning that the bubble would fall back
    // to showing the URL. It does not: _bubbleText() strips the link
    // out precisely so it is not repeated under the card, so a post
    // that failed to load produced a COMPLETELY EMPTY BUBBLE.
    //
    // Nothing is drawn differently here instead — the body below
    // already degrades on its own. No image gives the placeholder icon,
    // and an empty author and caption simply do not render. What is
    // left is "Post on DriveLife", still tappable, which is both honest
    // and better than a raw URL.
    final onDark = widget.onDarkBubble;
    final border = onDark ? Colors.white24 : const Color(0xFFE2E2E2);
    final panel = onDark ? Colors.white10 : const Color(0xFFF5F5F5);
    final ink = onDark ? Colors.white : const Color(0xFF111111);
    final muted = onDark ? Colors.white70 : const Color(0xFF6B6B6B);

    final image = _image;
    final caption = _post?['caption']?.toString().trim() ?? '';
    final author = _post?['username']?.toString().trim() ?? '';

    return GestureDetector(
      onTap: _loading ? null : _open,
      child: Container(
        width: 210,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // A fixed 4:3 box whether or not there is a photo, so a card
            // does not change height when the image arrives and shove
            // the whole conversation down a line.
            AspectRatio(
              aspectRatio: 4 / 3,
              child: _loading
                  ? ColoredBox(color: border.withValues(alpha: 0.4))
                  : (image != null
                        ? CachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            // A third of a phone's width, so there is
                            // nothing to gain from decoding the full
                            // photograph into it.
                            memCacheWidth: 420,
                            placeholder: (_, _) =>
                                ColoredBox(color: border.withValues(alpha: 0.4)),
                            errorWidget: (_, _, _) => ColoredBox(
                              color: border.withValues(alpha: 0.4),
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: muted,
                                size: 22,
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: border.withValues(alpha: 0.4),
                            child: Icon(
                              widget.link.isEvent
                                  ? Icons.event
                                  : Icons.photo_outlined,
                              color: muted,
                              size: 26,
                            ),
                          )),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.link.isEvent ? 'Event on DriveLife' : 'Post on DriveLife',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: muted,
                    ),
                  ),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '@$author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, height: 1.3, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
