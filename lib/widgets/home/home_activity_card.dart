import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/global_group_screen.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Something that happened, in the middle of the home feed.
///
/// The feed is mostly posts, drawn with PostCard. Mixed in are things
/// that are not posts and never will be: a car went into a garage,
/// photographs went into a gallery, somebody joined a group. None has a
/// caption, a like or a comment, so drawing one as a post would mean a
/// card with most of its parts empty.
///
/// ── TELLING THEM APART ──────────────────────────────────────────────
///
/// These are different KINDS of event and they should not all look like
/// one. The reliable way to show that is the shape of the thing under
/// the header, not a badge on top of an identical card — shape is read
/// before any label is.
///
/// So there are three bodies:
///
///   PHOTOS   a gallery, or new pictures of a car. A grid, because the
///            pictures are the point and there are several.
///
///   GARAGE   a car added, or a dream car. ONE wide photograph with the
///            car's name across the foot of it, like a plate. A car
///            entering a garage is a record, not a photo dump, and a
///            single hero frame says so at a glance.
///
///   GROUP    somebody joined. No photograph at all — a short tinted row
///            with the group's badge and name. Nothing happened visually,
///            so taking a card's worth of height to say so would be a
///            lie about its importance.
///
/// A quiet icon at the top right agrees with whichever it is. It is a
/// confirmation, not the signal.
///
/// ── INTERESTED / NOT FOR ME ─────────────────────────────────────────
///
/// Shown only on a RECOMMENDATION. Network activity — people followed,
/// people in the same groups — is not a guess that needs correcting: the
/// viewer already chose those people, and asking them to rate it would
/// be clutter on every second card. A recommendation IS a guess, so it
/// carries the buttons that teach the interest profile.
class HomeActivityCard extends StatefulWidget {
  const HomeActivityCard({
    super.key,
    required this.item,
    required this.theme,
    this.onRespond,
  });

  /// The raw row, as the feed delivered it. A map, like the posts it sits
  /// between: the endpoint returns both in one list and the feed branches
  /// on `feed_kind`, so typing one half buys nothing.
  final Map<String, dynamic> item;

  final ThemeProvider theme;

  /// Records Interested / Not for me. Null — or a network card — and the
  /// buttons are not drawn at all.
  final void Function(int activityId, String response)? onRespond;

  @override
  State<HomeActivityCard> createState() => _HomeActivityCardState();
}

/// Which body a card gets.
enum _Shape { photos, garage, group }

class _HomeActivityCardState extends State<HomeActivityCard> {
  /// Held as a field so it can be disposed. One built inside build()
  /// would be rebuilt on every frame this card scrolls through and never
  /// cleaned up.
  late final TapGestureRecognizer _nameTap = TapGestureRecognizer()
    ..onTap = _openProfile;

  /// Set when the card has been answered, so it can say so and stop
  /// asking. Local rather than a refetch: the feed is long, and
  /// reordering it under the reader to remove one card is worse than
  /// leaving it there, answered.
  String? _answered;

  @override
  void dispose() {
    _nameTap.dispose();
    super.dispose();
  }

  // ── What the row says ──────────────────────────────────────────────

  String get _verb => widget.item['verb']?.toString() ?? '';

