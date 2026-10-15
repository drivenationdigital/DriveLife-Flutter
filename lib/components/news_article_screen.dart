import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// A news article, read full screen.
///
/// Laid out as an article rather than as a post: the category and date sit
/// above a large headline, the standfirst below it, then the byline, then the
/// picture with its credit, then the body. That order is what the design
/// asks for and it is also how a reader expects to meet a story — what it is
/// and when, then what it says, then who says so.
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

  /// "Industry", "Reviews" — shown as a pill above the headline.
  final String? category;

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
    this.category,
    this.excerpt,
    this.imageCaption,
    this.readMinutes,
    this.articleUrl,
  });

  @override
  State<NewsArticleScreen> createState() => _NewsArticleScreenState();
}

class _NewsArticleScreenState extends State<NewsArticleScreen> {
  static const Color _gold = Color(0xFFAE9159);
  static const Color _ink = Color(0xFF111111);
  static const Color _muted = Color(0xFF8A8A8E);

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

  Future<void> _share() async {
    final url = widget.articleUrl;
    if (url == null || url.trim().isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: '${widget.title}\n\n$url'),
    );
  }

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
                  _byline(),
                  if (widget.imageUrls.isNotEmpty) _hero(context),
                  if (widget.imageCaption != null) _credit(),
                  _body(),
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
          // The logo rather than the word "NEWS": the article says what it
          // is in its own category pill a few pixels below, and saying it
          // twice tells the reader nothing the second time.
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
  Widget _meta() {
    final minutes = widget.readMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          if (widget.category != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.category!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: _gold,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
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
        ],
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
  Widget _hero(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return CachedNetworkImage(
      imageUrl: widget.imageUrls.first,
      width: width,
      fit: BoxFit.cover,
      // Capped at the screen's own width. A press photo is often 2000px
      // wide, which decodes to around 16MB uncapped.
      memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
      placeholder: (_, _) =>
          Container(height: width * 0.62, color: const Color(0xFFF2F2F2)),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
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
        data: widget.htmlContent,
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
