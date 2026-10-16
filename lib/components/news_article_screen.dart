import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/html_text.dart';

import 'news_comments.dart';

/// A news article, read full screen.
///
/// Laid out as an article rather than as a post: the date, read time and a
/// shortcut to the comments sit above a large headline, the standfirst below
/// it, then the picture with its credit, then the body, then the byline, and
/// the comments last. That is how a reader meets a story — what it is and
/// when, then what it says, then who said so and what everyone made of it.
///
/// A route rather than a bottom sheet. A sheet that opens at 95% is a page
/// wearing a disguise: it leaves a strip of feed showing at the top, it can
/// be dragged half shut mid-paragraph, and it gets none of the things a page
/// gets for free — the back gesture, a predictable place in the history, and
/// a status bar that belongs to it.
class NewsArticleScreen extends StatefulWidget {
  final String title;
  final String htmlContent;
  final String date;
  final List<String> imageUrls;
  final String? creatorProfileImage;
  final String? username;
  final bool? isVerified;
  final String? postUserId;

  /// The article's feed id — negative, as news posts carry it. Comments
  /// hang off it. Null leaves the article with no comments section, which is
  /// what anything opening this screen without an id should get.
  final String? postId;

  /// How many comments the feed said there were, used only until the real
  /// list loads. Saves the shortcut at the top from appearing a moment late.
  final int? commentsCount;

  /// The standfirst under the headline. The article's own excerpt.
  final String? excerpt;

  /// The photographer's credit, under the picture. Often the only place an
  /// attribution licence is satisfied, so it is shown whenever it exists.
  final String? imageCaption;

  /// Whole minutes, worked out from the article's length.
  final int? readMinutes;

  /// Where the article lives, for sharing. The feed's own share URL is built
  /// from a post id, and an article has none here.
  final String? articleUrl;

  const NewsArticleScreen({
    super.key,
    required this.title,
    required this.htmlContent,
    required this.date,
    required this.imageUrls,
    this.creatorProfileImage,
    this.username,
    this.isVerified,
    this.postUserId,
    this.postId,
    this.commentsCount,
    this.excerpt,
    this.imageCaption,
    this.readMinutes,
    this.articleUrl,
  });

  @override
  State<NewsArticleScreen> createState() => _NewsArticleScreenState();
}

class _NewsArticleScreenState extends State<NewsArticleScreen> {
  /// The hero frame's height, as a fraction of the screen's width.
  static const double _heroRatio = 0.62;

  /// What the blurred backdrop is decoded to. The feed card uses the same
  /// number for the same reason — see _blurDecodeWidth in post_card.dart.
  static const int _blurDecodeWidth = 64;

  static const Color _gold = Color(0xFFAE9159);
  static const Color _ink = Color(0xFF111111);
  static const Color _muted = Color(0xFF8A8A8E);

  /// Null when the article arrived without an id, which is the one case
  /// where it cannot be commented on.
  NewsCommentsController? _comments;

  bool get _hasComments => _comments != null;

  @override
  void initState() {
    super.initState();

    final postId = widget.postId?.trim();
    if (postId == null || postId.isEmpty) return;

    _comments = NewsCommentsController(
      postId: postId,
      seed: widget.commentsCount,
    )..load();
  }

  @override
  void dispose() {
    _comments?.dispose();
    super.dispose();
  }

  /// "14 Oct 2026". Falls back to whatever it was given, because a date that
  /// will not parse is still more use than an empty space.
  String get _date {
    try {
      final parsed = DateTime.parse(widget.date);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
    } catch (_) {
      return widget.date;
    }
  }

  /// The author's initials, for the avatar when there is no picture.
  String get _initials {
    final name = (widget.username ?? '').trim();
    if (name.isEmpty) return 'DL';

    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'DL';
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return (words.first.substring(0, 1) + words.elementAt(1).substring(0, 1))
        .toUpperCase();
  }