  Map<String, dynamic>? get _user {
    final raw = widget.item['user'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  String get _who {
    final name = (_user?['name'] ?? '').toString().trim();
    return name.isEmpty ? 'Someone' : name;
  }

  String? get _avatar {
    final value = _user?['avatar']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String get _action =>
      (widget.item['action'] ?? 'did something').toString().trim();

  String get _title => (widget.item['title'] ?? '').toString().trim();

  String? get _subtitle {
    final value = widget.item['subtitle']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get _image {
    final value = widget.item['image']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  /// Which of the three bodies this gets.
  ///
  /// On the VERB, not on target_type: a gallery and new pictures of a car
  /// are different objects but the same kind of event, and a car added is
  /// the same object as a car photographed but a different one.
  _Shape get _shape {
    switch (_verb) {
      case 'added_vehicle':
      case 'added_dream':
        return _Shape.garage;
      case 'joined_group':
        return _Shape.group;
      default:
        return _Shape.photos;
    }
  }

  /// A car somebody WANTS, which is a different statement from one they
  /// have, and the only reason the two share a body.
  bool get _isDream => _verb == 'added_dream';

  /// The photos to draw, at most four.
  List<String> get _images {
    final raw = widget.item['images'];

    if (raw is List) {
      final urls = raw
          .map((v) => v?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();

      if (urls.isNotEmpty) return urls;
    }

    final single = _image;
    return single == null ? const [] : [single];
  }

  /// How many photos there really are, for the "+2" badge.
  ///
  /// Sent separately from the list because the list is trimmed to what
  /// fits and the badge has to count what does not.
  int get _imageCount {
    final raw = widget.item['image_count'];

    final count = switch (raw) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()) ?? 0,
      _ => 0,
    };

    return count > 0 ? count : _images.length;
  }

  /// The sentence under the header — what the activity is.
  ///
  /// Photo cards only. A garage card puts the car on the plate and a
  /// group card puts the name in the row, so a line of prose above
  /// either would say it a second time.
  String? get _caption {
    if (_shape != _Shape.photos) return null;

    final value = widget.item['caption']?.toString().trim() ?? '';

    if (value.isNotEmpty) return value;

    final title = _title;
    return title.isEmpty ? null : title;
  }

  /// The grey line under the name.
  ///
  /// Just the time on garage and group cards: the body names the thing,
  /// and naming it twice in six words of each other reads as a stutter.
  /// On a photo card, whatever the caption has not already said.
  String get _meta {
    if (_shape != _Shape.photos) return _ago;

    final caption = _caption ?? '';
    bool alreadySaid(String s) => s.isNotEmpty && caption.contains(s);

    final bits = <String>[
      if (_title.isNotEmpty && !alreadySaid(_title)) _title,
      if (_subtitle != null && !alreadySaid(_subtitle!)) _subtitle!,
      if (_ago.isNotEmpty) _ago,
    ];

    return bits.join(' · ');
  }

  int get _activityId => switch (widget.item['id']) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v.trim()) ?? 0,
    _ => 0,
  };

  /// A guess, rather than something the viewer chose to see.
  bool get _isRecommendation =>
      widget.item['activity_source']?.toString() == 'recommended';

  IconData get _icon => switch (_shape) {
    _Shape.garage => _isDream
        ? Icons.star_outline_rounded
        : Icons.garage_outlined,
    _Shape.group => Icons.groups_2_outlined,
    _Shape.photos => Icons.photo_library_outlined,
  };

  /// How long ago, from the activity's own timestamp.
  String get _ago {
    final when = DateTime.tryParse(
      widget.item['created_at']?.toString() ?? '',
    );

    if (when == null) return '';

    final gap = DateTime.now().difference(when);

    if (gap.inMinutes < 60) return '${gap.inMinutes}m';
    if (gap.inHours < 24) return '${gap.inHours}h';
    if (gap.inDays < 7) return '${gap.inDays}d';
    if (gap.inDays < 365) return '${(gap.inDays / 7).floor()}w';

    return '${(gap.inDays / 365).floor()}y';
  }

  // ── Going places ───────────────────────────────────────────────────

  void _openProfile() {
    final id = _user?['id'];

    if (id == null) return;

    Navigator.pushNamed(
      context,
      AppRoutes.viewProfile,
      arguments: {
        'userId': id,
        'username': (_user?['username'] ?? '').toString(),
      },
    );
  }

  /// Open whatever the activity is about.
  ///
  /// Note the detail that vehicleDetail wants its id as a String and
  /// postDetail wants an int — neither route coerces what it is handed.
  void _open() {
    final targetId = (widget.item['target_id'] ?? '').toString();

    switch (widget.item['target_type']?.toString()) {
      case 'vehicle':
        if (targetId.isEmpty) return;
        Navigator.pushNamed(
          context,
          AppRoutes.vehicleDetail,
          arguments: {'garageId': targetId},
        );
        break;

      case 'post':
        final postId = int.tryParse(targetId) ?? 0;
        if (postId <= 0) return;
        Navigator.pushNamed(
          context,
          AppRoutes.postDetail,
          arguments: {'postId': postId},
        );
        break;

      case 'group':
        if (targetId.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GlobalGroupScreen(slug: targetId)),
        );
        break;

      case 'gallery':
        // There IS a screen for this — AppRoutes.galleryDetail, which the
        // media section has used all along. The Activity tab's opener
        // predates it and says there is none; this was copied from there,
        // which is why a gallery card used to do nothing when tapped.
        final galleryId = int.tryParse(targetId) ?? 0;
        if (galleryId <= 0) return;
        Navigator.pushNamed(
          context,
          AppRoutes.galleryDetail,
          arguments: {
            // An int: the route accepts either, but in-app callers pass
            // an int and deep links are what the string case is for.
            'galleryId': galleryId,
            'title': _title,
          },
        );
        break;

      default:
        break;
    }
  }

  void _respond(String response) {
    setState(() => _answered = response);
    widget.onRespond?.call(_activityId, response);
  }

  // ── Drawing ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showButtons =
        _isRecommendation && widget.onRespond != null && _answered == null;

    return InkWell(
      onTap: _open,
      child: Container(
        // Flush on white, no rule beneath. The feed around it is posts
        // drawn the same way, and a card with its own outline sitting
        // among them reads as an advert.
        //
        // Separation is space rather than a line. A hairline under every
        // activity turned a run of them into a ruled list, which is
        // heavier than the posts it sits between — and the eye reads
        // whitespace as a break perfectly well without being told.
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),

            if (_caption != null) ...[
              const SizedBox(height: 10),
              Text(
                _caption!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: Color(0xFF111111),
                ),
              ),
            ],

            // Only when there is a body. A gallery whose photos have all
            // been deleted has nothing to draw, and the gap would be the
            // only thing left of it.
            if (_body() case final body?) ...[
              const SizedBox(height: 11),
              body,
            ],

            if (_answered != null) ...[
              const SizedBox(height: 10),
              Text(
                _answered == 'interested'
                    ? 'More like this'
                    : 'Fewer like this',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFA0A0A0),
                ),
              ),
            ],

            if (showButtons) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _ResponseButton(
                      label: 'Interested',
                      icon: Icons.favorite_border_rounded,
                      onTap: () => _respond('interested'),
                      emphasis: true,
                      theme: widget.theme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ResponseButton(
                      label: 'Not for me',
                      icon: Icons.close_rounded,
                      onTap: () => _respond('not_interested'),
                      emphasis: false,
                      theme: widget.theme,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _openProfile,
          child: GroupAvatar(url: _avatar, radius: 21, theme: widget.theme),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _who,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      recognizer: _nameTap,
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: _action,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  color: Color(0xFF111111),
                ),
              ),
              if (_meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  _meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(_icon, size: 18, color: Colors.grey.shade400),
        ),
      ],
    );
  }

  /// Null when there is nothing to draw, so the caller can leave out the
  /// gap as well as the widget.
  Widget? _body() {
    switch (_shape) {
      case _Shape.garage:
        return _GaragePlate(
          image: _image,
          name: _title.isEmpty ? 'A car' : _title,
          spec: _subtitle,
          isDream: _isDream,
          accent: widget.theme.primaryColor,
        );

      case _Shape.group:
        return _GroupRow(
          image: _image,
          name: _title.isEmpty ? 'A group' : _title,
          strapline: _subtitle,
          accent: widget.theme.primaryColor,
        );

      case _Shape.photos:
        if (_images.isEmpty) return null;
        return _PhotoGrid(urls: _images, total: _imageCount);
    }
  }
}

