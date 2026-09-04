import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/screens/media/gallery_arrange_screen.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:drivelife/services/user_service.dart';
import 'package:drivelife/widgets/events/event_community_gallery_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Who put a gallery together.
///
/// A gallery is one person's named batch of photos attached to an event or a
/// venue, which is why this is a single uploader rather than a list — the
/// community pool for an entity is the sum of its galleries.
class GalleryOwner {
  final int userId;
  final String name;
  final String handle;
  final String avatarUrl;

  const GalleryOwner({
    required this.userId,
    this.name = '',
    this.handle = '',
    this.avatarUrl = '',
  });

  /// "@apex.media", falling back to the display name when there is no handle.
  String get displayHandle {
    if (handle.isNotEmpty) return handle.startsWith('@') ? handle : '@$handle';
    return name.isEmpty ? '' : name;
  }
}

/// Full-screen view of one gallery: cover, then everything else.
///
/// The cover is whatever the entity's owner chose (see the set-cover endpoint);
/// with none chosen the first photo stands in, so the layout never collapses.
class GalleryViewScreen extends StatefulWidget {
  /// One specific gallery. The only way to open a gallery that is tagged to
  /// nothing; when set it takes precedence over [entityId].
  final int? galleryId;

  /// Event or venue id the gallery hangs off, or '' for a standalone gallery.
  final String entityId;

  /// 'event' or 'venue'.
  final String entityType;

  /// Name the uploader gave it, e.g. "Supercar Sunday". Falls back to the
  /// entity's own title when the batch was never named.
  final String? galleryName;

  /// Entity title, used as the heading when there is no gallery name.
  final String entityTitle;

  /// Shown in the date line. The entity's date for an event; a venue has none.
  final DateTime? date;

  /// Pre-formatted date, as the gallery cards already carry ("24/05/2026").
  /// Preferred over [date] so a card does not have to parse and reformat.
  final String? dateLabel;

  /// Known up front from the card that opened this; otherwise taken from the
  /// photos once they load.
  final GalleryOwner? owner;

  /// Public URL, for the share sheet.
  final String? shareUrl;

  /// Called as soon as something here changes what a list showing this gallery
  /// would render — a new cover, a reorder, a delete.
  ///
  /// A callback rather than a pop result because the iOS back-swipe pops with
  /// no result of its own, and blocking the pop to supply one is what stopped
  /// that swipe from working at all.
  final VoidCallback? onChanged;

  const GalleryViewScreen({
    super.key,
    this.galleryId,
    this.entityId = '',
    required this.entityTitle,
    this.entityType = 'event',
    this.galleryName,
    this.date,
    this.dateLabel,
    this.owner,
    this.shareUrl,
    this.onChanged,
  });

  @override
  State<GalleryViewScreen> createState() => _GalleryViewScreenState();
}

