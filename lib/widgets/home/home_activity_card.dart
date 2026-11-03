import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/global_group_screen.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Something that happened, in the middle of the home feed.
///
/// The home feed is mostly posts, drawn with PostCard. Mixed in with them
/// are things that are not posts and never will be: a car went into a
/// garage, photographs went into a gallery, somebody joined a group. None
/// of those has a caption, a like or a comment, so drawing one as a post
/// would mean a card with most of its parts empty.
///
/// Deliberately the same card the group Latest tab uses rather than a
/// second design — the same event in both places should look like the
/// same event. It is a separate widget and not that one because
/// GroupActivityCard reads a group feed's field names and navigates
/// through a group screen; sharing it would have meant a translation
/// layer in one direction and a flag in the other.
///
/// ── INTERESTED / NOT FOR ME ─────────────────────────────────────────
///
/// Shown only on a RECOMMENDATION. Network activity — people followed,
/// people in the same groups — is not a guess that needs correcting:
/// the viewer already chose those people, and asking them to rate it
/// would be clutter on every second card. A recommendation IS a guess,
/// so it carries the buttons that teach the interest profile.
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

  /// Records Interested / Not for me. Null — or a network card — and
  /// the buttons are not drawn at all.
  final void Function(int activityId, String response)? onRespond;

  @override
  State<HomeActivityCard> createState() => _HomeActivityCardState();
}

class _HomeActivityCardState extends State<HomeActivityCard> {
  /// Held as a field so it can be disposed. One built inside build()
  /// would be rebuilt on every frame this card scrolls through and never
  /// cleaned up.
  late final TapGestureRecognizer _nameTap = TapGestureRecognizer()
    ..onTap = _openProfile;

  /// Set when the card has been answered, so it can say so and stop
  /// asking. Local rather than a refetch: the feed is long and reordering
  /// it under the reader to remove one card is worse than leaving it
  /// there, answered.
  String? _answered;

  @override
  void dispose() {
    _nameTap.dispose();
    super.dispose();
  }

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

  int get _activityId => switch (widget.item['id']) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v.trim()) ?? 0,
    _ => 0,
  };

  /// A guess, rather than something the viewer chose to see.
  bool get _isRecommendation =>
      widget.item['activity_source']?.toString() == 'recommended';

  IconData get _icon {
    switch (widget.item['target_type']?.toString()) {
      case 'gallery':
        return Icons.photo_library_outlined;
      case 'group':
        return Icons.groups_2_outlined;
      case 'post':
        return Icons.camera_alt_outlined;
      default:
        return Icons.directions_car_filled_outlined;
    }
  }

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
  /// The same mapping the Activity tab uses, including the detail that
  /// vehicleDetail wants its id as a String and postDetail wants an int —
  /// neither route coerces what it is handed.
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

      // A gallery has no screen of its own yet. The card is still worth
      // showing; it simply does not go anywhere.
      default:
        break;
    }
  }

  void _respond(String response) {
    setState(() => _answered = response);
    widget.onRespond?.call(_activityId, response);
  }

  @override
  Widget build(BuildContext context) {
    final showButtons =
        _isRecommendation && widget.onRespond != null && _answered == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDEDED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _openProfile,
                        child: GroupAvatar(
                          url: _avatar,
                          radius: 18,
                          theme: widget.theme,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _who,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                    recognizer: _nameTap,
                                  ),
                                  const TextSpan(text: '  '),
                                  TextSpan(
                                    text: _action,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF6B6B6B),
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.3,
                                color: Color(0xFF111111),
                              ),
                            ),
                            if (_ago.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _ago,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFA0A0A0),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(_icon, size: 17, color: Colors.grey.shade400),
                    ],
                  ),
                ),

                if (_image != null)
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: CachedNetworkImage(
                      imageUrl: _image!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: const Color(0xFFF4F4F4)),
                      errorWidget: (_, _, _) => Container(
                        color: const Color(0xFFF4F4F4),
                        child: Icon(
                          Icons.directions_car_outlined,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title.isEmpty ? 'A car' : _title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: Color(0xFF111111),
                        ),
                      ),
                      if (_subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two feedback buttons.
///
/// Nested inside the card's InkWell, so the innermost gesture wins: a tap
/// here answers the card and does not also open the car behind it.
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
      color: emphasis
          ? accent.withValues(alpha: 0.10)
          : const Color(0xFFF4F4F4),
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