  /// Shares the article as a URL rather than as a line of text.
  ///
  /// `uri` and `text` do different things. Text is a string that happens to
  /// contain a link: it is offered to anything that takes text, the preview
  /// is the first few words, and the recipient gets a headline followed by a
  /// bare address. A `uri` is handed over as a web page — iOS fetches it,
  /// pulls out the title and the site's icon, and both the share sheet and
  /// the message show a card for the article. The two cannot be combined, so
  /// the headline rides along as the subject, which is what mail and the
  /// Android chooser use.
  Future<void> _share() async {
    final raw = widget.articleUrl?.trim();
    if (raw == null || raw.isEmpty) return;

    final uri = Uri.tryParse(raw);
    final isLink = uri != null && uri.hasScheme;
    final box = context.findRenderObject() as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        uri: isLink ? uri : null,
        // A link that will not parse is still worth sending as text.
        text: isLink ? null : '${widget.title}\n\n$raw',
        subject: widget.title,
        title: widget.title,
        // iPad anchors the sheet to this. Without it the share pops from
        // the top-left corner, and on some iPadOS versions it throws.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// Opens the thread from the shortcut at the top.
  ///
  /// It opens the sheet rather than scrolling down to the section at the
  /// foot of the article. Scrolling there would mean a long journey past
  /// the whole story to reach it, and on a long article the section has not
  /// been built yet, so there would be nothing to scroll to.
  void _toComments() => _comments?.open(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // top only: the article runs to the bottom edge, and the list adds
        // the home-indicator inset to its own padding so the last paragraph
        // is not sitting under it.
        bottom: false,
        child: Column(
          children: [
            _bar(context),
            const Divider(height: 1, color: Color(0xFFEFEFEF)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 32,
                ),
                children: [
                  _meta(),
                  _headline(),
                  if (widget.excerpt != null) _standfirst(),
                  if (widget.imageUrls.isNotEmpty) _hero(context),
                  if (widget.imageCaption != null) _credit(),
                  _body(),
                  // Last, under the article and whatever sources it ends
                  // with. Who filed a story is worth knowing once you have
                  // read it; above the picture it only delayed the reading.
                  const Divider(
                    height: 36,
                    thickness: 1,
                    indent: 20,
                    endIndent: 20,
                    color: Color(0xFFEFEFEF),
                  ),
                  _byline(),
                  if (_comments != null) NewsComments(controller: _comments!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Back, title, share — a page header, not a sheet handle.
  Widget _bar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _circleButton(
            Icons.chevron_left_rounded,
            () => Navigator.of(context).pop(),
          ),
          // The logo rather than the word "NEWS". It is a masthead, and a
          // reader who has just tapped a news card does not need telling
          // again what they opened.
          Expanded(
            child: Center(
              child: Image.asset('assets/logo-dark.png', height: 18),
            ),
          ),
          // Kept in the layout when there is nothing to share, so the title
          // stays centred rather than shifting.
          Opacity(
            opacity: widget.articleUrl == null ? 0 : 1,
            child: _circleButton(
              Icons.ios_share_rounded,
              widget.articleUrl == null ? null : _share,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback? onTap) {
    return Material(
      color: const Color(0xFFF4F4F4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: _ink),
        ),
      ),
    );
  }

  /// Category, date and reading time.
  /// The line above the headline: when it ran, how long it takes, and a way
  /// straight to the comments.
  ///
  /// No category pill. Every article on the feed came back tagged
  /// "Industry", so the pill said the same thing on every story and earned
  /// none of the space it took above the headline.
  Widget _meta() {
    final minutes = widget.readMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              minutes == null ? _date : '$_date  ·  $minutes min read',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
          ),
          if (_hasComments) ...[const SizedBox(width: 12), _commentsShortcut()],
        ],
      ),
    );
  }

  /// The comment count at the top, which scrolls to the thread at the foot.
  ///
  /// A count and a jump rather than a second composer: a reader who wants to
  /// see what people said should not have to thumb through the article to
  /// find out, but the comments themselves belong after it.
  Widget _commentsShortcut() {
    final controller = _comments!;

    return Material(
      color: const Color(0xFFF4F4F4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _toComments,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 14,
                color: _ink,
              ),
              const SizedBox(width: 5),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Text(
                  controller.total == null ? 'Comments' : '${controller.total}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 27,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: _ink,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _standfirst() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Text(
        widget.excerpt!,
        style: const TextStyle(
          fontSize: 16.5,
          height: 1.45,
          color: Color(0xFF3C3C40),
        ),
      ),
    );
  }

  Widget _byline() {
    final image = widget.creatorProfileImage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: _ink,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: image == null || image.isEmpty
                ? Center(
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _gold,
                      ),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.cover,
                    memCacheWidth: (44 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorWidget: (_, _, _) => Center(
                      child: Text(
                        _initials,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _gold,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.username ?? 'DriveLife',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'News Desk',
                  style: TextStyle(fontSize: 13.5, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full-bleed, as the design has it — the picture is the one thing that
  /// should not be inset to the text column.
  /// The picture, in a frame of a fixed height with a blurred copy of
  /// itself behind it — the same construction the feed card uses, so the
  /// photograph looks the same before and after the tap.
  ///
  /// The frame is what stops the page jumping. It used to be a plain
  /// cover-fitted image with no height of its own, so the article laid out
  /// twice: once around a placeholder of a guessed height, and again around
  /// the real picture's aspect ratio when it arrived. Everything below the
  /// image moved, which on a slow connection happened several seconds into
  /// reading.
  ///
  /// The ClipRect is not optional. A blur paints outside the bounds of what
  /// it is blurring — that is what a blur is — and a Stack only clips
  /// children whose LAYOUT overflows, not their paint. Without it the
  /// backdrop bleeds up into the standfirst and down into the caption. The
  /// feed card gets away with the same Stack because the PageView it sits
  /// in clips the whole page.
  Widget _hero(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final url = widget.imageUrls.first;

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: ClipRect(
        child: SizedBox(
          width: width,
          // The height the placeholder always claimed. Keeping it means the
          // page is laid out once, and nothing moves when the picture lands.
          height: width * _heroRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.grey.shade200),

              // The backdrop. Decoded tiny on purpose: it is blurred past
              // recognition before anyone sees it, so resolution buys
              // nothing, and this is the same photograph being decoded a
              // second time.
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: _blurDecodeWidth,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),

              // The photograph itself, whole.
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  // Capped at the screen's own width. A press photo is
                  // often 2000px wide, which decodes to around 16MB
                  // uncapped.
                  memCacheWidth:
                      (width * MediaQuery.devicePixelRatioOf(context)).round(),
                  // Nothing: the blurred backdrop is already the
                  // placeholder, and a grey box over it would only flash.
                  placeholder: (_, _) => const SizedBox.shrink(),
                  fadeInDuration: const Duration(milliseconds: 180),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credit() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        widget.imageCaption!,
        style: const TextStyle(fontSize: 13, height: 1.4, color: _muted),
      ),
    );
  }

  Widget _body() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Html(
        // Same treatment as a venue description, for the same reason: a
        // venue page went down inside flutter_html's CSS parser over a
        // style attribute pasted out of a word processor, and these
        // articles come from the same kind of editor. The style map below
        // is this screen's own idea of how an article should read.
        data: withoutInlineStyles(widget.htmlContent),
        onLinkTap: (url, _, _) async {
          if (url == null) return;
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        style: {
          'body': Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            fontSize: FontSize(16),
            lineHeight: const LineHeight(1.6),
            color: const Color(0xFF26262A),
          ),
          'p': Style(margin: Margins.only(bottom: 16)),
          'h2': Style(
            fontSize: FontSize(19),
            fontWeight: FontWeight.w700,
            margin: Margins.only(top: 8, bottom: 10),
            color: _ink,
          ),
          'h3': Style(
            fontSize: FontSize(17),
            fontWeight: FontWeight.w700,
            margin: Margins.only(top: 8, bottom: 8),
            color: _ink,
          ),
          'a': Style(color: _gold, textDecoration: TextDecoration.none),
          'img': Style(margin: Margins.symmetric(vertical: 8)),
          'figcaption': Style(fontSize: FontSize(13), color: _muted),
        },
      ),
    );
  }
}
