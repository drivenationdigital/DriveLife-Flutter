import 'dart:async';

import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/screens/create-post/post_photo_tagging_screen.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/widgets/media/detected_vehicle_row.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Step 2 of posting — who and what is in the post.
///
/// The same shape as the gallery flow, and for the same reason: a tag needs the
/// post to exist and its media to be registered, and neither is true until the
/// background upload finishes. So this screen waits, then tags.
///
/// Nothing here is required. The post is already published by the time the
/// tagging UI appears, so leaving simply means an untagged post — which is why
/// the button reads Skip until something is tagged.
class PostTaggingScreen extends StatefulWidget {
  /// The background upload to follow, as passed to [UploadPostProvider].
  final String uploadId;

  const PostTaggingScreen({super.key, required this.uploadId});

  @override
  State<PostTaggingScreen> createState() => _PostTaggingScreenState();
}

class _PostTaggingScreenState extends State<PostTaggingScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  /// Tags that will be saved.
  List<GalleryTag> _tags = [];

  /// Which image in the post each auto-detected tag was found in.
  ///
  /// Post tags are per-image — the server maps `index` positionally onto the
  /// post's media — so a detected car is tagged in the photo it was actually
  /// seen in. Manual tags have no such evidence and go on the first image.
  final Map<String, int> _indexFor = {};

  List<Map<String, dynamic>> _suggestions = const [];
  final Set<String> _dismissed = {};

  int? _postId;

  bool _scanning = false;
  bool _saving = false;
  bool _scanStarted = false;
  bool _openingPhotos = false;

  /// Set once anything has been tagged photo by photo, so leaving does not
  /// report "Post published" as though nothing happened.
  bool _taggedPhotos = false;

  /// Whether the scan read every image. A finished scan that found nothing is
  /// a result worth reporting, not a reason to vanish.
  bool _scanFinished = false;

  String? _scanError;

  /// Stops the scan loop if the screen goes away mid-run.
  bool _disposed = false;

  UploadPostProvider? _uploads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final provider = context.read<UploadPostProvider>();
    if (identical(provider, _uploads)) return;

    _uploads?.removeListener(_onUploadChanged);
    _uploads = provider..addListener(_onUploadChanged);

    // A short post on wifi can finish before this screen's first frame.
    _onUploadChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    _uploads?.removeListener(_onUploadChanged);
    super.dispose();
  }

  void _onUploadChanged() {
    if (_scanStarted || _disposed || !mounted) return;

    final upload = _uploads?.getUpload(widget.uploadId);
    if (upload == null || upload.status != UploadStatus.completed) return;

    final postId = int.tryParse('${upload.result?['post_id']}');
    if (postId == null || postId <= 0) return;

    _scanStarted = true;
    setState(() => _postId = postId);
    _runScan(postId);
  }

  Future<void> _runScan(int postId) async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });

    try {
      var done = false;

      // Bounded so a server that never reports done cannot spin forever.
      for (var pass = 0; pass < 100 && !done; pass++) {
        final result = await PostsAPI.scanPost(postId: postId);
        if (_disposed || !mounted) return;

        if (result['available'] == false) {
          setState(() => _scanning = false);
          return;
        }

        done = result['done'] == true;

        final found = (result['suggestions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        setState(() {
          _suggestions = found;
          _scanFinished = done;
          _autoTag(found);
        });
      }
    } catch (e) {
      // A failed scan is not a failed post — it is already published — so this
      // is reported in place rather than as an error over the top of it.
      if (!_disposed && mounted) {
        setState(() => _scanError = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (!_disposed && mounted) setState(() => _scanning = false);
    }
  }

  /// Tags every detected plate without being asked, as the gallery flow does.
  /// Called inside the caller's setState.
  void _autoTag(List<Map<String, dynamic>> suggestions) {
    for (final suggestion in suggestions) {
      final plate = '${suggestion['registration'] ?? ''}';
      if (plate.isEmpty || _dismissed.contains(plate)) continue;

      final tag = GalleryTag(
        kind: TagKind.vehicle,
        label: plate,
        subtitle: '${suggestion['subtitle'] ?? ''}',
        avatarUrl: '${suggestion['image'] ?? ''}',
        entityId: int.tryParse('${suggestion['entity_id']}') ?? 0,
        registration: plate,
      );

      // The scan is polled and returns everything found so far, so without
      // this every pass would re-add the same cars.
      if (_tags.any((t) => t.matches(tag))) continue;

      _indexFor[plate] = int.tryParse('${suggestion['index']}') ?? 0;
      _tags = [..._tags, tag];
    }
  }

  List<Map<String, dynamic>> get _openSuggestions => _suggestions
      .where((s) => !_dismissed.contains('${s['registration'] ?? ''}'))
      .toList();

  void _removeSuggestion(Map<String, dynamic> suggestion) {
    final plate = '${suggestion['registration'] ?? ''}';
    final entityId = int.tryParse('${suggestion['entity_id']}') ?? 0;

    setState(() {
      _dismissed.add(plate);
      _tags = _tags
          .where(
            (t) =>
                t.kind != TagKind.vehicle ||
                (entityId > 0
                    ? t.entityId != entityId
                    : t.label.toUpperCase() != plate.toUpperCase()),
          )
          .toList();
    });
  }

  /// Writes what the scan found. Safe to call twice — the server ignores a
  /// tag that is already on the photo.
  Future<void> _saveDetectedTags() async {
    final postId = _postId;
    if (postId == null || _tags.isEmpty) return;

    final userId = context.read<UserProvider>().user?.id ?? 0;

    await PostsAPI.addTagsForPost(
      userId: userId,
      postId: postId,
      tags: _tags.map((tag) {
        return TaggedEntity(
          // Where it was seen for a detected car; the first image for a
          // manual tag, which carries no evidence of its own.
          index: _indexFor[tag.label] ?? 0,
          id: '${tag.entityId}',
          type: tag.kind == TagKind.vehicle ? 'car' : 'user',
          label: tag.label,
          imageUrl: tag.avatarUrl.isEmpty ? null : tag.avatarUrl,
          registration: tag.registration,
        );
      }).toList(),
    );
  }

  /// Opens per-photo tagging, exactly as the gallery flow does.
  ///
  /// The detected tags are written first, so the grid opens showing what is
  /// already on each photo rather than an empty post — and so nothing is lost
  /// if the user finishes from in there.
  Future<void> _tagMore() async {
    final postId = _postId;
    if (postId == null) return;

    setState(() => _openingPhotos = true);

    try {
      await _saveDetectedTags();
      if (!mounted) return;

      final userId = context.read<UserProvider>().user?.id ?? 0;

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              PostPhotoTaggingScreen(postId: postId, authorId: userId),
        ),
      );

      if (!mounted) return;
      if (changed == true) setState(() => _taggedPhotos = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingPhotos = false);
    }
  }

  Future<void> _publish() async {
    final postId = _postId;

    // Still uploading, or it failed — either way there is nothing to attach
    // tags to, so let them out rather than trapping them here.
    if (postId == null || _tags.isEmpty) {
      _finish();
      return;
    }

    setState(() => _saving = true);

    try {
      await _saveDetectedTags();

      if (!mounted) return;
      _finish();
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

  void _finish() {
    final count = _tags.length;
    final messenger = ScaffoldMessenger.of(context);

    Navigator.of(context).popUntil((route) => route.isFirst);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          // Tags added photo by photo never land in _tags, so counting
          // only that list reported "Post published" over work just done.
          count == 0
              ? (_taggedPhotos
                    ? 'Post published with your tags'
                    : 'Post published')
              : 'Post published with $count tag${count == 1 ? '' : 's'}',
        ),
        backgroundColor: _gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched rather than read: the upload's progress drives the top of this
    // screen while it is still going.
    final upload = context.watch<UploadPostProvider>().getUpload(
      widget.uploadId,
    );

    final publishing =
        upload != null &&
        upload.status != UploadStatus.completed &&
        upload.status != UploadStatus.failed;

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
          onPressed: _finish,
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tag users & vehicles',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Step 2 of 2',
              style: TextStyle(color: _muted, fontSize: 13.5),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              onPressed: _saving ? null : _publish,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  // Always "Done", as the gallery flow is: the post is
                  // already published by the time this screen appears, and
                  // "Skip" also read the wrong list — tags added photo by
                  // photo never reach _tags.
                  : const Text('Done'),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: ListView(
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
          Text(
            publishing
                ? 'Your post is publishing. Tagging opens as soon as it lands '
                      '— you can leave, it carries on without this screen.'
                : 'Tagged members and vehicles are linked to your post so '
                      'people can find it. This is optional.',
            style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
          ),
          const SizedBox(height: 20),

          if (publishing) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: upload.progress > 0 ? upload.progress : null,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: _gold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              upload.statusMessage.isEmpty
                  ? 'Publishing…'
                  : upload.statusMessage,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          ] else ...[
            if (_scanning ||
                _scanFinished ||
                _openSuggestions.isNotEmpty ||
                _scanError != null) ...[
              _PostScanSection(
                scanning: _scanning,
                finished: _scanFinished,
                error: _scanError,
                suggestions: _openSuggestions,
                onRemove: _removeSuggestion,
                onRetry: () {
                  final postId = _postId;
                  if (postId != null) _runScan(postId);
                },
              ),
              const SizedBox(height: 24),
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
        ],
      ),
    );
  }
}

