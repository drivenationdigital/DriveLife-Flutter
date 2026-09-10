import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/services/posts_service.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:flutter/material.dart';

/// Tagging a post photo by photo — the same screen galleries have.
///
/// Posts only ever had one flat list of tags, every one of them written onto
/// the first image regardless of which photo the person or car was actually
/// in. On a ten-image post that is not tagging, it is a label on the post.
///
/// The grid is the whole point: each tile carries a count, so what has been
/// done and what has not is visible without opening anything.
class PostPhotoTaggingScreen extends StatefulWidget {
  final int postId;

  /// Whose post it is. Sent with new tags, which the server records as the
  /// tagger.
  final int authorId;

  const PostPhotoTaggingScreen({
    super.key,
    required this.postId,
    required this.authorId,
  });

  @override
  State<PostPhotoTaggingScreen> createState() => _PostPhotoTaggingScreenState();
}

class _PostPhotoTaggingScreenState extends State<PostPhotoTaggingScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  /// The post's images: {id, url}. Videos are left out — there is nothing to
  /// point at in one.
  final List<Map<String, dynamic>> _photos = [];

  /// Tags per photo, keyed by the media row id.
  final Map<int, List<GalleryTag>> _tags = {};

  /// The server's id for each tag, so a removal can name the exact row.
  ///
  /// Keyed by photo and then by what the tag points at: the same person tagged
  /// in two photos is two rows, and removing one must not take the other.
  ///
  /// A string key rather than the tag object, because a tag read back from the
  /// server is a different instance to the one on screen and GalleryTag has no
  /// value equality — identity would lose the id on the first save.
  final Map<int, Map<String, int>> _tagIds = {};

  /// What a tag points at, as a map key.
  static String _key(GalleryTag tag) =>
      '${tag.entityType}:${tag.entityId}:'
      '${(tag.registration.isNotEmpty ? tag.registration : tag.label).toUpperCase()}';

  bool _loading = true;

  /// True once anything has been saved, so the screen behind knows to reload.
  bool _changed = false;

  String? _error;

  final PostsService _posts = PostsService();

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
      // PostsService, not PostsAPI: PostsAPI.getPostById builds a URL with
      // no /wp-json/app/v2 in it and reads a `data` key the endpoint does not
      // send. Forced past the cache, because a post whose media list is ten
      // minutes old is exactly the one somebody has just added a photo to.
      final post = await _posts.getPostById(
        postId: '${widget.postId}',
        forceRefresh: true,
      );

      final media = (post?['media'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((m) => '${m['media_type']}' != 'video')
          .toList();

      // Unmatched plates come back only to the post's author, which is who
      // this screen is for — and they are the tags most in need of correcting.
      final tags = await PostsAPI.fetchPostTags(postId: widget.postId);

      if (!mounted) return;

      final grouped = <int, List<GalleryTag>>{};
      final ids = <int, Map<String, int>>{};

      for (final raw in tags) {
        final tagId = int.tryParse('${raw['tag_id']}') ?? 0;
        final mediaId = int.tryParse('${raw['media_id']}') ?? 0;
        final type = '${raw['type']}';

        // Venues and events hang off a post differently and are not editable
        // here, so they are left alone rather than listed and then dropped.
        if (tagId <= 0 || mediaId <= 0) continue;
        if (type != 'user' && !type.contains('car')) continue;

        final tag = GalleryTag.fromPostTag(raw);

        grouped.putIfAbsent(mediaId, () => []).add(tag);
        ids.putIfAbsent(mediaId, () => {})[_key(tag)] = tagId;
      }

      setState(() {
        _photos
          ..clear()
          ..addAll(media);
        _tags
          ..clear()
          ..addAll(grouped);
        _tagIds
          ..clear()
          ..addAll(ids);
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

  Future<void> _openPhoto(Map<String, dynamic> photo) async {
    final photoId = int.tryParse('${photo['id']}') ?? 0;
    if (photoId <= 0) return;

    final saved = await showModalBottomSheet<List<GalleryTag>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _PhotoTagSheet(
        imageUrl: '${photo['media_url'] ?? ''}',
        initialTags: _tags[photoId] ?? const [],
        onSave: (tags) => _save(photoId, tags),
      ),
    );

    if (saved == null || !mounted) return;

    setState(() {
      _changed = true;
      if (saved.isEmpty) {
        _tags.remove(photoId);
      } else {
        _tags[photoId] = saved;
      }
    });
  }

  /// Writes one photo's tags.
  ///
  /// Posts have no "replace this photo's set" call the way galleries do, so
  /// the difference is worked out here: what has gone is removed by its row
  /// id, and what is new is added naming the photo it belongs to.
  Future<void> _save(int photoId, List<GalleryTag> tags) async {
    final before = _tags[photoId] ?? const <GalleryTag>[];
    final ids = _tagIds[photoId] ?? const <String, int>{};

    for (final tag in before) {
      if (tags.any((t) => t.matches(tag))) continue;

      final tagId = ids[_key(tag)] ?? 0;
      if (tagId > 0) await PostsAPI.removePostTag(tagId: tagId);
    }

    final added = tags.where((t) => !before.any((b) => b.matches(t))).toList();

    if (added.isNotEmpty) {
      await PostsAPI.addTagsForPost(
        userId: widget.authorId,
        postId: widget.postId,
        tags: [
          for (final tag in added)
            TaggedEntity(
              // The photo itself. `index` is a position in a list both sides
              // have to agree the order of, which is how a tag ended up on
              // the wrong image.
              index: 0,
              mediaId: photoId,
              id: '${tag.entityId}',
              label: tag.label,
              type: tag.kind == TagKind.member ? 'user' : 'car',
              registration: tag.registration,
              x: 0.5,
              y: 0.5,
            ),
        ],
      );
    }

    // The new rows have ids this screen has never seen, so the next removal
    // would have nothing to name. Reading them back is cheaper than guessing.
    if (added.isNotEmpty || before.length != tags.length) {
      await _refreshIds(photoId);
    }
  }

  Future<void> _refreshIds(int photoId) async {
    try {
      final tags = await PostsAPI.fetchPostTags(postId: widget.postId);
      if (!mounted) return;

      final ids = <String, int>{};

      for (final raw in tags) {
        final tagId = int.tryParse('${raw['tag_id']}') ?? 0;
        final mediaId = int.tryParse('${raw['media_id']}') ?? 0;
        if (tagId <= 0 || mediaId != photoId) continue;

        ids[_key(GalleryTag.fromPostTag(raw))] = tagId;
      }

      _tagIds[photoId] = ids;
    } catch (_) {
      // The tags are saved either way; the ids come back on the next load.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagged = _tags.values.where((t) => t.isNotEmpty).length;

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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tag photos',
                style: TextStyle(
                  color: _ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _loading
                    ? 'Loading…'
                    : tagged == 0
                    ? 'Tap a photo to tag it'
                    : '$tagged of ${_photos.length} tagged',
                style: const TextStyle(color: _muted, fontSize: 13.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _changed),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
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

    if (_photos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No photos to tag.', style: TextStyle(color: _muted)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        final photoId = int.tryParse('${photo['id']}') ?? 0;
        final count = _tags[photoId]?.length ?? 0;

        return GestureDetector(
          onTap: () => _openPhoto(photo),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: '${photo['media_url'] ?? ''}',
                fit: BoxFit.cover,
                memCacheWidth: 400,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) =>
                    Container(color: Colors.grey.shade200),
              ),

              // A tagged photo is obvious without counting: gold badge, and
              // untagged tiles stay plain rather than carrying a "0".
              if (count > 0)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_offer,
                          size: 11,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tagging one photo. Pops the saved list, or null if nothing was saved.
class _PhotoTagSheet extends StatefulWidget {
  final String imageUrl;
  final List<GalleryTag> initialTags;

  /// Writes the photo's tags. Throws to report a failure.
  final Future<void> Function(List<GalleryTag>) onSave;

  const _PhotoTagSheet({
    required this.imageUrl,
    required this.initialTags,
    required this.onSave,
  });

  @override
  State<_PhotoTagSheet> createState() => _PhotoTagSheetState();
}

class _PhotoTagSheetState extends State<_PhotoTagSheet> {
  static const Color _ink = Color(0xFF0B0B0B);

  late List<GalleryTag> _tags = List<GalleryTag>.from(widget.initialTags);

  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      await widget.onSave(_tags);
      if (!mounted) return;
      Navigator.pop(context, _tags);
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
    return Padding(
      // Lifts the sheet clear of the keyboard while searching.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 140,
                      placeholder: (_, __) => Container(
                        width: 44,
                        height: 44,
                        color: Colors.grey.shade200,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Tag this photo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Container(height: 1, color: Colors.grey.shade200),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  GalleryTagPicker(
                    tags: _tags,
                    onChanged: (tags) => setState(() => _tags = tags),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
