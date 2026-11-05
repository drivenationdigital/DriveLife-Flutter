import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A thing that happened in a group that is not a post.
///
/// A group's Latest tab is mostly posts, drawn with the same PostCard a
/// club feed uses. But ce_group_activity also indexes vehicles — somebody
/// added a BMW, and every member of the BMW group might want to see it —
/// and a vehicle has no caption, no comments and nothing to like. Drawing
/// it as a post would mean a card with every one of those parts empty.
///
/// So: who, what car, a photo, and a way in. Closer to the Activity tab's
/// card than to a post, deliberately — the same event in both places
/// should look like the same event.
///
/// No Interested / Not for me here. Those exist in the Activity tab to
/// teach the interest profile, and a group feed is not asking a question:
/// you are in the BMW group, so BMWs are the answer.
class GroupActivityCard extends StatefulWidget {
  const GroupActivityCard({
    super.key,
    required this.item,
    required this.theme,
    required this.onTap,
  });

  /// The raw row. A map rather than a model because the endpoint returns
  /// posts and vehicles in one list and the screen branches on
  /// `group_item_type` — typing one half of a mixed list buys nothing.
  final Map<String, dynamic> item;

  final ThemeProvider theme;

  /// Opens the vehicle.
  final VoidCallback onTap;

  @override
  State<GroupActivityCard> createState() => _GroupActivityCardState();
}

class _GroupActivityCardState extends State<GroupActivityCard> {
  /// Held as a field so it can be disposed. A recognizer built inside
  /// build() would be rebuilt on every frame this card scrolls through
  /// and never cleaned up.
  late final TapGestureRecognizer _nameTap = TapGestureRecognizer()
    ..onTap = _openProfile;

  @override
  void dispose() {
    _nameTap.dispose();
    super.dispose();
  }

  /// Open whoever did this.
  ///
  /// Does nothing without an id: the card still draws for a deleted
  /// account, and a tap that opens an empty profile is worse than a tap
  /// that does nothing.
  void _openProfile() {
    final user = _user;
    final id = user?['id'];

    if (id == null) return;

    Navigator.pushNamed(
      context,
      AppRoutes.viewProfile,
      arguments: {
        'userId': id,
        'username': (user?['username'] ?? '').toString(),
      },
    );
  }

  String get _title => (widget.item['title'] ?? '').toString().trim();

  String get _action =>
      (widget.item['action'] ?? 'added a vehicle').toString().trim();

  /// `vehicle`, `gallery` or `garage_photo`.
  ///
  /// Only the icon and the subtitle differ: the endpoint already writes
  /// the whole sentence into `action` and the name into `title`, so all
  /// three kinds render through the same card rather than three that
  /// drift apart.
  String get _kind => (widget.item['group_item_type'] ?? 'vehicle').toString();

  IconData get _icon {
    switch (_kind) {
      case 'gallery':
        return Icons.photo_library_outlined;
      case 'garage_photo':
        return Icons.add_a_photo_outlined;
      default:
        return Icons.directions_car_filled_outlined;
    }
  }

  String? get _subtitle {
    final value = widget.item['subtitle']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get _image {
    final value = widget.item['image']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Map<String, dynamic>? get _user {
    final raw = widget.item['user'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  String get _who {
    final user = _user;
    if (user == null) return 'Someone';

    final name = (user['name'] ?? '').toString().trim();
    return name.isEmpty ? 'Someone' : name;
  }

  String? get _avatar {
    final value = _user?['avatar']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  /// Variant and colour, whichever are there.
  String? get _spec {
    final bits = <String>[
      for (final key in const ['variant', 'colour'])
        if ((widget.item[key]?.toString().trim() ?? '').isNotEmpty)
          widget.item[key].toString().trim(),
    ];

    // Vehicles describe themselves with variant and colour. A gallery has
    // neither, and sends the matched car as `subtitle` instead.
    if (bits.isEmpty) return _subtitle;

    return bits.join(' · ');
  }

  /// How long ago, from the activity row's own timestamp.
  String get _ago {
    final raw = widget.item['happened_at']?.toString() ?? '';
    final when = DateTime.tryParse(raw);

    if (when == null) return '';

    final gap = DateTime.now().difference(when);

    if (gap.inMinutes < 60) return '${gap.inMinutes}m';
    if (gap.inHours < 24) return '${gap.inHours}h';
    if (gap.inDays < 7) return '${gap.inDays}d';
    if (gap.inDays < 365) return '${(gap.inDays / 7).floor()}w';

    return '${(gap.inDays / 365).floor()}y';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
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
                      if (_spec != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _spec!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B6B6B),
                          ),
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
