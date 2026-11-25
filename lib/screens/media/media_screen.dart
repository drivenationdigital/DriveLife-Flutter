import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/media_api.dart';
import 'package:drivelife/models/media_models.dart';
import 'package:drivelife/providers/pending_tags_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/media/images_of_you_screen.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:drivelife/screens/media/new_gallery_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/screens/media/all_galleries_screen.dart';
import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/screens/media/all_videos_screen.dart';
import 'package:drivelife/screens/media/video_upload_screen.dart';
import 'package:drivelife/screens/media/video_watch_screen.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:drivelife/widgets/media/video_upload_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

/// The Media tab: pending tag approvals, galleries (events and venues), and
/// popular images.
///
/// The three sections load independently so a slow or failing one never holds
/// up the others. A section that comes back *empty* hides itself; one that
/// *fails* shows an inline message with a retry, so a total outage reads as
/// broken rather than as a blank page.
class MediaScreen extends StatefulWidget {
  /// The shell's scroll listener.
  ///
  /// ── WHY THE BOTTOM BAR STAYED PUT HERE ──────────────────────────
  ///
  /// Every other destination takes this and hands it every scroll
  /// notification, which is the only way the shell knows to take its
  /// bar away and bring it back. This screen never took one, so it
  /// scrolled in silence and the bar sat there through all of it.
  ///
  /// Nullable because the screen is also perfectly usable on its own,
  /// where there is no bar to move.
  final ChromeVisibility? chrome;

  const MediaScreen({super.key, this.chrome});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const double _hPadding = 16;

  /// Search field and "Add a gallery" share this so they line up exactly.
  static const double _controlHeight = 48;

  List<PendingImage> _pending = [];

  /// Whole-queue count from the API, which can exceed the thumbnails fetched.
  int _pendingTotal = 0;
  bool _loadingPending = true;
  String? _pendingError;

  EventGalleriesResponse _galleries = const EventGalleriesResponse();
  bool _loadingGalleries = true;

  /// DriveLife's own long-form videos, and how far through each of
  /// them this person has watched.
  List<LongVideo> _videos = const [];
  Map<String, int> _watched = const {};
  bool _loadingVideos = true;

  /// Whether to offer the Upload control.
  ///
  /// A courtesy only. The endpoints check the role themselves - see
  /// dl_videos_is_admin - because a hidden button is not a permission.
  bool _canUploadVideos = false;
  String? _galleriesError;

  List<PopularImage> _popular = [];
  bool _loadingPopular = true;
  String? _popularError;

  /// Batches already folded into the list, so one finished upload triggers one
  /// refresh rather than one per notification.
  final Set<String> _handledBatches = {};

  GalleryUploadProvider? _uploads;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

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

  /// Refreshes the Galleries row when an upload lands.
  ///
  /// Publishing returns you to this tab, and without this the gallery you just
  /// made is simply absent until you think to pull to refresh — which reads as
  /// the upload having failed.
  void _onUploadsChanged() {
    final provider = _uploads;
    if (provider == null || !mounted) return;

    final finished = provider.batches.values
        .where((b) => b.isFinished && b.uploaded > 0)
        .map((b) => b.id)
        .where((id) => !_handledBatches.contains(id))
        .toList();

    if (finished.isEmpty) return;

    _handledBatches.addAll(finished);
    _loadGalleries();
  }

  Future<void> _loadAll() {
    return Future.wait([
      _loadPending(),
      _loadGalleries(),
      _loadVideos(),
      _loadPopular(),
    ]);
  }