/// A car entering somebody's garage.
///
/// One wide photograph with the car's name across the foot of it. A
/// garage entry is a record rather than a set of pictures, and a single
/// hero frame with a plate on it reads as one — you know what kind of
/// card this is before you have read a word of it.
///
/// The name sits on a scrim rather than under the photo so the two are
/// one object. Underneath, it would be a caption, and a caption under a
/// photo is what the gallery cards do.
class _GaragePlate extends StatelessWidget {
  const _GaragePlate({
    required this.image,
    required this.name,
    required this.spec,
    required this.isDream,
    required this.accent,
  });

  final String? image;
  final String name;
  final String? spec;
  final bool isDream;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              CachedNetworkImage(
                imageUrl: image!,
                fit: BoxFit.cover,
                // The widest this is ever drawn is the card, so there is
                // nothing to gain from decoding beyond it. PostCard caps
                // its own feed images the same way.
                memCacheWidth: 1200,
                placeholder: (_, _) =>
                    Container(color: const Color(0xFFF0F0F0)),
                errorWidget: (_, _, _) => const _NoPhoto(),
              )
            else
              // A car with no picture yet still deserves the same shape,
              // or it would be the only garage card that looks like
              // something else.
              const _NoPhoto(),

            // Dark at the foot, clear at the top: enough to read white
            // over a bright sky without flattening the photograph.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),

            if (isDream)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'DREAM CAR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                  if (spec != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      spec!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD8D8D8),
                      ),
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