/// Detected vehicles, tagged by default with a control to remove each.
class _PostScanSection extends StatelessWidget {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  final bool scanning;

  /// Whether the scan read every image.
  final bool finished;

  final String? error;
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onRemove;
  final VoidCallback onRetry;

  const _PostScanSection({
    required this.scanning,
    required this.finished,
    required this.error,
    required this.suggestions,
    required this.onRemove,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // A finished scan with no results is a result. Reporting it beats leaving
    // the user unsure whether the scan ever ran.
    final foundNothing = finished && suggestions.isEmpty && error == null;

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
              Icon(
                foundNothing ? Icons.search_off : Icons.auto_awesome,
                size: 17,
                color: foundNothing ? _muted : _gold,
              ),
              const SizedBox(width: 7),
              Text(
                foundNothing ? 'No vehicles found' : 'Auto-detected',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              if (suggestions.isNotEmpty)
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
                    '${suggestions.length} tagged',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A6D2F),
                    ),
                  ),
                ),
              const Spacer(),
              if (scanning)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            error != null
                ? error!
                : scanning
                ? 'Looking for number plates…'
                : foundNothing
                ? 'We could not make out a number plate in these photos. Tag '
                      'people and vehicles yourself below.'
                : 'Tagged automatically. Remove any that are wrong — owners '
                      'are notified when their car is tagged.',
            style: TextStyle(
              fontSize: 12.5,
              color: error != null ? Colors.red.shade700 : _muted,
              height: 1.4,
            ),
          ),

          if (error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          for (final suggestion in suggestions)
            DetectedVehicleRow(
              suggestion: suggestion,
              onRemove: () => onRemove(suggestion),
              removeTooltip: 'Not in this post',
            ),
        ],
      ),
    );
  }
}