class _GalleryViewScreenState extends State<GalleryViewScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  final _userService = UserService();

  final List<CommunityPhoto> _photos = [];
  GalleryOwner? _owner;

  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  bool _loading = true;
  bool _loadingMore = false;

  /// Whether this viewer may curate — reorder and choose the cover. Decided
  /// server-side: the gallery's own owner for a standalone gallery, the event
  /// or venue owner for one tagged to an entity.
  bool _canCurate = false;

  /// The linked entity's image, when the gallery has a link and that entity
  /// has one. Null otherwise — the header then shows the name alone rather
  /// than an empty box.
  String? _entityImage;

  /// Tags on the whole gallery. Per-photo tags are not shown here — they
  /// belong to their photo, not to the gallery as a whole.
  List<GalleryTag> _galleryTags = const [];

  /// Tags on individual photos, keyed by photo row id.
  Map<int, List<GalleryTag>> _photoTags = const {};
  bool _following = false;
  bool _followBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _owner = widget.owner;
    _load();
  }

  String get _title =>
      (widget.galleryName != null && widget.galleryName!.isNotEmpty)
      ? widget.galleryName!
      : widget.entityTitle;

  /// The owner's chosen cover, else the first photo.
  CommunityPhoto? get _cover {
    if (_photos.isEmpty) return null;
    for (final photo in _photos) {
      if (photo.isCover) return photo;
    }
    return _photos.first;
  }

  /// Everything except the cover, in order.
  List<CommunityPhoto> get _rest {
    final cover = _cover;
    if (cover == null) return const [];
    return _photos.where((p) => p.id != cover.id).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final response = await EventsAPI.fetchCommunityGallery(
      galleryId: widget.galleryId,
      eventId: widget.entityId,
      page: 1,
      entityType: widget.entityType,
    );

    if (!mounted) return;

    if (response == null || response['success'] != true) {
      setState(() {
        _loading = false;
        _error = 'Could not load this gallery';
      });
      return;
    }

    setState(() {
      _photos
        ..clear()
        ..addAll(_parse(response));
      _page = 1;
      _total = int.tryParse('${response['total']}') ?? _photos.length;
      _totalPages = int.tryParse('${response['total_pages']}') ?? 1;
      // Named is_event_owner for the app already reading it; it means "may
      // curate this gallery".
      _canCurate = response['is_event_owner'] == true;
      _entityImage = _firstLinkImage(response);
      _loading = false;

      // No owner passed in — take it from the cover photo's uploader, which
      // for a single-person gallery is the person who made it.
      _owner ??= _ownerFromPhotos();
    });

    // After the photos, not before: tags are supporting detail and should
    // never hold up the gallery itself.
    unawaited(_loadTags());
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;

    setState(() => _loadingMore = true);
    final next = _page + 1;

    final response = await EventsAPI.fetchCommunityGallery(
      galleryId: widget.galleryId,
      eventId: widget.entityId,
      page: next,
      entityType: widget.entityType,
    );

    if (!mounted) return;

    setState(() {
      if (response != null && response['success'] == true) {
        _photos.addAll(_parse(response));
        _page = next;
        _totalPages = int.tryParse('${response['total_pages']}') ?? _totalPages;
      }
      _loadingMore = false;
    });
  }

  /// Tag labels to show over one photo: its own, plus the gallery's.
  List<String> _labelsForPhoto(CommunityPhoto photo) {
    String label(GalleryTag tag) =>
        tag.kind == TagKind.vehicle ? tag.label : '@${tag.label}';

    return [
      ...(_photoTags[photo.id] ?? const <GalleryTag>[]).map(label),
      ..._galleryTags.map(label),
    ];
  }

  /// Loads the gallery-wide tags.
  ///
  /// Quiet on failure: a gallery that loads without its tag row is far better
  /// than an error over a gallery that displays perfectly well.
  Future<void> _loadTags() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return;

    try {
      final tags = await EventsAPI.fetchGalleryTags(galleryId: galleryId);
      if (!mounted) return;

      final wide = <GalleryTag>[];
      final perPhoto = <int, List<GalleryTag>>{};

      for (final raw in tags) {
        final mediaId = int.tryParse('${raw['media_id']}') ?? 0;
        final tag = GalleryTag.fromJson(raw);

        if (mediaId == 0) {
          wide.add(tag);
        } else {
          perPhoto.putIfAbsent(mediaId, () => []).add(tag);
        }
      }

      setState(() {
        _galleryTags = wide;
        _photoTags = perPhoto;
      });
    } catch (_) {
      // Leave the row hidden.
    }
  }

  /// Image of the first linked entity that has one.
  ///
  /// A gallery may link to nothing, or to something with no cover set, so this
  /// is null far more often than not and the header has to cope either way.
  String? _firstLinkImage(Map<String, dynamic> response) {
    final links = response['links'] as List<dynamic>? ?? const [];

    for (final link in links.whereType<Map>()) {
      final image = link['image']?.toString() ?? '';
      if (image.isNotEmpty) return image;
    }

    return null;
  }

  List<CommunityPhoto> _parse(Map<String, dynamic> response) {
    final images = response['images'] as List<dynamic>? ?? const [];
    return images
        .whereType<Map<String, dynamic>>()
        .map(CommunityPhoto.fromJson)
        .where((p) => p.url.isNotEmpty)
        .toList();
  }

  GalleryOwner? _ownerFromPhotos() {
    final cover = _cover;
    if (cover == null) return null;
    return GalleryOwner(
      userId: 0,
      name: cover.uploaderName,
      avatarUrl: cover.uploaderAvatar,
    );
  }

  /// Pulls in every remaining page before arranging.
  ///
  /// Arranging a partial list is a data bug, not just a UI limit: the reorder
  /// endpoint positions the ids it is given and leaves the rest with a null
  /// sort_order, so photos that were never loaded would silently drop behind
  /// the ones that were.
  Future<bool> _loadAllPhotos() async {
    while (_page < _totalPages) {
      final before = _photos.length;
      await _loadMore();

      if (!mounted) return false;

      // Guard against a page that returns nothing: better to arrange what we
      // have than to spin forever.
      if (_photos.length == before) break;
    }

    return mounted;
  }

  /// Opens the arrange screen and reloads only if something actually changed.
  ///
  /// Reloading rather than trusting the local list: the arrange screen may
  /// have saved several moves, and the server's order is the truth.
  Future<void> _openArrange() async {
    // _loadMore owns _loadingMore, which is also what drives the spinner, so
    // this must not set it - _loadMore bails out early while it is set.
    if (_page < _totalPages && !await _loadAllPhotos()) return;

    if (!mounted) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GalleryArrangeScreen(
          galleryId: widget.galleryId,
          entityId: widget.entityId,
          entityType: widget.entityType,
          photos: List<CommunityPhoto>.from(_photos),
          primaryColor: _gold,
        ),
      ),
    );

    if (changed == true && mounted) {
      _markChanged();
      await _load();
    }
  }

  /// Sets the cover straight from a tile, without a trip through arranging —
  /// the far more common of the two jobs.
  Future<void> _setCover(CommunityPhoto photo) async {
    final previous = List<CommunityPhoto>.from(_photos);

    setState(() {
      for (var i = 0; i < _photos.length; i++) {
        _photos[i] = _photos[i].copyWith(isCover: _photos[i].id == photo.id);
      }
    });

    try {
      await EventsAPI.setCommunityGalleryCover(
        galleryId: widget.galleryId,
        eventId: widget.entityId,
        imageId: photo.id,
        entityType: widget.entityType,
      );

      if (mounted) _markChanged();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _photos
          ..clear()
          ..addAll(previous);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Removes one photo from the gallery.
  ///
  /// Separate from deleting the gallery: a contributor may remove their own
  /// photo without being able to touch anything else, which is the rule the
  /// delete endpoint enforces and `canDelete` mirrors.
  Future<void> _deletePhoto(CommunityPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('It will be removed from the gallery for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final wasCover = photo.isCover;

    try {
      await EventsAPI.deleteCommunityGalleryImages(imageIds: [photo.id]);
      if (!mounted) return;

      setState(() {
        _photos.removeWhere((p) => p.id == photo.id);
        if (_total > 0) _total -= 1;
      });
      _markChanged();

      // Deleting the cover changes what every list shows for this gallery,
      // and the server picks the replacement — so take its answer.
      if (wasCover && mounted) await _load();
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

  /// Long-press actions on one photo: make it the cover, or remove it.
  ///
  /// Deliberately about THIS photo. Deleting the whole gallery lives on its
  /// tile in the profile grid, where the gallery is the thing being pointed
  /// at — offering both here made it far too easy to wipe a gallery while
  /// meaning to drop one bad shot.
  Future<void> _showCurateActions(CommunityPhoto photo) async {
    // Curators get both actions; a contributor who only uploaded this photo
    // still gets to remove it.
    if (!_canCurate && !photo.canDelete) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            if (_canCurate)
              photo.isCover
                  // Shown disabled rather than hidden, so the sheet does not
                  // change height depending on which photo you held.
                  ? const ListTile(
                      leading: Icon(Icons.star, color: _gold),
                      title: Text('Already the cover'),
                      enabled: false,
                    )
                  : ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: const Text('Use as cover'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _setCover(photo);
                      },
                    ),
            if (photo.canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deletePhoto(photo);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final owner = _owner;
    if (owner == null || owner.userId <= 0 || _followBusy) return;

    final sessionUser = context.read<AccountManager>().activeUser;
    if (sessionUser == null) return;

    // Optimistic — a follow button that waits on the network feels broken.
    final wasFollowing = _following;
    setState(() {
      _following = !wasFollowing;
      _followBusy = true;
    });

    final ok = await _userService.followUser(owner.userId, sessionUser.id);

    if (!mounted) return;
    setState(() {
      if (!ok) _following = wasFollowing;
      _followBusy = false;
    });
  }

  void _share() {
    final url = widget.shareUrl;

    // share_plus 12's API. The rest of the app still calls the deprecated
    // Share.share; this is the current form rather than matching that.
    SharePlus.instance.share(
      ShareParams(
        text: url == null || url.isEmpty ? _title : '$_title\n$url',
        subject: _title,
      ),
    );
  }

  void _openViewer(CommunityPhoto photo) {
    final index = _photos.indexWhere((p) => p.id == photo.id);
    if (index < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CommunityPhotoViewer(
          photos: List.of(_photos),
          initialIndex: index,
          // Gallery-wide tags apply to every photo, so they show alongside
          // whatever is tagged on this one specifically.
          tagsFor: _labelsForPhoto,
        ),
      ),
    );
  }

  /// Tells the caller its cover, order or count is now stale. Fires the moment
  /// the change lands rather than on the way out, so every way of leaving —
  /// the back arrow, the iOS edge swipe, the Android back button — carries it.
  void _markChanged() => widget.onChanged?.call();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leadingWidth: 40,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          // The linked entity's image, and only when there is one. A gallery
          // need not be linked to anything, and an entity need not have a
          // cover — an initials placeholder in those cases is noise, so the
          // name simply takes the full width instead.
          if (_entityImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: _entityImage!,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                memCacheWidth: 140,
                placeholder: (_, __) => Container(
                  width: 46,
                  height: 46,
                  color: Colors.grey.shade200,
                ),
                // Falling back to a blank box would reintroduce exactly the
                // empty square this replaced, so drop it entirely.
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Only for whoever may curate; everyone else sees an unchanged bar.
        if (_canCurate)
          IconButton(
            icon: const Icon(Icons.swap_vert, color: _ink, size: 23),
            tooltip: 'Arrange photos',
            onPressed: _openArrange,
          ),
        IconButton(
          icon: const Icon(Icons.ios_share, color: _ink, size: 23),
          onPressed: _share,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
    );
  }

  /// "24/05/2026 · 173 photos", dropping the date when there isn't one — a
  /// venue gallery has no date, and a leading separator would look broken.
  String get _subtitle {
    final count = _loading ? null : (_total > 0 ? _total : _photos.length);
    final label = (widget.dateLabel != null && widget.dateLabel!.isNotEmpty)
        ? widget.dateLabel!
        : (widget.date == null
              ? null
              : DateFormat('dd/MM/yyyy').format(widget.date!));

    final parts = <String>[
      if (label != null) label,
      if (count != null) '$count photo${count == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 34, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: _muted)),
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
          child: Text(
            'No photos in this gallery yet.',
            style: TextStyle(color: _muted),
          ),
        ),
      );
    }

    final cover = _cover!;
    final rest = _rest;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 500) {
          _loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          if (_owner != null) SliverToBoxAdapter(child: _buildOwnerRow()),

          if (_galleryTags.isNotEmpty)
            SliverToBoxAdapter(child: _buildTagStrip()),

          // Cover runs edge to edge; the grid below is what it introduces.
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () => _openViewer(cover),
              onLongPress: () => _showCurateActions(cover),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: CachedNetworkImage(
                  imageUrl: cover.url,
                  fit: BoxFit.cover,
                  memCacheWidth: 1400,
                  placeholder: (_, __) =>
                      Container(color: Colors.grey.shade200),
                  errorWidget: (_, __, ___) =>
                      Container(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),

          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => GestureDetector(
                onTap: () => _openViewer(rest[index]),
                onLongPress: () => _showCurateActions(rest[index]),
                child: CachedNetworkImage(
                  imageUrl: rest[index].thumb,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  placeholder: (_, __) =>
                      Container(color: Colors.grey.shade200),
                  errorWidget: (_, __, ___) =>
                      Container(color: Colors.grey.shade200),
                ),
              ),
              childCount: rest.length,
            ),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: _loadingMore ? 64 : 24,
              child: _loadingMore
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Who and what is in this gallery, as a horizontal strip.
  ///
  /// Horizontal rather than wrapped: a gallery from a big meet can carry a
  /// dozen tags, and letting them wrap would push the cover off the screen —
  /// the cover is what the page is for.
  Widget _buildTagStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'In this gallery',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _galleryTags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tag = _galleryTags[index];
                final isVehicle = tag.kind == TagKind.vehicle;

                return Container(
                  padding: const EdgeInsets.only(
                    left: 4,
                    right: 12,
                    top: 4,
                    bottom: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GalleryTagAvatar(
                        imageUrl: tag.avatarUrl,
                        isVehicle: isVehicle,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isVehicle ? tag.label : '@${tag.label}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerRow() {
    final owner = _owner!;
    final canFollow = owner.userId > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: owner.avatarUrl.isEmpty
                ? null
                : CachedNetworkImageProvider(owner.avatarUrl),
            child: owner.avatarUrl.isEmpty
                ? Icon(Icons.person, color: Colors.grey.shade500)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  owner.displayHandle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  owner.name.isEmpty ? 'Gallery' : 'Gallery by ${owner.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: _muted),
                ),
              ],
            ),
          ),
          if (canFollow)
            OutlinedButton(
              onPressed: _followBusy ? null : _toggleFollow,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _ink, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              child: Text(
                _following ? 'Following' : 'Follow',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              CircleAvatar(radius: 22, backgroundColor: Colors.grey.shade200),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 130,
                      color: Colors.grey.shade200,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 90,
                      color: Colors.grey.shade200,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(color: Colors.grey.shade200),
        ),
        const SizedBox(height: 2),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => Container(color: Colors.grey.shade200),
        ),
      ],
    );
  }
}