/// Somebody joined a group.
///
/// A short row, not a picture. Nothing happened visually — no photograph
/// was taken — so spending a card's worth of height would overstate it
/// next to the gallery above. The group's badge, its name, and a way in.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.image,
    required this.name,
    required this.strapline,
    required this.accent,
  });

  final String? image;
  final String name;
  final String? strapline;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 46,
              height: 46,
              child: image != null
                  ? CachedNetworkImage(
                      imageUrl: image!,
                      fit: BoxFit.cover,
                      // Drawn at 46 logical pixels. A group's cover
                      // image is a banner, and decoding a banner to fill
                      // a thumbnail is most of a megabyte for nothing.
                      memCacheWidth: 160,
                      placeholder: (_, _) =>
                          Container(color: const Color(0xFFEDEDED)),
                      errorWidget: (_, _, _) =>
                          _GroupBadge(accent: accent),
                    )
                  : _GroupBadge(accent: accent),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: Color(0xFF111111),
                  ),
                ),
                if (strapline != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    strapline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF7A7A7A),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: accent, size: 22),
        ],
      ),
    );
  }
}

/// Stands in for a group with no badge.
class _GroupBadge extends StatelessWidget {
  const _GroupBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: accent.withValues(alpha: 0.16),
      alignment: Alignment.center,
      child: Icon(Icons.groups_2_rounded, size: 22, color: accent),
    );
  }
}

/// Stands in for a photograph that is missing or will not load.
class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F0F0),
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_car_outlined,
        size: 34,
        color: Colors.grey.shade400,
      ),
    );
  }
}

/// The photos on a gallery or new-pictures card.
///
/// One big tile with a column of smaller ones beside it, which is what a
/// set of photographs looks like when one of them is the one worth
/// seeing. A single photo gets the whole width; two share it.
///
/// At most three are drawn however many there are. A fourth tile would be
/// small enough to be decoration, and the badge says what is behind the
/// tap more honestly than a thumbnail nobody can see.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.urls, required this.total});

  final List<String> urls;

  /// How many exist, which can be more than [urls] holds.
  final int total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: _layout(),
    );
  }

  Widget _layout() {
    if (urls.length == 1) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: _Tile(url: urls.first, decodeWidth: 1200),
      );
    }

    if (urls.length == 2) {
      return AspectRatio(
        aspectRatio: 2 / 1,
        child: Row(
          children: [
            Expanded(child: _Tile(url: urls[0], decodeWidth: 700)),
            const SizedBox(width: 2),
            Expanded(child: _Tile(url: urls[1], decodeWidth: 700)),
          ],
        ),
      );
    }

    // The remainder after the three tiles on show. Counted off `total`,
    // not off `urls`, because urls is already trimmed.
    final more = total - 3;

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Row(
        children: [
          // Wider than the column beside it: the lead photo is the one
          // being shown, the others are evidence there are more.
          Expanded(flex: 58, child: _Tile(url: urls[0], decodeWidth: 900)),
          const SizedBox(width: 2),
          Expanded(
            flex: 42,
            child: Column(
              children: [
                Expanded(child: _Tile(url: urls[1], decodeWidth: 500)),
                const SizedBox(height: 2),
                Expanded(
                  child: _Tile(
                    url: urls[2],
                    decodeWidth: 500,
                    overlay: more > 0 ? '+$more' : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One photo, with an optional "+2" over it.
class _Tile extends StatelessWidget {
  const _Tile({required this.url, this.overlay, required this.decodeWidth});

  final String url;
  final String? overlay;

  /// How wide this tile is actually drawn, in device pixels, so the
  /// image is not decoded larger than it will ever be seen.
  ///
  /// Passed in rather than decided here: only the grid knows whether this
  /// is the lead tile or one of the small ones, and a tile that assumed
  /// the largest would undo the point for the other two.
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: decodeWidth,
          placeholder: (_, _) => Container(color: const Color(0xFFF4F4F4)),
          errorWidget: (_, _, _) => const _NoPhoto(),
        ),
        if (overlay != null)
          Container(
            // Dark enough to read white over the brightest photograph,
            // light enough to leave the picture legible underneath.
            color: Colors.black.withValues(alpha: 0.42),
            alignment: Alignment.center,
            child: Text(
              overlay!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

/// One of the two feedback buttons.
///
/// Nested inside the card's InkWell, so the innermost gesture wins: a tap
/// here answers the card and does not also open what it is about.
class _ResponseButton extends StatelessWidget {
  const _ResponseButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.emphasis,
    required this.theme,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Interested is the answer worth making easy to give; Not for me is
  /// the quieter one. Same size and same hit area either way — the
  /// weighting is colour only, so neither is harder to reach.
  final bool emphasis;

  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    final accent = theme.primaryColor;

    return Material(
      color: emphasis ? accent.withValues(alpha: 0.10) : const Color(0xFFF4F4F4),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: emphasis ? accent : const Color(0xFF6B6B6B),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: emphasis ? accent : const Color(0xFF6B6B6B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
