import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/media_api.dart';
import 'package:drivelife/main.dart';
import 'package:drivelife/models/media_models.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/media/images_of_you_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

/// The Media tab: pending tag approvals, event galleries, and popular images.
///
/// The three sections load independently so a slow or failing one never holds
/// up the others. A section that comes back *empty* hides itself; one that
/// *fails* shows an inline message with a retry, so a total outage reads as
/// broken rather than as a blank page.
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

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
  String? _galleriesError;

  List<PopularImage> _popular = [];
  bool _loadingPopular = true;
  String? _popularError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() {
    return Future.wait([
      _loadPending(),
      _loadGalleries(),
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

  /// Events open straight on their community gallery tab — that's the whole
  /// point of the section, whether it's browsing photos or adding your own.
  void _openGallery(EventGallery gallery) {
    Navigator.pushNamed(
      context,
      AppRoutes.eventDetail,
      arguments: {
        'event': {'id': gallery.eventId, 'site': 'GB'},
        'initialTabIndex': 2,
      },
    );
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
      body: RefreshIndicator(
        color: theme.primaryColor,
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const _SearchRow(),
            ..._pendingSection(theme),
            ..._gallerySection(),
            ..._popularSection(),
          ],
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
        _SectionHeader(title: 'Event galleries'),
        _GalleryRowSkeleton(),
        SizedBox(height: 28),
      ];
    }

    if (_galleriesError != null) {
      return [
        const _SectionHeader(title: 'Event galleries'),
        _SectionMessage(message: _galleriesError!, onRetry: _loadGalleries),
        const SizedBox(height: 28),
      ];
    }

    if (_galleries.data.isEmpty) return const [];

    return [
      _SectionHeader(
        title: 'Event galleries',
        actionLabel: 'See all',
        // Events tab (bottom nav index 1), same target as the feed's pills.
        onAction: () => context.read<BottomNavProvider>().setIndex(1),
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
  final VoidCallback onRetry;

  const _SectionMessage({required this.message, required this.onRetry});

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
          Icon(Icons.error_outline, size: 17, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
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

/// Search field paired with the primary "Add a gallery" action.
class _SearchRow extends StatelessWidget {
  const _SearchRow();

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
            child: Container(
              height: _MediaScreenState._controlHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 19, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search galleries, events',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {},
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
          Text(
            gallery.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            gallery.subtitle,
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
