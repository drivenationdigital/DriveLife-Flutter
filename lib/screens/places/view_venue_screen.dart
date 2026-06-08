import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/models/venue_view_model.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/places/add_venue_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── Brand color constants (match club view) ────────────────────────────
const Color _gold = Color(0xFFC4A062);
const Color _ink = Color(0xFF0B0B0B);
const Color _muted = Color(0xFF8A8A8A);
const Color _chip = Color(0xFFEFEFEF);

class VenueDetailScreen extends StatefulWidget {
  final String venueId;

  const VenueDetailScreen({super.key, required this.venueId});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  VenueDetail? _venue;
  bool _isLoading = true;
  bool _isFollowing = false;
  String? _errorMessage;

  // Posts state with infinite scroll
  final List<Map<String, dynamic>> _posts = [];
  bool _postsLoaded = false;
  bool _loadingPosts = false;
  bool _hasMorePosts = true;
  int _postsPage = 0;
  static const int _pageSize = 10;
  final ScrollController _updatesScrollController = ScrollController();

  // Upload completion tracking
  final Set<String> _completedUploads = {};
  bool _refreshScheduled = false;
  UploadPostProvider? _uploadProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // was 3
    _updatesScrollController.addListener(_onUpdatesScroll);
    _loadVenue();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _updatesScrollController.removeListener(_onUpdatesScroll);
    _updatesScrollController.dispose();
    _uploadProvider?.removeListener(_onUploadsChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final provider = Provider.of<UploadPostProvider>(context, listen: false);
    if (_uploadProvider != provider) {
      _uploadProvider?.removeListener(_onUploadsChanged);
      _uploadProvider = provider;
      _uploadProvider!.addListener(_onUploadsChanged);
    }
  }

  void _onUploadsChanged() {
    if (!mounted || _uploadProvider == null) return;
    _checkUploadCompletions(_uploadProvider!.uploads);
  }