  Future<void> _loadPending() async {
    try {
      final result = await MediaAPI.getMatches(status: 'pending', limit: 12);
      if (!mounted) return;
      setState(() {
        _pending = result.data;
        _pendingTotal = result.pending;
        _pendingError = null;
        _loadingPending = false;
      });

      // Same answer, so the badge does not need its own request — but it does
      // need telling, or a pull-to-refresh here would leave it stale.
      unawaited(context.read<PendingTagsProvider>().refresh());
    } on MediaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pending = [];
        _pendingTotal = 0;
        _pendingError = e.message;
        _loadingPending = false;
      });
    }
  }

  /// The videos row.
  ///
  /// Never throws and never shows an error: this section is an extra
  /// on a screen that works without it, so a failure hides the row
  /// rather than putting a retry button in front of somebody who came
  /// here to look at photographs.
  Future<void> _loadVideos() async {
    try {
      final videos = await VideosAPI.list(limit: 10);
      final watched = await WatchProgress.positions();
      final permission = await VideosAPI.uploadPermission();

      if (!mounted) return;

      setState(() {
        _videos = videos;
        _watched = watched;
        // Both, not either: an administrator on a server with no
        // Stream token would get a button that can only fail.
        _canUploadVideos = permission.canUpload && permission.configured;
        _loadingVideos = false;
      });
    } catch (e) {
      debugPrint('MediaScreen._loadVideos failed: $e');

      if (!mounted) return;

      setState(() {
        _videos = const [];
        _loadingVideos = false;
      });
    }
  }

  Future<void> _openAllVideos() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AllVideosScreen()));

    // Watching, liking or uploading in there changes this row too.
    if (mounted) await _loadVideos();
  }

  Future<void> _uploadVideo() async {
    final published = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const VideoUploadScreen()));

    // Only reload when something actually landed. Backing out of the
    // uploader should not cost a round trip.
    if (published == true && mounted) await _loadVideos();
  }

  Future<void> _openVideo(LongVideo video) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VideoWatchScreen(video: video)));

    if (!mounted) return;

    // The whole row, not just the watch positions.
    //
    // Positions alone was the bug: somebody who liked or commented
    // while watching came back to the old counts, and pulling to
    // refresh did not always help because the response was being
    // served from a cache - see the headers on dl_videos_list.
    await _loadVideos();
  }

  Future<void> _loadGalleries() async {
    try {
      final result = await MediaAPI.getEventGalleries(limit: 5);

      if (!mounted) return;
      setState(() {
        _galleries = result;
        _galleriesError = null;
        _loadingGalleries = false;
      });
    } on MediaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _galleries = const EventGalleriesResponse();
        _galleriesError = e.message;
        _loadingGalleries = false;
      });
    }
  }

  Future<void> _loadPopular() async {
    try {
      final result = await MediaAPI.getPopularImages(limit: 30);
      if (!mounted) return;
      setState(() {
        _popular = result;
        _popularError = null;
        _loadingPopular = false;
      });
    } on MediaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _popular = [];
        _popularError = e.message;
        _loadingPopular = false;
      });
    }
  }

  Future<void> _openReview() async {
    await NavigationHelper.navigateTo(context, const ImagesOfYouScreen());
    // Whatever they approved or declined in there changes the queue.
    if (mounted) await _loadPending();
  }

  /// Opens the gallery itself, not the event or venue behind it.
  ///
  /// These cards are galleries, so tapping one shows its photos — cover first,
  /// then the grid. Getting to the entity is a step from there, rather than
  /// the other way round.
  Future<void> _openGallery(EventGallery gallery) async {
    // By gallery id where there is one: that is what lets the gallery's owner
    // curate it from here, and what keeps two galleries on one event apart.
    var changed = false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryViewScreen(
          galleryId: gallery.galleryId,
          // entityId, not eventId: a venue's card has no event id.
          entityId: gallery.entityId.toString(),
          entityType: gallery.entityType,
          // A location group has no entity id — Google's place id is what
          // addresses it.
          placeId: gallery.placeId,
          entityTitle: gallery.title,
          galleryName: gallery.galleryName,
          dateLabel: gallery.dateLabel,
          onChanged: () => changed = true,
        ),
      ),
    );

    // A new cover, a reorder or a deleted gallery all change these cards, and
    // the covers are resolved server-side — so refetch rather than patch.
    if (changed && mounted) await _loadGalleries();
  }

  void _openPost(PopularImage image) {
    Navigator.pushNamed(
      context,
      AppRoutes.postDetail,
      arguments: {'postId': image.postId},
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      // Every scroll in here reports to the shell through this one
      // listener, which is what takes the bottom bar away and brings
      // it back. Harmless when there is no shell.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          color: theme.primaryColor,
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _SearchRow(onGalleryCreated: _loadAll),
              // Uploads in flight, above everything. They are the one
              // thing on this screen somebody is actively waiting on.
              const VideoUploadTiles(),
              ..._pendingSection(theme),
              ..._gallerySection(),
              ..._videoSection(),
              ..._popularSection(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pendingSection(ThemeProvider theme) {
    if (_loadingPending) {
      return const [
        _SectionHeader(title: 'Pending images of you'),
        _PendingRowSkeleton(),
        SizedBox(height: 28),
      ];
    }

    if (_pendingError != null) {
      return [
        const _SectionHeader(title: 'Pending images of you'),
        _SectionMessage(message: _pendingError!, onRetry: _loadPending),
        const SizedBox(height: 28),
      ];
    }

    if (_pending.isEmpty) return const [];

    return [
      _SectionHeader(
        title: 'Pending images of you',
        badgeCount: _pendingTotal > 0 ? _pendingTotal : _pending.length,
        badgeColor: theme.primaryColor,
        actionLabel: 'Review all',
        onAction: _openReview,
      ),
      _PendingRow(images: _pending, onTap: _openReview),
      const SizedBox(height: 28),
    ];
  }

  List<Widget> _gallerySection() {
    if (_loadingGalleries) {
      return const [
        _SectionHeader(title: 'Galleries'),
        _GalleryRowSkeleton(),
        SizedBox(height: 28),
      ];
    }

    if (_galleriesError != null) {
      return [
        const _SectionHeader(title: 'Galleries'),
        _SectionMessage(message: _galleriesError!, onRetry: _loadGalleries),
        const SizedBox(height: 28),
      ];
    }

    // Nothing to show and nothing being searched for: the section hides
    // rather than explaining its own emptiness.
    if (_galleries.data.isEmpty) return const [];

    // One row again. Individual galleries no longer appear here at all — this
    // feed is events, venues and places, plus the upcoming-event cards that
    // invite the first upload. A gallery of your own is on your profile.
    return [
      _SectionHeader(
        title: 'Galleries',
        actionLabel: 'See all',
        // Every gallery, newest first, with filters. This used to jump to the
        // Events tab — a different thing entirely, and no way to browse
        // galleries at all.
        onAction: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AllGalleriesScreen()));
          // A cover, delete or new gallery there changes this row too.
          if (mounted) await _loadGalleries();
        },
      ),
      // Explain the cards with no badge, or their emptiness reads as broken
      // rather than as an invitation.
      if (_galleries.hasEmptyGalleries)
        Padding(
          padding: const EdgeInsets.fromLTRB(_hPadding, 0, _hPadding, 12),
          child: Text(
            'Some of these have no photos yet. Were you there? Add yours.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      _GalleryRow(galleries: _galleries.data, onTap: _openGallery),
      const SizedBox(height: 28),
    ];
  }

  List<Widget> _videoSection() {
    if (_loadingVideos) {
      return const [
        _SectionHeader(title: 'Videos'),
        _GalleryRowSkeleton(),
        SizedBox(height: 28),
      ];
    }

    // Nothing to show hides the row entirely, same as Galleries - an
    // empty "Videos" heading is worse than no heading.
    //
    // Except for an administrator, who needs somewhere to put the
    // first one. For them an empty section is the way in rather than
    // a dead end.
    if (_videos.isEmpty && !_canUploadVideos) return const [];

    return [
      _SectionHeader(
        title: 'Videos',
        // "See all" here, like Galleries, rather than Upload. Upload
        // is a button of its own below - see _UploadVideoButton for
        // why it stopped being a word in a header.
        actionLabel: _videos.isEmpty ? null : 'See all',
        onAction: _videos.isEmpty ? null : _openAllVideos,
      ),
      if (_videos.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(_hPadding, 0, _hPadding, 12),
          child: Text(
            'No videos yet. Upload one and it appears here once '
            'Cloudflare has finished processing it.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        )
      else
        _VideoRow(videos: _videos, watched: _watched, onTap: _openVideo),
      if (_canUploadVideos) ...[
        const SizedBox(height: 14),
        _UploadVideoButton(onTap: _uploadVideo),
      ],
      const SizedBox(height: 28),
    ];
  }

  List<Widget> _popularSection() {
    if (_loadingPopular) {
      return const [
        _SectionHeader(title: 'Popular images'),
        _PopularGridSkeleton(),
      ];
    }

    if (_popularError != null) {
      return [
        const _SectionHeader(title: 'Popular images'),
        _SectionMessage(message: _popularError!, onRetry: _loadPopular),
      ];
    }

    if (_popular.isEmpty) return const [];

    return [
      const _SectionHeader(title: 'Popular images'),
      _PopularGrid(images: _popular, onTap: _openPost),
    ];
  }
}

/// Inline failure notice for one section. Sections hide themselves when they
/// come back empty, so without this a total outage renders as a blank page.
class _SectionMessage extends StatelessWidget {
  final String message;

  /// Null for a message that is not a failure — "no results" has nothing to
  /// retry, and offering one implies something went wrong.
  final VoidCallback? onRetry;

  const _SectionMessage({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _MediaScreenState._hPadding,
        0,
        _MediaScreenState._hPadding,
        4,
      ),
      child: Row(
        children: [
          Icon(
            onRetry == null ? Icons.search_off : Icons.error_outline,
            size: 17,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// Grey block that pulses while its section loads.
class _Skeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const _Skeleton({this.width, this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class _PendingRowSkeleton extends StatelessWidget {
  const _PendingRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _PendingRow._size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: _MediaScreenState._hPadding,
        ),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => const _Skeleton(
          width: _PendingRow._size,
          height: _PendingRow._size,
        ),
      ),
    );
  }
}

class _GalleryRowSkeleton extends StatelessWidget {
  const _GalleryRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _GalleryRow._imageHeight + 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: _MediaScreenState._hPadding,
        ),
        itemCount: 2,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => const SizedBox(
          width: _GalleryRow._cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Skeleton(
                width: _GalleryRow._cardWidth,
                height: _GalleryRow._imageHeight,
              ),
              SizedBox(height: 10),
              _Skeleton(width: 170, height: 14, radius: 4),
              SizedBox(height: 6),
              _Skeleton(width: 120, height: 12, radius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularGridSkeleton extends StatelessWidget {
  const _PopularGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 9,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (_, __) => const _Skeleton(radius: 0),
    );
  }
}

/// Way in to the gallery search, paired with "Add a gallery".
///
/// Not a field. Searching here returned five results in a strip you could not
/// filter, while the browse page did the same search properly — two searches
/// over the same galleries that behaved differently. This one opens that one.
class _SearchRow extends StatelessWidget {
  /// Called when a gallery was actually created, so the screen can refresh.
  final Future<void> Function() onGalleryCreated;

  const _SearchRow({required this.onGalleryCreated});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _MediaScreenState._hPadding,
        4,
        _MediaScreenState._hPadding,
        20,
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AllGalleriesScreen(openSearch: true),
                  ),
                ),
                child: Container(
                  height: _MediaScreenState._controlHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 19, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      // Flexible so the hint ellipsises on narrow screens or
                      // with larger text scale rather than overflowing the row.
                      Flexible(
                        child: Text(
                          'Search event or location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const NewGalleryScreen(),
                  ),
                );

                // The upload runs in the background, so photos land over the
                // next while — refresh so the galleries row picks up the new
                // one rather than waiting for the next visit.
                if (created == true) await onGalleryCreated();
              },
              child: const SizedBox(
                height: _MediaScreenState._controlHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Add a gallery',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title with an optional count badge and trailing text action.
class _SectionHeader extends StatelessWidget {
  final String title;
  final int? badgeCount;
  final Color? badgeColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    this.badgeCount,
    this.badgeColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _MediaScreenState._hPadding,
        0,
        _MediaScreenState._hPadding,
        14,
      ),
      child: Row(
        children: [
          // Title and badge share one Expanded. A bare Flexible would compete
          // with a Spacer for the free space and leave the action mid-row
          // instead of against the right edge.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                if (badgeCount != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    constraints: const BoxConstraints(minWidth: 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor ?? Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal strip of thumbnails awaiting approval.
class _PendingRow extends StatelessWidget {
  final List<PendingImage> images;
  final VoidCallback onTap;

  const _PendingRow({required this.images, required this.onTap});

  static const double _size = 118;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: _MediaScreenState._hPadding,
        ),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _NetworkThumb(
                url: images[index].imageUrl,
                width: _size,
                height: _size,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal strip of event gallery cards.
class _GalleryRow extends StatelessWidget {
  final List<EventGallery> galleries;
  final ValueChanged<EventGallery> onTap;

  const _GalleryRow({required this.galleries, required this.onTap});

  static const double _cardWidth = 250;
  static const double _imageHeight = 160;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Image, plus room for the two-line caption beneath it.
      height: _imageHeight + 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: _MediaScreenState._hPadding,
        ),
        itemCount: galleries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) => _GalleryCard(
          gallery: galleries[index],
          onTap: () => onTap(galleries[index]),
        ),
      ),
    );
  }
}

/// The way an administrator adds a video.
///
/// ── WHY IT IS NOT A WORD IN THE SECTION HEADER ──────────────────────
///
/// It was "Upload", in the same small grey slot where every other
/// section says "See all" - so it looked like a link rather than the
/// only way to do the one thing this section exists for, and it sat
/// in the corner of the screen furthest from the thumb.
///
/// Full width, gold, with an icon and a sentence under it. It is
/// shown to perhaps three people in the world and it should be
/// impossible for any of them to miss.
class _UploadVideoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _UploadVideoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _MediaScreenState._hPadding,
      ),
      child: Material(
        color: const Color(0xFFAE9159),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.video_call_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Upload a video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Any length. Admins only.',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Videos row: the Galleries slider, carrying videos.
///
/// Same card width, same image height, same gaps and same padding, so
/// the two rows line up down the page rather than almost lining up.
class _VideoRow extends StatelessWidget {
  final List<LongVideo> videos;

  /// Seconds watched, by post id. Absent means not started.
  final Map<String, int> watched;

  final ValueChanged<LongVideo> onTap;

  const _VideoRow({
    required this.videos,
    required this.watched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _GalleryRow._imageHeight + 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: _MediaScreenState._hPadding,
        ),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final video = videos[index];

          return _VideoCard(
            video: video,
            watchedSeconds: watched[video.postId] ?? 0,
            onTap: () => onTap(video),
          );
        },
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final LongVideo video;
  final int watchedSeconds;
  final VoidCallback onTap;

  const _VideoCard({
    required this.video,
    required this.watchedSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final length = video.lengthLabel;

    // Only a real, partial position counts. Zero is "not started" and
    // anything at or past the end is "finished" - neither deserves a
    // bar, and a full bar on a finished video is just clutter.
    final showProgress =
        watchedSeconds > 0 &&
        video.durationSeconds > 0 &&
        watchedSeconds < video.durationSeconds;

    return SizedBox(
      width: _GalleryRow._cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            // One clip for the card, so the progress bar at the
            // bottom is cut by the same rounded rectangle as the
            // artwork. With a clip of its own, a corner radius on a
            // four-point bar gets clamped and the ends stay square
            // while the picture curves away behind them.
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                _NetworkThumb(
                  url: video.thumbnailUrl,
                  width: _GalleryRow._cardWidth,
                  height: _GalleryRow._imageHeight,
                ),

                // The play button, centred on the artwork. It is the
                // whole reason this card reads as a video rather than a
                // photograph.
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),

                // How far through they got, hugging the bottom edge of
                // the artwork.
                if (showProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: watchedSeconds / video.durationSeconds,
                      minHeight: 4,
                      // Darker than white24, which disappeared over a
                      // pale frame - leaving a gold bar that stopped
                      // in mid-air with nothing behind it.
                      backgroundColor: Colors.black26,
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFFAE9159),
                      ),
                    ),
                  ),

                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onTap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            // The length, or where they are up to once they have
            // started. "12:04 left" answers the question somebody
            // returning to a video is actually asking.
            showProgress
                ? '${LongVideo.formatPosition(video.durationSeconds - watchedSeconds)} left'
                : length,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  final EventGallery gallery;
  final VoidCallback onTap;

  const _GalleryCard({required this.gallery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _GalleryRow._cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _NetworkThumb(
                  url: gallery.coverImageUrl,
                  width: _GalleryRow._cardWidth,
                  height: _GalleryRow._imageHeight,
                ),
              ),
              // No badge on a gallery with no photos — "0 photos" reads as an
              // error where absence reads as an invitation.
              if (gallery.photoCount > 0)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${gallery.photoCount} '
                      'photo${gallery.photoCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              // Ripple sits above the artwork so the whole card reads as tappable.
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onTap,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The gallery's own name when the uploader gave one, else the event.
          Text(
            gallery.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            // A group says what it is; a single gallery says whose it is. The
            // address used to go here, which the title above had usually
            // named already.
            gallery.isGroup ? gallery.kindLabel : gallery.ownerLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// Edge-to-edge three-column grid of popular images.
class _PopularGrid extends StatelessWidget {
  final List<PopularImage> images;
  final ValueChanged<PopularImage> onTap;

  const _PopularGrid({required this.images, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      // Scrolls with the page rather than on its own.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => onTap(images[index]),
          child: _NetworkThumb(url: images[index].imageUrl),
        );
      },
    );
  }
}

/// Shared image tile with consistent loading and failure states.
class _NetworkThumb extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;

  const _NetworkThumb({required this.url, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final source = url;

    if (source == null || source.isEmpty) return _placeholder();

    return CachedNetworkImage(
      imageUrl: source,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (_, __) =>
          SizedBox(width: width, height: height, child: _plain()),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _plain() => Container(color: Colors.grey.shade200);

  Widget _placeholder() => Container(
    width: width,
    height: height,
    color: Colors.grey.shade200,
    child: Icon(
      Icons.image_not_supported_outlined,
      color: Colors.grey.shade400,
      size: 20,
    ),
  );
}
