import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/screens/events/event_community_gallery_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One photo shared by an attendee, as returned by
/// `app/v2/event-community-gallery/list`.
class CommunityPhoto {
  final int id;
  final String url; // full size — viewer
  final String thumb; // smaller crop — grid tiles
  final String uploaderName;
  final String uploaderAvatar;
  final DateTime? takenAt;

  /// Whether the signed-in viewer may remove this photo — their own upload, or
  /// anything at all if they own the event. Decided server-side; this only
  /// governs whether the control is offered.
  final bool canDelete;

  const CommunityPhoto({
    required this.id,
    required this.url,
    required this.thumb,
    required this.uploaderName,
    required this.uploaderAvatar,
    this.takenAt,
    this.canDelete = false,
  });

  factory CommunityPhoto.fromJson(Map<String, dynamic> json) {
    final uploader = json['uploader'] as Map<String, dynamic>? ?? const {};
    final url = _str(json['url']);
    final thumb = _str(json['thumb']);

    return CommunityPhoto(
      id: int.tryParse(_str(json['id'])) ?? 0,
      url: url,
      thumb: thumb.isEmpty ? url : thumb,
      uploaderName: _str(uploader['name']).isEmpty
          ? 'DriveLife member'
          : _str(uploader['name']),
      uploaderAvatar: _str(uploader['avatar']),
      takenAt: DateTime.tryParse(_str(json['taken_at'])) ??
          DateTime.tryParse(_str(json['created_at'])),
      // Absent on an older server build — default to no control rather than
      // offering a delete that would come back 403.
      canDelete: json['can_delete'] == true || json['can_delete'] == 1,
    );
  }

  static String _str(dynamic value) => value?.toString() ?? '';
}

/// Community gallery tab — photos attendees shared from this event.
///
/// Read-only grid; the "Add photos" action hands off to
/// [EventCommunityGalleryScreen] and refreshes when it returns.
class EventCommunityGalleryTab extends StatefulWidget {
  final String eventId;
  final String eventTitle;
  final String? eventCoverUrl;
  final Color primaryColor;

  const EventCommunityGalleryTab({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.primaryColor,
    this.eventCoverUrl,
  });

  @override
  State<EventCommunityGalleryTab> createState() =>
      _EventCommunityGalleryTabState();
}

class _EventCommunityGalleryTabState extends State<EventCommunityGalleryTab> {
  final List<CommunityPhoto> _photos = [];

  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  /// Batches whose completion has already triggered a reload.
  ///
  /// Lives here, on state that survives a reload. It used to live on the status
  /// strip inside the scroll view — which [_loadFirstPage] tears down when it
  /// flips to the skeleton, so the set was destroyed and every finished batch
  /// looked new again on the way back: refresh, teardown, refresh, forever.
  final Set<String> _handledBatches = {};

  GalleryUploadProvider? _uploads;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Watching the provider directly, rather than reacting inside build().
    // A refresh is a side effect, and build() must stay free of those.
    final provider = context.read<GalleryUploadProvider>();
    if (identical(provider, _uploads)) return;

