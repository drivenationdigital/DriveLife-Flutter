import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:flutter/material.dart';

/// Adjusts who is tagged in a post after it has been published.
///
/// Tagging used to be a one-way door: the step during composing was the only
/// chance, and a wrong tag or a missed person stayed that way for good.
///
/// People and vehicles only for now. Venues and events are attached to a post
/// differently and are not editable here yet.
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

class _EditPostTagsScreenState extends State<EditPostTagsScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  /// What the post has now, keyed by the server's tag id so a removal can name
  /// the exact row.
  final Map<int, GalleryTag> _existing = {};

  /// Tag ids the user has taken off, applied on save.
  final Set<int> _removed = {};

  /// Tags added in this session, which have no id until they are written.
  List<GalleryTag> _added = [];

  bool _loading = true;
  bool _saving = false;
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

      _existing.clear();

      for (final raw in tags) {
        final tagId = int.tryParse('${raw['tag_id']}') ?? 0;
        final type = '${raw['type']}';

        // Venues and events hang off a post differently and are not editable
        // here, so they are left alone rather than listed and then dropped.
        if (tagId <= 0 || (type != 'user' && !type.contains('car'))) continue;

        final entity = raw['entity'];
        final map = entity is Map ? Map<String, dynamic>.from(entity) : {};

        _existing[tagId] = GalleryTag(
          kind: type == 'user' ? TagKind.member : TagKind.vehicle,
          label:
              '${map['username'] ?? map['registration'] ?? map['name'] ?? ''}',
          subtitle: '${map['name'] ?? ''}',
          avatarUrl: '${map['image'] ?? ''}',
          entityId: int.tryParse('${raw['entity_id']}') ?? 0,
          registration: type == 'user' ? '' : '${map['registration'] ?? ''}',
          ownerId: type == 'user'
              ? (int.tryParse('${raw['entity_id']}') ?? 0)
              : (int.tryParse('${map['owner_id'] ?? 0}') ?? 0),
        );
      }

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Everything currently on the post, as the picker sees it.
  List<GalleryTag> get _visible => [
    for (final entry in _existing.entries)
      if (!_removed.contains(entry.key)) entry.value,
    ..._added,
  ];

  /// The picker hands back a whole list, so a removal shows up as something
  /// that used to be there and no longer is.
  void _onChanged(List<GalleryTag> tags) {
    final kept = tags.toSet();

    setState(() {
      for (final entry in _existing.entries) {
        if (_removed.contains(entry.key)) continue;
        if (!kept.contains(entry.value)) _removed.add(entry.key);
      }

      _added = tags.where((tag) => !_existing.containsValue(tag)).toList();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      for (final tagId in _removed) {
        await PostsAPI.removePostTag(tagId: tagId);
      }

      if (_added.isNotEmpty) {
        await PostsAPI.addTagsForPost(
          userId: widget.authorId,
          postId: widget.postId,
          tags: [
            for (final tag in _added)
              TaggedEntity(
                id: '${tag.entityId}',
                label: tag.label,
                type: tag.kind == TagKind.member ? 'user' : 'car',
                // Added after the fact, with no photo to point at: the first
                // image is where a tag with no evidence goes.
                index: 0,
                x: 0.5,
                y: 0.5,
                registration: tag.registration,
              ),
          ],
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _removed.isNotEmpty || _added.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: const Text(
          'Edit tags',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: (_saving || !dirty) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    )
                  : Text(
                      'Save',
                      style: TextStyle(
                        color: dirty ? _gold : Colors.grey.shade400,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _buildBody(),
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
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tagging someone lets them find the post from their own profile. '
          'A tag on somebody else is a request until they accept it.',
          style: TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
        ),
        const SizedBox(height: 18),
        GalleryTagPicker(tags: _visible, onChanged: _onChanged),
      ],
    );
  }
}
