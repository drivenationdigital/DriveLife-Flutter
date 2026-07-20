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

  const CommunityPhoto({
    required this.id,
    required this.url,
    required this.thumb,
    required this.uploaderName,
    required this.uploaderAvatar,
    this.takenAt,
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

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
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

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final response = await EventsAPI.fetchCommunityGallery(
      eventId: widget.eventId,
      page: 1,
    );

    if (!mounted) return;

    if (response == null || response['success'] != true) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load the gallery';
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

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CommunityPhotoViewer(
          photos: List.of(_photos),
          initialIndex: index,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: photo.thumb,
          fit: BoxFit.cover,
          memCacheWidth: 400,
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
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

  const _CommunityPhotoViewer({
    required this.photos,
    required this.initialIndex,
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
