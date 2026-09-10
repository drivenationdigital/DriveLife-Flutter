import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/screens/create-post/post_photo_tagging_screen.dart';
import 'package:drivelife/widgets/media/detected_vehicle_row.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:flutter/material.dart';

/// Adjusts who and what is tagged in a post after it has been published.
///
/// The same screen a gallery gets, and for the same reasons. Two lists of what
/// is on the post — vehicles and people — and one way in to tagging photo by
/// photo, which is where a tag actually belongs: a post's tags are per image,
/// and everything added from a flat list landed on the first one.
///
/// Registrations the scan read that match nobody's garage are listed here and
/// nowhere else. They are the tags most likely to be wrong, this is the only
/// screen that can correct them, and the post's author is the only person the
/// server sends them to.
///
/// Venues and events are attached to a post differently and are not editable
/// here yet.
class EditPostTagsScreen extends StatefulWidget {
  final int postId;

  /// Whose post it is. Sent with new tags, which the server records as the
  /// tagger.
  final int authorId;

  const EditPostTagsScreen({
    super.key,
    required this.postId,
    required this.authorId,
  });

  @override
  State<EditPostTagsScreen> createState() => _EditPostTagsScreenState();
}

/// One tag on the post, with the row id needed to take it off again.
typedef _PostTag = ({GalleryTag tag, int tagId});

class _EditPostTagsScreenState extends State<EditPostTagsScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);

  List<_PostTag> _vehicles = const [];
  List<_PostTag> _people = const [];

  bool _loading = true;
  bool _openingPhotos = false;

  /// Whether anything changed, so the screen behind knows to reload.
  bool _changed = false;

  String? _error;

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
      final tags = await PostsAPI.fetchPostTags(postId: widget.postId);
      if (!mounted) return;

      final vehicles = <_PostTag>[];
      final people = <_PostTag>[];

      for (final raw in tags) {
        final tagId = int.tryParse('${raw['tag_id']}') ?? 0;
        final type = '${raw['type']}';

        if (tagId <= 0 || (type != 'user' && !type.contains('car'))) continue;

        final tag = GalleryTag.fromPostTag(raw);
        (tag.kind == TagKind.vehicle ? vehicles : people).add((
          tag: tag,
          tagId: tagId,
        ));
      }

      setState(() {
        _vehicles = vehicles;
        _people = people;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Takes a tag off, straight away.
  ///
  /// No Save button: a removal is one decision about one tag, and holding it
  /// behind a second confirmation is how a screen full of them ends up half
  /// applied. The row leaves the list first and comes back if the call fails.
  Future<void> _remove(_PostTag entry) async {
    final wasVehicle = entry.tag.kind == TagKind.vehicle;

    setState(() {
      _changed = true;
      if (wasVehicle) {
        _vehicles = _vehicles.where((e) => e.tagId != entry.tagId).toList();
      } else {
        _people = _people.where((e) => e.tagId != entry.tagId).toList();
      }
    });

    try {
      await PostsAPI.removePostTag(tagId: entry.tagId);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        if (wasVehicle) {
          _vehicles = [..._vehicles, entry];
        } else {
          _people = [..._people, entry];
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _tagMore() async {
    setState(() => _openingPhotos = true);

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PostPhotoTaggingScreen(
          postId: widget.postId,
          authorId: widget.authorId,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _openingPhotos = false);

    // Reload rather than patch: the grid can have added and removed several
    // tags across several photos, and their row ids are new.
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  /// A tagged vehicle in the shape the auto-detected list uses, so a car looks
  /// the same wherever it is shown.
  Map<String, dynamic> _asSuggestion(GalleryTag tag) => {
    'registration': tag.label,
    'subtitle': tag.subtitle.isNotEmpty
        ? tag.subtitle
        // A plate nobody has claimed. Said plainly, because "Unknown vehicle"
        // reads as an error when it is simply all we know.
        : 'Not registered here yet',
    'image': tag.avatarUrl,
    if (tag.ownerHandle.isNotEmpty)
      'owner': {'label': tag.ownerHandle, 'image': tag.ownerAvatar},
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          titleSpacing: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: const Text(
            'Edit User Tags',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.grey.shade200),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 34, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        const Text(
          'Who is in this post?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Everything tagged on this post, including registrations we read off '
          'the photos. Only you can see the ones that match no vehicle here.',
          style: TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
        ),
        const SizedBox(height: 20),

        if (_vehicles.isNotEmpty) ...[
          _Section(
            icon: Icons.directions_car_filled_outlined,
            title: 'Vehicles',
            count: _vehicles.length,
            child: Column(
              children: [
                for (final entry in _vehicles)
                  DetectedVehicleRow(
                    suggestion: _asSuggestion(entry.tag),
                    onRemove: () => _remove(entry),
                    removeTooltip: 'Not in this post',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (_people.isNotEmpty) ...[
          _Section(
            icon: Icons.person_outline,
            title: 'People',
            count: _people.length,
            child: Column(
              children: [
                for (final entry in _people)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: GalleryTagCard(
                      tag: entry.tag,
                      onRemove: () => _remove(entry),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (_vehicles.isEmpty && _people.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text(
              'Nothing is tagged in this post yet.',
              style: TextStyle(fontSize: 13.5, color: _muted),
            ),
          ),
          const SizedBox(height: 20),
        ],

        Container(height: 1, color: Colors.grey.shade200),
        const SizedBox(height: 20),
        const Text(
          'Tag more users',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Search for people and vehicles, and tag them photo by photo.',
          style: TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openingPhotos ? null : _tagMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              minimumSize: const Size.fromHeight(50),
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: _openingPhotos
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text(
              'Tag more users',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

/// One headed block, styled like the auto-detected panel the tagging screens
/// use so the two read as the same feature.
class _Section extends StatelessWidget {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _gold = Color(0xFFC4A062);

  final IconData icon;
  final String title;
  final int count;
  final Widget child;

  const _Section({
    required this.icon,
    required this.title,
    required this.count,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: _gold),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A6D2F),
                  ),
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
