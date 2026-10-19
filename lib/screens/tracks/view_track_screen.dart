import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/tracks_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A track or circuit.
///
/// Built rather than reusing the venue screen, which is 2,000 lines of tabs
/// — updates, posts, galleries — none of which a track has. A track is a
/// place with a description, some ways to contact it and a list of what is
/// happening there, so that is what this shows.
///
/// It reads `app/v2/get-track`, which is its own endpoint. The first version
/// of this went through the venue endpoint and every track came back 404,
/// because that endpoint's blog locator only ever accepted `venues` posts.
class TrackDetailScreen extends StatefulWidget {
  final String trackId;

  /// Which site the track was listed on, when the caller knows. A hint only
  /// — the server checks both — but it saves a lookup on the wrong one.
  final String? site;

  const TrackDetailScreen({super.key, required this.trackId, this.site});

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  Map<String, dynamic>? _track;
  bool _loading = true;
  String? _error;
  bool _following = false;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await TracksApiService.getTrack(
        trackId: widget.trackId,
        country: widget.site,
      );
      if (!mounted) return;

      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'Could not load this track.';
        });
        return;
      }

      setState(() {
        _track = result;
        _following = result['is_following'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this track.';
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;

    // Flipped before the request and put back if it fails. A follow button
    // that does nothing until the network answers feels broken on a slow
    // connection, and this is a cheap thing to be wrong about briefly.
    final wanted = !_following;
    setState(() {
      _following = wanted;
      _followBusy = true;
    });

    final settled = await TracksApiService.toggleFollow(
      trackId: widget.trackId,
    );
    if (!mounted) return;

    setState(() {
      // The server says what it settled on, so a toggle that raced another
      // device ends up showing the truth rather than this device's guess.
      _following = settled ?? !wanted;
      _followBusy = false;
    });
  }

  Future<void> _open(String? url) async {
    if (url == null || url.trim().isEmpty) return;

    final text = url.trim();

    // mailto: and tel: are built here and arrive complete. Everything else
    // is normalised by the server, which knows that an Instagram field holds
    // a handle as often as a link — prefixing "https://" to "@croftcircuit"
    // produces an address that goes nowhere.
    final uri = Uri.tryParse(text.contains(':') ? text : 'https://$text');
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String? _text(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    return s.isEmpty ? null : s;
  }

  /// What the website shows under the title: the disciplines, then the two
  /// numbers a driver checks before booking a day.
  String? _image(dynamic value) {
    if (value is Map) return _text(value['url']);
    return _text(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Scaffold(backgroundColor: Colors.white, body: _skeleton(context));
    }

    if (_error != null || _track == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _plainBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'Could not load this track.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8A8A8E)),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }

    final track = _track!;
    final events = (track['events'] as List?) ?? const [];

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: theme.primaryColor,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            _header(track),
            SliverToBoxAdapter(child: _identity(track)),
            SliverToBoxAdapter(child: _links(track)),
            if (_text(track['description']) != null)
              SliverToBoxAdapter(child: _description(track)),
            SliverToBoxAdapter(
              child: _SectionTitle(
                events.isEmpty
                    ? 'Upcoming events'
                    : 'Upcoming events (${events.length})',
              ),
            ),
            if (events.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Text(
                    'Nothing listed here yet.',
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF8A8A8E)),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: events.length,
                itemBuilder: (context, i) => _EventRow(
                  event: Map<String, dynamic>.from(events[i] as Map),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A bare bar with a back button and no title.
  ///
  /// No "Track" written across the top. The page it belongs to carries the
  /// track's own name a few pixels below, so the word was the app telling
  /// you what kind of page you had opened, in the one spot where its name
  /// should be.
  PreferredSizeWidget _plainBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        // The chevron, not Android's arrow — what every other view page in
        // the app uses.
        icon: const Icon(CupertinoIcons.back, color: Color(0xFF1C1C1E)),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  /// The page's own shape, in grey, while it loads.
  ///
  /// A spinner on an empty page says only that something is happening. This
  /// says what is coming — a cover photo, a badge over it, a name, an
  /// address, a button — so the real thing arriving is a page filling in
  /// rather than a page replacing another.
  ///
  /// Laid out to the same numbers as [_header] and [_identity]: a skeleton
  /// whose blocks sit somewhere other than the content's is worse than no
  /// skeleton, because everything jumps at the moment it loads.
  Widget _skeleton(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    Widget block(double w, double h, {double radius = 6}) => Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );

    return Stack(
      children: [
        SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The cover, and the badge hanging off the bottom of it — the
              // 220 + 52 the real header measures.
              SizedBox(
                height: 272,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: block(width, 220, radius: 0),
                    ),
                    block(104, 104, radius: 22),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Center(child: block(width * 0.6, 26)),
              const SizedBox(height: 12),
              Center(child: block(width * 0.75, 15)),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: block(width, 48, radius: 14),
              ),

              const SizedBox(height: 20),

              // The contact chips.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    block(110, 44, radius: 22),
                    const SizedBox(width: 10),
                    block(96, 44, radius: 22),
                    const SizedBox(width: 10),
                    block(90, 44, radius: 22),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // And the first few lines of whatever it says about itself.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(140, 18),
                    const SizedBox(height: 14),
                    block(width, 13),
                    const SizedBox(height: 10),
                    block(width, 13),
                    const SizedBox(height: 10),
                    block(width * 0.7, 13),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Over the cover, where the real one sits.
        Positioned(
          top: MediaQuery.viewPaddingOf(context).top,
          left: 0,
          child: IconButton(
            icon: const Icon(CupertinoIcons.back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }

  Widget _header(Map<String, dynamic> track) {
    final cover = _image(track['cover_photo']);
    final logo = _image(track['logo']);

    return SliverAppBar(
      // Room for the logo to hang below the photograph without the name
      // starting underneath it. The cover is 220 and the badge overhangs by
      // half of its 104, so the bar is 220 + 52.
      expandedHeight: 272,
      leading: IconButton(
        icon: const Icon(CupertinoIcons.back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      pinned: true,
      backgroundColor: Colors.white,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                // A cover photo is full-bleed, so cap the decode at the
                // screen's own width rather than the source's.
                memCacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF1C1C1E)),
              )
            else
              const ColoredBox(color: Color(0xFF1C1C1E)),

            // Keeps the back arrow and the title legible over a photo that
            // might be any colour at all.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                  stops: [0, 0.45],
                ),
              ),
            ),

            // White below the photo, so the overhanging logo sits on the
            // page rather than on a strip of cover photo stretched to fill
            // the extra height.
            const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 52,
                child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox.expand(),
                ),
              ),
            ),

            if (logo != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 104,
                  height: 104,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.cover,
                      memCacheWidth:
                          (104 * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Name, where it is, and one button.
  ///
  /// The logo is not here any more — it sits in [_header], overlapping the
  /// bottom of the cover photo, which is where a venue's is. Two pages for
  /// the same kind of place should not put the same badge in two different
  /// positions.
  Widget _identity(Map<String, dynamic> track) {
    final location = _text(track['location']);

    return Padding(
      // Only 8 at the top: the logo overhangs the cover by half its height
      // and this block starts underneath it.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _text(track['title']) ?? 'Track',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: Color(0xFF1C1C1E),
            ),
          ),

          // No discipline badges and no pin beside the address.
          //
          // The badges repeated what the track types section further down
          // already lists, and the pin said what an address says by being
          // an address. Between them they filled the space under the name
          // that the name wants.
          if (location != null) ...[
            const SizedBox(height: 8),
            Text(
              location,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Color(0xFF8A8A8E),
              ),
            ),
          ],

          const SizedBox(height: 16),

          _FollowButton(
            following: _following,
            busy: _followBusy,
            onTap: _toggleFollow,
          ),
        ],
      ),
    );
  }

  /// How many follow this track, or null when the API did not say.
  ///
  /// Unused while the count is hidden from the profile — see _identity.
  /// Kept rather than deleted because hiding it was a "for now".
  ///
  /// The field has been spelled both ways over the life of the endpoint, so
  /// both are accepted rather than the count quietly disappearing.
  // ignore: unused_element
  static int? _followerCount(Map<String, dynamic> track) {
    final raw = track['follower_count'] ?? track['followers_count'];

    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());

    return null;
  }

  /// 2418 as "2,418". Written out rather than pulled from intl, which this
  /// screen does not otherwise need and which is a lot of locale data to
  /// carry for one separator.
  /// Unused while the follower count is hidden. See _followerCount.
  // ignore: unused_element
  static String _grouped(int value) {
    final digits = value.toString();
    final out = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }

    return out.toString();
  }

  Widget _links(Map<String, dynamic> track) {
    // Only what this track actually has. A row of dead icons says less than
    // no row at all.
    final links = <(IconData, String, String?)>[
      (Icons.language_rounded, 'Website', _text(track['website'])),
      (Icons.mail_outline_rounded, 'Email', _text(track['email'])),
      (Icons.call_outlined, 'Call', _text(track['phone'])),
      (Icons.facebook_rounded, 'Facebook', _text(track['facebook'])),
      (Icons.camera_alt_outlined, 'Instagram', _text(track['instagram'])),
    ].where((l) => l.$3 != null).toList();

    if (links.isEmpty) return const SizedBox(height: 16);

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        itemCount: links.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (icon, label, value) = links[i];
          return _LinkChip(
            icon: icon,
            label: label,
            onTap: () => _open(
              label == 'Email'
                  ? 'mailto:$value'
                  : label == 'Call'
                  ? 'tel:$value'
                  : value,
            ),
          );
        },
      ),
    );
  }

  Widget _description(Map<String, dynamic> track) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('About', padded: false),
          const SizedBox(height: 6),
          // The field is a WYSIWYG, so it arrives as HTML — same renderer
          // the venue screen uses, so the two read alike.
          Html(
            data: '${track['description']}',
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(14.5),
                lineHeight: const LineHeight(1.6),
                color: const Color(0xFF4A4A4F),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final bool padded;

  const _SectionTitle(this.text, {this.padded = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padded
          ? const EdgeInsets.fromLTRB(20, 24, 20, 8)
          : EdgeInsets.zero,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1C1C1E),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool following;
  final bool busy;
  final VoidCallback onTap;

  const _FollowButton({
    required this.following,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: following
            ? const Color(0xFFF2F2F2)
            : const Color(0xFF1C1C1E),
        foregroundColor: following ? const Color(0xFF1C1C1E) : Colors.white,
        // Full width now, so the padding sets the height and the stretch
        // above sets the width.
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (following) ...[
            const Icon(Icons.check_rounded, size: 17),
            const SizedBox(width: 6),
          ],
          Text(
            following ? 'Following' : 'Follow',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: const Color(0xFF1C1C1E)),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8E)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final thumb = '${event['thumbnail'] ?? ''}'.trim();

    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/event-detail',
        arguments: {'event': event},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 58,
                height: 58,
                child: thumb.isEmpty
                    ? const ColoredBox(color: Color(0xFFF2F2F2))
                    : CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        memCacheWidth:
                            (58 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: Color(0xFFF2F2F2)),
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
                    '${event['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event['start_date'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A8A8E),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFC4C4C6),
            ),
          ],
        ),
      ),
    );
  }
}