    _uploads?.removeListener(_onUploadsChanged);
    _uploads = provider..addListener(_onUploadsChanged);
  }

  @override
  void dispose() {
    _uploads?.removeListener(_onUploadsChanged);
    super.dispose();
  }

  /// Pulls in photos once per batch, as soon as that batch stops running.
  void _onUploadsChanged() {
    final provider = _uploads;
    if (provider == null || !mounted) return;

    for (final batch in provider.batches.values) {
      if (batch.eventId != widget.eventId) continue;

      if (!batch.isFinished) {
        // Running again — a Retry on a partly-failed batch. Re-arm it so the
        // photos it recovers still trigger a reload when it settles.
        _handledBatches.remove(batch.id);
        continue;
      }

      if (!_handledBatches.add(batch.id)) continue; // add() false = already in

      // Quietly — a full skeleton flash after a successful upload is the
      // "glitching" half of this bug, separate from the loop.
      _loadFirstPage(silent: true);
    }
  }

  // ── Data ─────────────────────────────────────────────────────────────

  List<CommunityPhoto> _parsePhotos(Map<String, dynamic> response) {
    final images = response['images'] as List<dynamic>? ?? const [];
    return images
        .whereType<Map<String, dynamic>>()
        .map(CommunityPhoto.fromJson)
        .where((p) => p.url.isNotEmpty)
        .toList();
  }

  /// [silent] refreshes in place, leaving the current grid on screen instead of
  /// swapping in the skeleton. Used after a background upload lands, where the
  /// user is looking at photos and a full-screen flash reads as a glitch — and
  /// where tearing the grid down would also unmount the widgets driving it.
  Future<void> _loadFirstPage({bool silent = false}) async {
    setState(() {
      if (!silent) _isLoading = true;
      _errorMessage = null;
    });

    final response = await EventsAPI.fetchCommunityGallery(
      eventId: widget.eventId,
      page: 1,
    );

    if (!mounted) return;

    if (response == null || response['success'] != true) {
      // A silent refresh that fails leaves the grid alone — replacing photos
      // the user is looking at with a full-screen error would be worse than
      // showing a slightly stale gallery.
      setState(() {
        _isLoading = false;
        if (!silent) _errorMessage = 'Could not load the gallery';
      });
      return;
    }

    setState(() {
      _photos
        ..clear()
        ..addAll(_parsePhotos(response));
      _page = 1;
      _total = int.tryParse('${response['total']}') ?? _photos.length;
      _totalPages = int.tryParse('${response['total_pages']}') ?? 1;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _page >= _totalPages) return;

    setState(() => _isLoadingMore = true);
    final nextPage = _page + 1;

    final response = await EventsAPI.fetchCommunityGallery(
      eventId: widget.eventId,
      page: nextPage,
    );

    if (!mounted) return;

    setState(() {
      if (response != null && response['success'] == true) {
        _photos.addAll(_parsePhotos(response));
        _page = nextPage;
        _totalPages = int.tryParse('${response['total_pages']}') ?? _totalPages;
      }
      _isLoadingMore = false;
    });
  }

  /// Paging rides scroll notifications rather than a ScrollController — the
  /// grid lives inside the detail screen's NestedScrollView, which owns the
  /// inner controller.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 400) {
      _loadMore();
    }
    return false;
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _openUploader() async {
    final uploaded = await NavigationHelper.navigateTo<bool>(
      context,
      EventCommunityGalleryScreen(
        eventId: widget.eventId,
        eventTitle: widget.eventTitle,
        eventCoverUrl: widget.eventCoverUrl,
      ),
    );

    if (uploaded == true && mounted) _loadFirstPage();
  }

  /// Confirms, deletes, then drops the photo from the grid in place.
  ///
  /// No full reload: the user is looking at the grid, and re-fetching would
  /// reshuffle it under them for the sake of one removed tile.
  Future<void> _confirmDelete(CommunityPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Delete this photo?'),
        content: const Text(
          'It will be removed from the event gallery. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final removed = await EventsAPI.deleteCommunityGalleryImages(
        imageIds: [photo.id],
      );

      if (!mounted) return;

      if (removed.contains(photo.id)) {
        setState(() {
          _photos.removeWhere((p) => p.id == photo.id);
          if (_total > 0) _total--;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo deleted')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (viewerContext) => _CommunityPhotoViewer(
          photos: List.of(_photos),
          initialIndex: index,
          onDelete: (photo) async {
            await _confirmDelete(photo);

            // The viewer holds a snapshot taken when it opened, so once a photo
            // is gone from the grid that snapshot is stale — paging through a
            // deleted photo would show a broken tile. Close back to the grid,
            // which has already updated.
            if (!_photos.any((p) => p.id == photo.id) &&
                viewerContext.mounted) {
              Navigator.of(viewerContext).pop();
            }
          },
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_errorMessage != null) return _buildError();

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        key: const PageStorageKey('event_community_gallery'),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(
            child: _GalleryUploadStatus(
              eventId: widget.eventId,
              primaryColor: widget.primaryColor,
            ),
          ),
          if (_photos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildTile(_photos[index], index),
                  childCount: _photos.length,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: _isLoadingMore ? 60 : 20,
              child: _isLoadingMore
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _photos.isEmpty
                      ? 'Community gallery'
                      : '$_total photo${_total == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Shared by people who were there',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _openUploader,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add_a_photo_outlined, size: 17),
            label: const Text(
              'Add photos',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(CommunityPhoto photo, int index) {
    return GestureDetector(
      onTap: () => _openViewer(index),
      // Long-press to delete, so the grid stays clean for the common case of
      // just looking. The viewer carries an explicit button for discoverability.
      onLongPress: photo.canDelete ? () => _confirmDelete(photo) : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: photo.thumb,
              fit: BoxFit.cover,
              memCacheWidth: 400,
              placeholder: (context, url) =>
                  Container(color: Colors.grey.shade200),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade200,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 22,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
          if (photo.canDelete)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.more_horiz,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No photos yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Were you at this event? Be the first to share your photos with '
            'the community.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _openUploader,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text(
              'Share your photos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Could not load the gallery',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadFirstPage,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-zoomable viewer with uploader credit.
class _CommunityPhotoViewer extends StatefulWidget {
  final List<CommunityPhoto> photos;
  final int initialIndex;

  /// Deletion is owned by the tab, which holds the grid this viewer is a window
  /// onto — so one confirm/API path serves both, and the grid updates whichever
  /// place the delete was triggered from.
  final Future<void> Function(CommunityPhoto photo) onDelete;

  const _CommunityPhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_CommunityPhotoViewer> createState() => _CommunityPhotoViewerState();
}

class _CommunityPhotoViewerState extends State<_CommunityPhotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.photos[i].url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 48,
                    ),
                  ),
                ),
              );
            },
          ),

          // Close + counter
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1} / ${widget.photos.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (photo.canDelete)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                      onPressed: () => widget.onDelete(photo),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),

          // Uploader credit
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      backgroundImage: photo.uploaderAvatar.isNotEmpty
                          ? CachedNetworkImageProvider(photo.uploaderAvatar)
                          : null,
                      child: photo.uploaderAvatar.isEmpty
                          ? Text(
                              photo.uploaderName.characters.first.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            photo.uploaderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (photo.takenAt != null)
                            Text(
                              DateFormat('d MMM yyyy').format(photo.takenAt!),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live status strip for a background gallery upload.
///
/// The upload no longer blocks the screen that started it, so this is where the
/// user finds out how it went — including the case that matters most on a bad
/// connection: some photos landed and some did not, with a way to retry just
/// the stragglers rather than re-picking the whole gallery.
///
/// Purely presentational. Reloading the grid on completion is the parent's job
/// (see `_onUploadsChanged`): this widget is inside the scroll view that a
/// reload tears down, so anything it remembered would be destroyed by the very
/// refresh it asked for.
class _GalleryUploadStatus extends StatelessWidget {
  final String eventId;
  final Color primaryColor;

  const _GalleryUploadStatus({
    required this.eventId,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryUploadProvider>(
      builder: (context, provider, _) {
        final batches = provider.batches.values
            .where((b) => b.eventId == eventId)
            .toList();

        if (batches.isEmpty) return const SizedBox.shrink();
        final batch = batches.last;

        if (batch.status == GalleryBatchStatus.completed) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF7EE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primaryColor.withOpacity(0.2)),
            ),
            child: batch.status == GalleryBatchStatus.uploading
                ? _buildProgress(batch)
                : _buildFailure(context, provider, batch),
          ),
        );
      },
    );
  }

  Widget _buildProgress(GalleryUploadBatch batch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sharing ${batch.uploaded} of ${batch.total} photos',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Text(
              '${(batch.progress * 100).round()}%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: batch.progress,
            minHeight: 5,
            backgroundColor: Colors.grey.shade200,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Keep using the app — this carries on in the background.',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildFailure(
    BuildContext context,
    GalleryUploadProvider provider,
    GalleryUploadBatch batch,
  ) {
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: Colors.red.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batch.error ?? 'Some photos did not upload',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'The photos that did upload are already in the gallery.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => provider.retryFailed(batch.id),
          child: Text(
            'Retry',
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          color: Colors.grey.shade500,
          onPressed: () => provider.dismiss(batch.id),
        ),
      ],
    );
  }
}
