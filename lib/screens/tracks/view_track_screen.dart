import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/tracks_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter/material.dart';
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

  /// The track's disciplines, as labels.
  List<String> _types(Map<String, dynamic> track) {
    final value = track['types'];
    if (value is! List) return const [];
    return value.map(_text).whereType<String>().toList(growable: false);
  }

  /// What the website shows under the title: the disciplines, then the two
  /// numbers a driver checks before booking a day.
  List<(IconData, String)> _facts(Map<String, dynamic> track) {
    final length = _text(track['track_length']);
    final noise = _text(track['noise_limit']);

    return [
      for (final type in _types(track)) (Icons.sports_score_rounded, type),
      if (length != null) (Icons.straighten_rounded, length),
      if (noise != null) (Icons.volume_up_rounded, noise),
    ];
  }

  String? _image(dynamic value) {
    if (value is Map) return _text(value['url']);
    return _text(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Track')),
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    if (_error != null || _track == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Track')),
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

  Widget _header(Map<String, dynamic> track) {
    final cover = _image(track['cover_photo']);

    return SliverAppBar(
      expandedHeight: 220,
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
          ],
        ),
      ),
    );
  }

  /// Logo, name, disciplines, where it is, how many follow it, and one
  /// button.
  ///
  /// Centred, with the logo above the name rather than beside it. The logo
  /// was a 60px thumbnail in the corner of a left-aligned block, which is
  /// the shape of a list row — fine in a list, but this is the track's own
  /// page and the badge is what identifies it. The same composition as a
  /// venue's page, so the two do not feel like different apps.
  Widget _identity(Map<String, dynamic> track) {
    final logo = _image(track['logo']);
    final location = _text(track['location']);
    final followers = _followerCount(track);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (logo != null) ...[
            Center(
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
                        (104 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

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

          if (_facts(track).isNotEmpty) ...[
            const SizedBox(height: 10),
            // All of them. A track can be a race circuit and a drag strip
            // and a skid pan, and which disciplines it runs is most of what
            // someone wants to know about it.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final fact in _facts(track))
                  _TypeBadge(label: fact.$2, icon: fact.$1),
              ],
            ),
          ],

          if (location != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: Color(0xFF8A8A8E),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    location,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8A8A8E),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Hidden rather than shown as 0. A track nobody follows yet does
          // not need to say so under its own name.
          if (followers != null && followers > 0) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _grouped(followers),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  const TextSpan(
                    text: ' followers',
                    style: TextStyle(color: Color(0xFF8A8A8E)),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5),
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
  /// The field has been spelled both ways over the life of the endpoint, so
  /// both are accepted rather than the count quietly disappearing.
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

/// One of a track's disciplines, as it reads on the page.
class _TypeBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _TypeBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFFD9B978)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