  void _checkUploadCompletions(Map<String, UploadPostProgress> uploads) {
    if (!mounted) return;

    bool needsRefresh = false;

    for (final entry in uploads.entries) {
      if (entry.value.status == UploadStatus.completed &&
          !_completedUploads.contains(entry.key)) {
        _completedUploads.add(entry.key);
        needsRefresh = true;
      }
    }

    _completedUploads.removeWhere((id) => !uploads.containsKey(id));

    if (needsRefresh && !_refreshScheduled) {
      _refreshScheduled = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshScheduled = false;
        if (!mounted) return;
        _refreshPosts();
      });
    }
  }

  void _onUpdatesScroll() {
    if (!_updatesScrollController.hasClients) return;
    final pos = _updatesScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 &&
        !_loadingPosts &&
        _hasMorePosts) {
      _loadMorePosts();
    }
  }

  // ── Data loading ───────────────────────────────────────────────────────

  Future<void> _loadVenue() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await VenueApiService.getVenue(venueId: widget.venueId);

      if (!mounted) return;

      if (result != null) {
        final venue = VenueDetail.fromJson(result);
        setState(() {
          _venue = venue;
          _isFollowing = venue.isFollowing;
          _isLoading = false;
        });
        _loadPosts();
      } else {
        setState(() {
          _errorMessage = 'Failed to load venue';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading venue: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading venue. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPosts() async {
    if (_loadingPosts) return;

    setState(() {
      _loadingPosts = true;
      _posts.clear();
      _postsPage = 0;
      _hasMorePosts = true;
    });

    await _loadMorePosts();
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMorePosts) return;
    if (_postsPage > 0 && _loadingPosts) return;

    setState(() => _loadingPosts = true);

    try {
      final result = await VenueApiService.fetchVenuePosts(
        venueId: widget.venueId,
        page: _postsPage + 1,
        perPage: _pageSize,
        kind: 'updates', // ← admin/owner posts only
      );

      if (!mounted) return;

      final newPosts = (result as List?)?.cast<Map<String, dynamic>>() ?? [];

      setState(() {
        _posts.addAll(newPosts);
        _hasMorePosts = newPosts.length >= _pageSize;
        _postsPage++;
        _loadingPosts = false;
        _postsLoaded = true;
      });
    } catch (e) {
      print('Error loading venue posts: $e');
      if (!mounted) return;
      setState(() => _loadingPosts = false);
    }
  }

  Future<void> _refreshPosts() async {
    setState(() => _postsLoaded = false);
    await _loadPosts();
  }

  Future<void> _refreshVenue() async {
    await _loadVenue();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _toggleFollow() async {
    if (_venue == null) return;

    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !wasFollowing);

    try {
      final result = await VenueApiService.followVenue(venueId: widget.venueId);

      if (result == null || result['success'] != true) {
        if (mounted) setState(() => _isFollowing = wasFollowing);
      }
    } catch (e) {
      print('Error toggling follow: $e');
      if (mounted) setState(() => _isFollowing = wasFollowing);
    }
  }

  Future<void> _handleCreateVenuePost() async {
    final result = await Navigator.pushNamed(
      context,
      '/create-post',
      arguments: {
        'association_id': widget.venueId,
        'association_type': 'venue',
        'association_label': _venue?.title ?? '',
      },
    );

    if (result == true && mounted) {
      _refreshPosts();
    }
  }

  void _handleMoreMenuSelection(String value) {
    switch (value) {
      case 'share':
        Share.share(
          'Check out ${_venue?.title ?? 'this venue'} on DriveLife!\n\n'
          'https://app.mydrivelife.com/venue/${_venue?.id ?? widget.venueId}',
        );
        break;
      case 'edit':
        _navigateToEditVenue();
        break;
      case 'delete':
        _deleteVenue();
        break;
    }
  }

  Future<void> _navigateToEditVenue() async {
    final response = await NavigationHelper.navigateTo(
      context,
      CreateVenueScreen(existingVenue: _venue),
    );

    if (!mounted) return;

    if (response == true) {
      _loadVenue();
    } else if (response == 'deleted') {
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteVenue() async {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    final selectedCountry =
        Provider.of<UserProvider>(
          context,
          listen: false,
        ).user?.lastLocation?.country ??
        'gb';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: const Text('Delete Venue'),
        content: const Text(
          'Are you sure you want to delete this venue? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        final response = await VenueApiService.deleteVenue(
          venueId: widget.venueId,
          site: selectedCountry,
        );

        if (response == null || response['success'] != true) {
          throw Exception('Failed to delete venue');
        }

        if (!mounted) return;

        Navigator.pop(context, 'deleted'); // Return to previous screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venue deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error deleting venue. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _buildLoadingSkeleton(),
      );
    }

    if (_errorMessage != null || _venue == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildErrorState(),
      );
    }

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final isUpdates = _tabController.index == 0;
        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              Column(
                children: [
                  if (!isUpdates) _buildCompactHeader(theme),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildUpdatesScroll(theme),
                        _buildEventsPanel(theme),
                        _VenueCommunityFeed(
                          venueId: widget.venueId,
                          onCompose: _handleCreateVenuePost,
                        ),
                        _buildAboutPanel(theme),
                      ],
                    ),
                  ),
                ],
              ),
              if (isUpdates) _buildTopOverlay(context),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomSegmentedNav(theme),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Top floating overlay (Updates tab) ─────────────────────────────────

  Widget _buildTopOverlay(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            color: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            itemBuilder: (context) {
              if (_venue?.isOwner == true) {
                return [
                  _menuItem('share', Icons.share_outlined, 'Share', _ink),
                  _menuItem('edit', Icons.edit_outlined, 'Edit venue', _ink),
                  const PopupMenuDivider(height: 1),
                  _menuItem(
                    'delete',
                    Icons.delete_outline,
                    'Delete venue',
                    Colors.red,
                    textColor: Colors.red,
                  ),
                ];
              }
              return [_menuItem('share', Icons.share_outlined, 'Share', _ink)];
            },
            onSelected: _handleMoreMenuSelection,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.more_horiz,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color iconColor, {
    Color? textColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor.withOpacity(0.85)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? _ink,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── Compact header (non-Updates tabs) ──────────────────────────────────

  Widget _buildCompactHeader(ThemeProvider theme) {
    final title = _venue?.title ?? '';
    final logo = _venue?.logo.url;
    final canCreate = _venue?.isOwner == true;

    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: _chip,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: _ink,
                ),
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Row(
                children: [
                  if (logo != null && logo.isNotEmpty) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CachedNetworkImage(
                        imageUrl: logo,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.business, color: _gold, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (canCreate)
              GestureDetector(
                onTap: _handleCreateVenuePost,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: _gold,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.add, size: 20, color: Colors.white),
                ),
              )
            else
              GestureDetector(
                onTap: () {
                  Share.share(
                    'Check out ${_venue?.title ?? 'this venue'} on DriveLife!\n\n'
                    'https://app.mydrivelife.com/venue/${_venue?.id ?? widget.venueId}',
                  );
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: _chip,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.share_outlined,
                    size: 18,
                    color: _ink,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Header area (Updates tab) — cover + logo + title + actions ─────────

  Widget _buildHeaderArea(ThemeProvider theme) {
    final logo = _venue?.logo.url;
    final cover = _venue?.coverPhoto.url;

    return SafeArea(
      bottom: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover image
              SizedBox(
                height: 240,
                width: double.infinity,
                child: cover != null && cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey.shade200),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.grey.shade400,
                            size: 40,
                          ),
                        ),
                      )
                    : Container(color: Colors.grey.shade200),
              ),

              // Space for the overlapping logo
              const SizedBox(height: 70),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _venue?.title ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Location subtitle
              if (_venue?.location.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: _gold,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _venue!.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),

              // Actions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildActionRow(theme),
              ),

              const SizedBox(height: 20),
            ],
          ),

          // Logo overlapping the cover
          Positioned(
            left: 0,
            right: 0,
            top: 240 - 58,
            child: Center(
              child: Container(
                width: 116,
                height: 116,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: logo != null && logo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: logo,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _buildLogoFallback(),
                        )
                      : _buildLogoFallback(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoFallback() {
    return Container(
      color: _ink,
      alignment: Alignment.center,
      child: const Icon(Icons.business, color: _gold, size: 36),
    );
  }

  // ── Action row (Updates tab) ───────────────────────────────────────────

  Widget _buildActionRow(ThemeProvider theme) {
    final moreButton = _ChipActionButton(
      icon: Icons.link_outlined,
      label: 'More',
      onTap: _showVenueLinks,
    );

    // Owner: Create Post + Edit + More
    if (_venue?.isOwner == true) {
      return Row(
        children: [
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.add,
              label: 'Create Post',
              onTap: _handleCreateVenuePost,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _OutlinedGoldButton(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: _navigateToEditVenue,
            ),
          ),
          const SizedBox(width: 8),
          moreButton,
        ],
      );
    }

    // Non-owner: Follow + More
    return Row(
      children: [
        Expanded(
          child: _PrimaryActionButton(
            icon: _isFollowing ? Icons.check : Icons.add,
            label: _isFollowing ? 'Following' : 'Follow',
            onTap: _toggleFollow,
            secondary: _isFollowing,
          ),
        ),
        const SizedBox(width: 8),
        moreButton,
      ],
    );
  }

  void _showVenueLinks() {
    final hasFacebook =
        _venue?.facebook != null && _venue!.facebook!.isNotEmpty;
    final hasInstagram =
        _venue?.instagram != null && _venue!.instagram!.isNotEmpty;
    final hasWebsite = _venue?.website != null && _venue!.website!.isNotEmpty;
    final hasEmail =
        _venue?.venueEmail != null && _venue!.venueEmail!.isNotEmpty;
    final hasPhone =
        _venue?.venuePhone != null && _venue!.venuePhone!.isNotEmpty;

    final hasAny =
        hasFacebook || hasInstagram || hasWebsite || hasEmail || hasPhone;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Links & Contact',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: _chip,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close, size: 14, color: _ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (!hasAny)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No links available',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ),
            if (hasWebsite)
              _linkTile(
                ctx,
                Icons.language,
                'Website',
                _venue!.website!,
                () => launchUrl(Uri.parse(_venue!.website!)),
              ),
            if (hasInstagram)
              _linkTile(
                ctx,
                Icons.camera_alt_outlined,
                'Instagram',
                _venue!.instagram!,
                () => launchUrl(Uri.parse(_venue!.instagram!)),
              ),
            if (hasFacebook)
              _linkTile(
                ctx,
                Icons.facebook,
                'Facebook',
                _venue!.facebook!,
                () => launchUrl(Uri.parse(_venue!.facebook!)),
              ),
            if (hasEmail)
              _linkTile(
                ctx,
                Icons.email_outlined,
                'Email',
                _venue!.venueEmail!,
                () =>
                    launchUrl(Uri(scheme: 'mailto', path: _venue!.venueEmail!)),
              ),
            if (hasPhone)
              _linkTile(
                ctx,
                Icons.phone_outlined,
                'Phone',
                _venue!.venuePhone!,
                () => launchUrl(Uri(scheme: 'tel', path: _venue!.venuePhone!)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _linkTile(
    BuildContext ctx,
    IconData icon,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: _gold),
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
      ),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  // ── Updates tab (Posts feed) ───────────────────────────────────────────

  Widget _buildUpdatesScroll(ThemeProvider theme) {
    if (_loadingPosts && _posts.isEmpty && !_postsLoaded) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeaderArea(theme)),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: theme.primaryColor),
              ),
            ),
          ),
        ],
      );
    }

    final hasPosts = _posts.isNotEmpty;

    return RefreshIndicator(
      color: _gold,
      onRefresh: _refreshVenue,
      child: CustomScrollView(
        controller: _updatesScrollController,
        slivers: [
          SliverToBoxAdapter(child: _buildHeaderArea(theme)),

          if (!hasPosts)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 56,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No posts yet',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _venue?.isOwner == true
                          ? 'Share an update with your followers'
                          : 'Check back soon',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (hasPosts)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final post = _posts[i];
                return PostCard(
                  key: ValueKey(post['id']),
                  post: post,
                  onTapProfile: () {
                    Navigator.pushNamed(
                      context,
                      '/view-profile',
                      arguments: {
                        'userId': post['user_id'],
                        'username': post['username'],
                      },
                    );
                  },
                  onLikeChanged: (isLiked) {
                    setState(() {
                      post['is_liked'] = isLiked;
                      post['likes_count'] =
                          (post['likes_count'] as int) + (isLiked ? 1 : -1);
                    });
                  },
                  onDelete: _refreshPosts,
                );
              }, childCount: _posts.length),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _loadingPosts && _posts.isNotEmpty
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _gold,
                        ),
                      )
                    : (!_hasMorePosts && _posts.isNotEmpty)
                    ? const Text(
                        "You're all caught up",
                        style: TextStyle(color: _muted, fontSize: 13),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ── Events tab ─────────────────────────────────────────────────────────

  Widget _buildEventsPanel(ThemeProvider theme) {
    if (_venue!.events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 100),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_rounded, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 14),
              Text(
                'No upcoming events',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'Check back soon',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Upcoming events',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${_venue!.events.length} ${_venue!.events.length == 1 ? "event" : "events"}',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final event in _venue!.events)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildEventCard(event),
          ),
      ],
    );
  }

  Widget _buildEventCard(VenueEvent event) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.eventDetail,
          arguments: {'event': event.toJson()},
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: event.thumbnail,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: Icon(
                    Icons.event,
                    color: Colors.grey.shade400,
                    size: 40,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 13, color: _muted),
                      const SizedBox(width: 6),
                      Text(
                        event.getFormattedDate(),
                        style: const TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: _muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: _muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── About tab ──────────────────────────────────────────────────────────

  Widget _buildAboutPanel(ThemeProvider theme) {
    final hasFacebook =
        _venue?.facebook != null && _venue!.facebook!.isNotEmpty;
    final hasInstagram =
        _venue?.instagram != null && _venue!.instagram!.isNotEmpty;
    final hasWebsite = _venue?.website != null && _venue!.website!.isNotEmpty;
    final hasEmail =
        _venue?.venueEmail != null && _venue!.venueEmail!.isNotEmpty;
    final hasPhone =
        _venue?.venuePhone != null && _venue!.venuePhone!.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        if (_venue!.description != null && _venue!.description!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'ABOUT',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Html(
              data: _venue!.description!,
              style: {
                "body": Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  fontSize: FontSize(15),
                  lineHeight: const LineHeight(1.6),
                  color: Colors.grey.shade700,
                ),
                "p": Style(margin: Margins.only(bottom: 12)),
                "h1, h2, h3, h4, h5, h6": Style(
                  margin: Margins.only(top: 16, bottom: 8),
                  fontWeight: FontWeight.bold,
                ),
                "ul, ol": Style(margin: Margins.only(left: 16, bottom: 12)),
                "li": Style(margin: Margins.only(bottom: 4)),
                "a": Style(
                  color: _gold,
                  textDecoration: TextDecoration.underline,
                ),
                "strong, b": Style(fontWeight: FontWeight.bold),
                "em, i": Style(fontStyle: FontStyle.italic),
              },
              onLinkTap: (url, _, __) {
                if (url != null) launchUrl(Uri.parse(url));
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'LOCATION',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.location_on, color: _gold, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _venue!.location,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (hasFacebook ||
            hasInstagram ||
            hasWebsite ||
            hasEmail ||
            hasPhone) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'CONTACT & LINKS',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (hasWebsite)
            _aboutLinkRow(
              Icons.language,
              'Website',
              _venue!.website!,
              () => launchUrl(Uri.parse(_venue!.website!)),
            ),
          if (hasInstagram)
            _aboutLinkRow(
              Icons.camera_alt_outlined,
              'Instagram',
              _venue!.instagram!,
              () => launchUrl(Uri.parse(_venue!.instagram!)),
            ),
          if (hasFacebook)
            _aboutLinkRow(
              Icons.facebook,
              'Facebook',
              _venue!.facebook!,
              () => launchUrl(Uri.parse(_venue!.facebook!)),
            ),
          if (hasEmail)
            _aboutLinkRow(
              Icons.email_outlined,
              'Email',
              _venue!.venueEmail!,
              () => launchUrl(Uri(scheme: 'mailto', path: _venue!.venueEmail!)),
            ),
          if (hasPhone)
            _aboutLinkRow(
              Icons.phone_outlined,
              'Phone',
              _venue!.venuePhone!,
              () => launchUrl(Uri(scheme: 'tel', path: _venue!.venuePhone!)),
            ),
        ],
      ],
    );
  }

  Widget _aboutLinkRow(
    IconData icon,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: _gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSegmentedNav(ThemeProvider theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _segButton(label: 'Updates', index: 0),
              _segButton(label: 'Events', index: 1),
              _segButton(label: 'Community', index: 2),
              _segButton(label: 'About', index: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segButton({required String label, required int index}) {
    final isActive = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? _gold : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: _gold.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.01,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(
              height: 240,
              width: double.infinity,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 70),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Shimmer.fromColors(
                  baseColor: Colors.grey.shade300,
                  highlightColor: Colors.grey.shade100,
                  child: Container(
                    height: 24,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Shimmer.fromColors(
                  baseColor: Colors.grey.shade300,
                  highlightColor: Colors.grey.shade100,
                  child: Container(
                    height: 44,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Oops!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Something went wrong',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadVenue,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable button widgets (match club view styles) ───────────────────
class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool secondary;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: secondary ? Colors.grey.shade200 : _gold,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: secondary ? _ink : Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: secondary ? _ink : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlinedGoldButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlinedGoldButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _gold, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ChipActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _chip,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _ink, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _VenueCommunityFeed extends StatefulWidget {
  final String venueId;
  final VoidCallback onCompose;

  const _VenueCommunityFeed({required this.venueId, required this.onCompose});

  @override
  State<_VenueCommunityFeed> createState() => _VenueCommunityFeedState();
}

class _VenueCommunityFeedState extends State<_VenueCommunityFeed>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;

  static const int _pageSize = 10;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final result = await VenueApiService.fetchVenuePosts(
        venueId: widget.venueId,
        page: _page + 1,
        perPage: _pageSize,
        kind: 'community',
      );

      if (!mounted) return;

      final newPosts = (result as List?)?.cast<Map<String, dynamic>>() ?? [];

      setState(() {
        _posts.addAll(newPosts);
        _hasMore = newPosts.length >= _pageSize;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _page = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      color: _gold,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          // Compose prompt — anyone can post in venue community
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _VenueComposePrompt(onTap: widget.onCompose),
            ),
          ),

          if (_posts.isEmpty && !_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 56,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No community posts yet',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Share your visit to this venue',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_posts.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final post = _posts[i];
                return PostCard(
                  key: ValueKey(post['id']),
                  post: post,
                  onTapProfile: () {
                    Navigator.pushNamed(
                      context,
                      '/view-profile',
                      arguments: {
                        'userId': post['user_id'],
                        'username': post['username'],
                      },
                    );
                  },
                  onLikeChanged: (isLiked) {
                    setState(() {
                      post['is_liked'] = isLiked;
                      post['likes_count'] =
                          (post['likes_count'] as int) + (isLiked ? 1 : -1);
                    });
                  },
                  onDelete: _refresh,
                );
              }, childCount: _posts.length),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _gold,
                        ),
                      )
                    : (!_hasMore && _posts.isNotEmpty)
                    ? const Text(
                        "You're all caught up",
                        style: TextStyle(color: _muted, fontSize: 13),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _VenueComposePrompt extends StatelessWidget {
  final VoidCallback onTap;
  const _VenueComposePrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F4),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Share your visit…',
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
