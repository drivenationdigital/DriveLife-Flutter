import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/tracks_api.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/widgets/media/entity_galleries_tab.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
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

class _TrackDetailScreenState extends State<TrackDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _track;
  bool _loading = true;
  String? _error;
  bool _following = false;
  bool _followBusy = false;

  /// About, Events, Community, Media — the same four a venue has, in the
  /// same order, because they are the same kind of page.
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    attachTabHaptics(_tabs);
    _load();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            // The panels are separate scroll views, so a sideways swipe
            // between them would carry the cover photo with it. The bar
            // below is how you change tab.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _aboutPanel(theme, track),
              _eventsPanel(theme, track),
              _TrackCommunityFeed(
                trackId: widget.trackId,
                title: _text(track['title']) ?? 'Track',
                onCompose: _composeTrackPost,
                refreshToken: _communityRefresh,
                bottomInset: _panelBottomInset(context),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              // Galleries hang off a generic (entity_type, entity_id)
              // pair, so a track is the same shape as a venue to them —
              // see dl_gallery_entity_types() in php-api/helpers.php.
              Column(
                children: [
                  _compactBarBox(),
                  Expanded(
                    child: EntityGalleriesTab(
                      entityId: widget.trackId,
                      entityType: 'track',
                      primaryColor: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),

          Positioned(left: 0, right: 0, bottom: 0, child: _bottomTabBar(theme)),
        ],
      ),
    );
  }

  /// Everything about the track itself: the cover, the badge, the name, the
  /// contacts and whatever it says about itself.
  Widget _aboutPanel(ThemeProvider theme, Map<String, dynamic> track) {
    return RefreshIndicator(
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
            child: SizedBox(height: _panelBottomInset(context)),
          ),
        ],
      ),
    );
  }

  /// What is on at the track.
  Widget _eventsPanel(ThemeProvider theme, Map<String, dynamic> track) {
    final events = (track['events'] as List?) ?? const [];

    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          _compactBar(track),
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
              itemBuilder: (context, i) =>
                  _EventRow(event: Map<String, dynamic>.from(events[i] as Map)),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: _panelBottomInset(context)),
          ),
        ],
      ),
    );
  }

  /// Room under a panel for the floating tab bar, so the last row is not
  /// sitting behind it.
  double _panelBottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 84;

  /// The slim bar the tabs other than About get, in place of the cover.
  ///
  /// The cover and the badge belong to the track, not to one tab, and
  /// repeating them above every panel would mean scrolling past the same
  /// 270 pixels to reach each one.
  Widget _compactBar(Map<String, dynamic> track) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(CupertinoIcons.back, color: Color(0xFF1C1C1E)),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        _text(track['title']) ?? 'Track',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1C1C1E),
        ),
      ),
    );
  }

  /// The same bar for the panels that are not scroll views.
  Widget _compactBarBox() {
    final track = _track ?? const <String, dynamic>{};

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.back, color: Color(0xFF1C1C1E)),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                _text(track['title']) ?? 'Track',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  /// The floating pill bar. The same one a venue carries.
  Widget _bottomTabBar(ThemeProvider theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _tabPill(label: 'About', index: 0),
              _tabPill(label: 'Events', index: 1),
              _tabPill(label: 'Community', index: 2),
              _tabPill(label: 'Media', index: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabPill({required String label, required int index}) {
    final isActive = _tabs.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _tabs.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFC4A062) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFFC4A062).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF8A8A8E),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
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

  /// Redraws the bar and swaps the panel. The segmented nav below is not
  /// a TabBar, so nothing repaints it unless this does.
  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// Bumped when the track's feed should reload — a post just composed.
  /// The feed is a child with its own paging, so it watches this number
  /// rather than this screen reaching into its state.
  int _communityRefresh = 0;

  /// Opens the composer with this track as the post's home.
  Future<void> _composeTrackPost() async {
    final track = _track;
    if (track == null) return;

    final result = await Navigator.pushNamed(
      context,
      '/create-post',
      arguments: {
        'association_id': widget.trackId,
        'association_type': 'track',
        'association_label': _text(track['title']) ?? '',
      },
    );

    if (result == true && mounted) {
      setState(() => _communityRefresh++);
    }
  }

  Widget _header(Map<String, dynamic> track) {
    final cover = _image(track['cover_photo']);
    final logo = _image(track['logo']);

    // The status bar's height, kept out of the photograph.
    //
    // A SliverAppBar's flexibleSpace paints the whole way to the top of the
    // screen, so the cover ran under the clock and the wifi icon. Those are
    // drawn dark, because this bar's backgroundColor is white, which left
    // them unreadable over anything but a pale photo — and a venue does not
    // do this, its header sits inside a SafeArea. Giving the strip back to
    // the page keeps the phone's own furniture legible on both.
    final topInset = MediaQuery.paddingOf(context).top;

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
        background: Padding(
          // The photo starts below the status bar. Padding rather than a
          // SafeArea: FlexibleSpaceBar sizes its background to the bar, and
          // a SafeArea in here would also claim the sides and the bottom.
          padding: EdgeInsets.only(top: topInset),
          child: Stack(
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

/// The posts tagged at a track.
///
/// The venue's community feed in all but name — its own paging, its own
/// compose prompt at the top, and a reload when the screen above says so.
/// Kept here rather than shared with the venue's because that one is a
/// private class inside its own screen; the day a third place needs one,
/// these two should become one widget.
class _TrackCommunityFeed extends StatefulWidget {
  final String trackId;
  final String title;
  final VoidCallback onCompose;

  /// Changes when the screen above wants this reloaded.
  final int refreshToken;

  /// Room under the last post for the floating tab bar.
  final double bottomInset;

  final VoidCallback onBack;

  const _TrackCommunityFeed({
    required this.trackId,
    required this.title,
    required this.onCompose,
    required this.refreshToken,
    required this.bottomInset,
    required this.onBack,
  });

  @override
  State<_TrackCommunityFeed> createState() => _TrackCommunityFeedState();
}

class _TrackCommunityFeedState extends State<_TrackCommunityFeed>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = true;
  int _page = 0;

  static const int _pageSize = 10;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void didUpdateWidget(_TrackCommunityFeed old) {
    super.didUpdateWidget(old);

    // A post was just composed. Start again from page one rather than
    // appending — a new post belongs at the top, and page one holds it.
    if (old.refreshToken != widget.refreshToken) {
      setState(() {
        _posts.clear();
        _page = 0;
        _hasMore = true;
      });
      _loadMore();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    // Both kinds, as a venue's community tab asks for: the track's own
    // announcements and everyone else's posts, in one feed.
    final result = await TracksApiService.fetchTrackPosts(
      trackId: widget.trackId,
      page: _page + 1,
      perPage: _pageSize,
    );

    if (!mounted) return;

    final fetched = (result ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    setState(() {
      _posts.addAll(fetched);
      _hasMore = fetched.length >= _pageSize;
      _page++;
      _loading = false;
      _loaded = true;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _page = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: Color(0xFF1C1C1E)),
              onPressed: widget.onBack,
            ),
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _ComposePrompt(onTap: widget.onCompose),
            ),
          ),

          if (_loaded && _posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 20, 40, 100),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 52,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No posts yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Be the first to post about this track.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Color(0xFF8A8A8E),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: _posts.length,
              itemBuilder: (context, i) {
                final post = _posts[i];

                return PostCard(
                  key: ValueKey(post['id']),
                  post: post,
                  onTapProfile: () => Navigator.pushNamed(
                    context,
                    '/view-profile',
                    arguments: {'userId': post['user_id']},
                  ),
                );
              },
            ),

          if (_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.primaryColor,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),

          SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
        ],
      ),
    );
  }
}

/// The way into the composer, at the top of the feed.
class _ComposePrompt extends StatelessWidget {
  final VoidCallback onTap;

  const _ComposePrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F4),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                size: 19,
                color: Color(0xFF8A8A8E),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Share something about this track',
                  style: TextStyle(fontSize: 14.5, color: Color(0xFF8A8A8E)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
