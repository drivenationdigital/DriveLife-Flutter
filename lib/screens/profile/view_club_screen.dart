import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/join_club_modal.dart';
import 'package:drivelife/screens/clubs/request_modal.dart';
import 'package:drivelife/screens/clubs/ui-widgets/announcement-card.dart';
import 'package:drivelife/screens/clubs/ui-widgets/event-card.dart';
import 'package:drivelife/screens/clubs/ui-widgets/member-listing.dart';
import 'package:drivelife/utils/misc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _gold = Color(0xFFC4A062);
const Color _ink = Color(0xFF0B0B0B);
const Color _muted = Color(0xFF8A8A8A);
const Color _chip = Color(0xFFEFEFEF);

class ClubViewScreen extends StatefulWidget {
  final int? clubPostId;
  final bool showAppBar;
  final bool isOwnClub;
  final String? tab;

  const ClubViewScreen({
    super.key,
    this.clubPostId,
    this.showAppBar = true,
    this.isOwnClub = false,
    this.tab,
  });

  @override
  State<ClubViewScreen> createState() => _ClubViewScreenState();
}

class _ClubViewScreenState extends State<ClubViewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, dynamic>? _clubData;
  bool _isLoading = true;
  bool _isMember = false;
  bool _hasPendingRequest = false;
  bool _isOwner = false;
  bool _isAdmin = false;
  int _pendingRequestsCount = 0;

  List<Map<String, dynamic>> _events = [];
  bool _loadingEvents = false;
  bool _eventsLoaded = false;

  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = false;
  bool _membersLoaded = false;

  List<dynamic> _clubPosts = [];
  bool _loadingClubPosts = false;
  bool _clubPostsLoaded = false;
  int _clubPostsPage = 0;
  bool _hasMoreClubPosts = true;
  final ScrollController _updatesScrollController = ScrollController();
  static const int _clubPostsPageSize = 10;

  // Upload completion tracking — refresh club posts when an upload finishes
  final Set<String> _completedUploads = {};
  bool _refreshScheduled = false;
  UploadPostProvider? _uploadProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _updatesScrollController.addListener(_onUpdatesScroll);

    _loadClubData();
  }

  @override
  void dispose() {
    _uploadProvider?.removeListener(_onUploadsChanged);
    _tabController.dispose();
    _updatesScrollController.removeListener(_onUpdatesScroll);
    _updatesScrollController.dispose();
    super.dispose();
  }

  void _onUpdatesScroll() {
    if (!_updatesScrollController.hasClients) return;

    final pos = _updatesScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 &&
        !_loadingClubPosts &&
        _hasMoreClubPosts) {
      _loadMoreClubPosts();
    }
  }

  Future<void> _loadClubPosts() async {
    if (_loadingClubPosts) return;

    setState(() {
      _loadingClubPosts = true;
      _clubPosts = [];
      _clubPostsPage = 0;
      _hasMoreClubPosts = true;
    });

    await _loadMoreClubPosts(); // first page
  }

  Future<void> _loadMoreClubPosts() async {
    if (!_hasMoreClubPosts) return;
    if (_clubPostsPage > 0 && _loadingClubPosts) return; // dedupe in-flight

    setState(() => _loadingClubPosts = true);

    try {
      final result = await ClubApiService.fetchClubPosts(
        clubId: _clubData?['id'].toString() ?? '',
        page: _clubPostsPage + 1,
        perPage: _clubPostsPageSize,
        kind: 'updates',
      );

      if (!mounted) return;

      final newPosts =
          (result?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      setState(() {
        _clubPosts.addAll(newPosts);
        _hasMoreClubPosts = newPosts.length >= _clubPostsPageSize;
        _clubPostsPage++;
        _loadingClubPosts = false;
        _clubPostsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingClubPosts = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Subscribe to upload provider once
    final provider = Provider.of<UploadPostProvider>(context, listen: false);
    if (_uploadProvider != provider) {
      _uploadProvider?.removeListener(_onUploadsChanged);
      _uploadProvider = provider;
      _uploadProvider!.addListener(_onUploadsChanged);
    }
  }

  void _onTabChanged() {
    if (_tabController.index == 0 &&
        !_clubPostsLoaded &&
        !_isLockedForPrivacy) {
      _loadClubPosts();
    }
    if (_tabController.index == 1 && !_eventsLoaded) {
      _loadClubEvents();
    }
    // Members loader removed — triggered when the modal opens instead
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
        // Only refresh if the completed upload was for THIS club
        _completedUploads.add(entry.key);
        needsRefresh = true;
      }
    }

    // Clean up tracking for uploads that have been removed from the provider
    _completedUploads.removeWhere((id) => !uploads.containsKey(id));

    if (needsRefresh && !_refreshScheduled) {
      _refreshScheduled = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshScheduled = false;
        if (!mounted) return;
        // Force a fresh fetch of club posts
        setState(() => _clubPostsLoaded = false);
        _loadClubPosts();
      });
    }
  }

  void _handleJoinLeave() {
    if (_isMember) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Leave Club?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Are you sure you want to leave this club?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Stay in Club',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await ClubApiService.leaveClub(
                  clubId: _clubData!['id'].toString(),
                );

                if (success && mounted) {
                  setState(() => _isMember = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You have left the club.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Leave Club'),
            ),
          ],
        ),
      );
      return;
    }

    if (_hasPendingRequest) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Cancel Request?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Are you sure you want to cancel your membership request?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Keep Request',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await ClubApiService.cancelJoinRequest(
                  clubId: _clubData!['id'].toString(),
                );
                if (success && mounted) {
                  setState(() => _hasPendingRequest = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Request cancelled.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Cancel Request'),
            ),
          ],
        ),
      );
      return;
    }

    final raw = _clubData!['membership_questions'];

    final questions = (raw is List)
        ? raw
              .map((q) => q?.toString().trim() ?? '')
              .where((q) => q.isNotEmpty)
              .toList()
        : <String>[];

    if (questions.isEmpty) {
      _handleFreeJoin();
      return;
    }

    showClubJoinModal(
      context,
      clubId: _clubData!['id'].toString(),
      questions: questions,
      onSuccess: () {
        setState(() => _hasPendingRequest = true);
      },
    );
  }

  Future<void> _handleFreeJoin() async {
    try {
      final success = await ClubApiService.submitJoinRequest(
        clubId: _clubData!['id'].toString(),
        questionsAndAnswers: [],
      );

      if (!mounted) return;

      if (success) {
        if (_clubData?['club_type'] == '2') { // Public club with auto-join
          setState(() => _isMember = true);
        } else {
          setState(() => _hasPendingRequest = true);
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Request sent! The club owner will review your application.'
                : 'Something went wrong. Please try again.',
          ),
          backgroundColor: success
              ? Colors.green.shade600
              : Colors.red.shade400,
        ),
      );
    } catch (e) {
      print('❌ Error submitting join request: $e');
      if (!mounted) return;
    }
  }

  void _openUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openMemberProfile(Map<String, dynamic> member) {
    Navigator.pushNamed(
      context,
      '/view-profile',
      arguments: {'userId': member['user_id']},
    );
  }

  void _showClubLinks() {
    if (!mounted) return;

    final website = _clubData?['website'];
    final facebook = _clubData?['facebook'];
    final instagram = _clubData?['instagram'];

    bool hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

    // Build the list of links that actually have values
    final links = <Map<String, String>>[
      if (hasValue(website))
        {'label': 'Website', 'url': website.toString(), 'icon': 'web'},
      if (hasValue(facebook))
        {'label': 'Facebook', 'url': facebook.toString(), 'icon': 'fb'},
      if (hasValue(instagram))
        {'label': 'Instagram', 'url': instagram.toString(), 'icon': 'ig'},
    ];

    if (links.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No links available'),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    IconData iconFor(String key) {
      switch (key) {
        case 'fb':
          return Icons.facebook;
        case 'ig':
          return Icons.camera_alt_outlined;
        case 'web':
        default:
          return Icons.public;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Club Links',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Links list
              ...links.map((link) {
                return ListTile(
                  leading: Icon(iconFor(link['icon']!), color: _gold, size: 22),
                  title: Text(
                    link['label']!,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () async {
                    Navigator.pop(context);
                    final url = link['url']!;
                    try {
                      final uri = Uri.parse(url);
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (e) {
                      print('Error launching URL: $e');
                    }
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadMembers() async {
    if (_loadingMembers || _clubData == null) return;

    setState(() => _loadingMembers = true);

    try {
      final data = await ClubApiService.fetchClubMembers(
        _clubData!['id'].toString(),
      );

      if (mounted && data != null) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(data);
          _membersLoaded = true;
          _loadingMembers = false;
        });
      } else if (mounted) {
        setState(() => _loadingMembers = false);
      }
    } catch (e) {
      print('❌ Error loading members: $e');
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  /// True when the club is private AND the viewer is neither a member nor owner.
  /// Privacy gates: events tab, posts tab, and member-list tap.
  bool get _isLockedForPrivacy {
    if (_clubData == null) return false;
    final isPrivate = _clubData!['club_type'] == '1' || _clubData!['club_type'] == '2';
    return isPrivate && !_isMember && !_isOwner && !_isAdmin;
  }

  Future<void> _loadClubEvents() async {
    if (_loadingEvents || _clubData == null) return;

    setState(() => _loadingEvents = true);

    try {
      final data = await ClubApiService.getClubEvents(
        clubPostId: _clubData!['id'],
        page: 1,
        perPage: 20,
      );

      if (mounted && data != null && data['success'] == true) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(data['events'] ?? []);
          _eventsLoaded = true;
          _loadingEvents = false;
        });
      }
    } catch (e) {
      print('❌ Error loading events: $e');
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  Future<void> _loadClubData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.isOwnClub) {
        final accountManager = Provider.of<AccountManager>(
          context,
          listen: false,
        );
        final clubAccount = accountManager.activeAccount!;
        final meta = clubAccount.entityMeta!;

        setState(() {
          _clubData = {
            'id': meta['club_post_id'],
            'title': meta['title'],
            'club_type': meta['club_type'],
            'location_type': meta['location_type'],
            'location': meta['location'],
            'member_count': meta['member_count'],
            'description': meta['description'],
            'website': meta['website'],
            'facebook': meta['facebook'],
            'instagram': meta['instagram'],
            'is_owner': meta['is_owner'],
            'is_admin': meta['is_admin'],
            'logo': clubAccount.user.profileImage,
            'cover_image': clubAccount.user.coverImage,
          };

          _isOwner = true;
          _isLoading = false;
        });
      } else {
        final data = await ClubApiService.getClubDetails(
          clubPostId: widget.clubPostId!,
        );

        if (mounted && data != null) {
          setState(() {
            _clubData = data;
            _isMember = data['is_member'] ?? false;
            _isOwner = data['is_owner'] ?? false;
            _isAdmin = data['is_admin'] ?? false;
            _hasPendingRequest = data['has_pending_request'] ?? false;
            _isLoading = false;
          });
        }
      }

      // If widget.tab is set, open that tab/screen
      if (widget.tab != null) {
        print('Opening club with tab: ${widget.tab}');
        final tab = widget.tab!.toLowerCase();

        // Members tab is now a modal — for "members" deep-link, open pending requests
        // (the typical use case from notifications)
        if (tab == 'members') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushNamed(
              context,
              '/club-pending-requests',
              arguments: {
                'clubId': _clubData?['id'],
                'clubName': _clubData?['title'],
              },
            ).then((result) {
              if (result == true && mounted) {
                _loadPendingRequestsCount();
              }
            });
          });
        } else {
          // Regular tab navigation (feed/events/about)
          final tabIndex = ['feed', 'events', 'about'].indexOf(tab);
          if (tabIndex != -1) {
            _tabController.index = tabIndex;
          }
        }
      }

      // print(_clubData);
      // loop through _clubData and print all keys and types for debugging
      _clubData?.forEach((key, value) {
        print('Club data key: $key, val: $value, type: ${value.runtimeType}');
      });

      _loadClubEvents();
      _loadClubPosts();
      _loadPendingRequestsCount();
      _loadMembers();
    } catch (e) {
      print('❌ Error loading club: $e ${widget.clubPostId}');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPendingRequestsCount() async {
    try {
      final data = await ClubApiService.getClubPendingRequests(
        clubPostId: _clubData!['id'],
      );

      if (mounted && data != null && data['success'] == true) {
        setState(() {
          _pendingRequestsCount = data['total'] ?? 0;
        });
      }
    } catch (e) {
      print('❌ Error loading pending count: $e');
    }
  }

  Future<void> _refreshClub() async {
    setState(() {
      _eventsLoaded = false;
      _membersLoaded = false;
      _clubPostsLoaded = false;
    });
    await _loadClubData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _buildSkeleton(theme),
      );
    }

    if (_clubData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(child: Text('Club not found')),
      );
    }

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final isUpdates = _tabController.index == 0;
        return Scaffold(
          backgroundColor: Colors.white,
          // appBar: isUpdates ? null : _buildAppBar(),
          body: Stack(
            children: [
              Column(
                children: [
                  if (!isUpdates) _buildCompactHeader(theme),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildUpdatesScroll(theme),
                        _buildEventsPanel(theme),
                        // _buildMembersPanel(theme),
                        _buildCommunityPanel(theme),
                        _buildAboutPanel(theme),
                      ],
                    ),
                  ),
                ],
              ),
              // Floating back + more buttons — Updates tab only
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

  Widget _buildUpdatesScroll(ThemeProvider theme) {
    if (_loadingClubPosts && _clubPosts.isEmpty && !_clubPostsLoaded) {
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

    final announcements = (_clubData?['announcements'] is List)
        ? (_clubData!['announcements'] as List)
        : const [];

    final hasPosts = _clubPosts.isNotEmpty;
    final hasAnnouncements = announcements.isNotEmpty;

    return CustomScrollView(
      controller: _updatesScrollController,
      slivers: [
        // Cover + logo + name + meta + actions — always shown
        SliverToBoxAdapter(child: _buildHeaderArea(theme)),

        // Owner pending-requests banner
        if ((_isOwner || _isAdmin) && _pendingRequestsCount > 0)
          SliverToBoxAdapter(child: _buildPendingRequestsBanner(theme)),

        // Non-members of a private club: locked view fills the rest
        if (_isLockedForPrivacy)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildPrivateLockedView(),
          )
        else ...[
          // Empty state
          if (!hasPosts && !hasAnnouncements)
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
                      'Nothing here yet',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check back soon',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Posts
          if (hasPosts)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final post = _clubPosts[i] as Map<String, dynamic>;
                return PostCard(
                  key: ValueKey(post['id']),
                  post: post,
                  onTapProfile: () {},
                  onLikeChanged: (isLiked) {
                    setState(() {
                      post['is_liked'] = isLiked;
                      post['likes_count'] =
                          (post['likes_count'] as int) + (isLiked ? 1 : -1);
                    });
                  },
                  onDelete: _refreshClub,
                );
              }, childCount: _clubPosts.length),
            ),

          // Divider between posts and announcements
          if (hasPosts && hasAnnouncements)
            SliverToBoxAdapter(
              child: Container(height: 8, color: const Color(0xFFF5F5F5)),
            ),

          // Announcements section header
          if (hasAnnouncements && hasPosts)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Announcements',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),

          // Announcements
          if (hasAnnouncements)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                return AnnouncementCard(
                  authorName: _clubData?['title'] ?? 'Club',
                  posted: (announcements[i]['date'] ?? '').toString(),
                  content: (announcements[i]['content'] ?? '').toString(),
                  logoUrl: _clubData?['logo'] as String?,
                );
              }, childCount: announcements.length),
            ),

          // Loading / end indicator
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _loadingClubPosts && _clubPosts.isNotEmpty
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _gold,
                        ),
                      )
                    : (!_hasMoreClubPosts && _clubPosts.isNotEmpty)
                    ? const Text(
                        'You\'re all caught up',
                        style: TextStyle(color: _muted, fontSize: 13),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Bottom padding for the floating pill nav
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ],
    );
  }

  Future<void> _openRequestModal(Map<String, dynamic> member) async {
    final result = await showDialog<RequestModalResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ClubRequestModal(
        clubName: _clubData?['title'] ?? 'this club',
        memberName: (member['name'] ?? 'User').toString(),
        userId: int.parse(member['user_id'].toString()),
        clubId: int.parse(_clubData?['id'].toString() ?? '0'),
        avatar: member['avatar'] as String?,
        questions: (member['questions'] as List?) ?? const [],
      ),
    );

    if (!mounted) return;

    // Refresh the list whether they accepted or rejected — both change state
    if (result == RequestModalResult.accepted ||
        result == RequestModalResult.rejected) {
      setState(() => _membersLoaded = false);
      _loadMembers();
      // Also refresh the pending banner count
      _loadPendingRequestsCount();
    }
  }

  Widget _buildMembersPanel(
    ThemeProvider theme,
    ScrollController? scrollController,
  ) {
    if (_isLockedForPrivacy) return _buildPrivateLockedView();

    if (_loadingMembers && _members.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              'No members yet',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
          ],
        ),
      );
    }

    // Owner bubbles to the top, then admins, then everyone else
    final ownerId = _clubData?['user_id'];
    final sorted = [..._members]
      ..sort((a, b) {
        final ar = _memberRank(a, ownerId);
        final br = _memberRank(b, ownerId);
        return ar.compareTo(br);
      });

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Members',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${sorted.length} ${sorted.length == 1 ? "member" : "members"}',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        for (final member in sorted)
          MemberRow(
            member: member,
            isViewerAdmin: _isOwner || _isAdmin,
            onTap: () => _openMemberProfile(member),
            onAdminAction: (action) => _handleMemberAdminAction(member, action),
            onViewRequest: member['is_pending'] == true
                ? () => _openRequestModal(member)
                : null,
          ),
      ],
    );
  }

  int _memberRank(Map<String, dynamic> m, dynamic ownerId) {
    if (ownerId != null && m['id'] == ownerId) return 0;
    if (m['is_admin'] == true) return 1;
    return 2;
  }

  Future<void> _handleMemberAdminAction(
    Map<String, dynamic> member,
    MemberAdminAction action,
  ) async {
    final name = member['name'] ?? 'this member';

    switch (action) {
      case MemberAdminAction.viewProfile:
        _openMemberProfile(member);
        return;

      case MemberAdminAction.makeAdmin:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name promoted to admin')));
        return;
      case MemberAdminAction.removeAdmin:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$name's admin role removed")));
        return;

      case MemberAdminAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Remove Member?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Remove $name from the club? They can request to join again later.',
              style: const TextStyle(fontSize: 14, color: Colors.black),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          final success = await ClubApiService.removeMember(
            clubId: _clubData!['id'].toString(),
            userId: member['user_id'],
          );
          if (success) {
            // // Optimistic update
            setState(() {
              _members.removeWhere((m) => m['id'] == member['id']);
            });
            _loadMembers();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$name removed from the club')),
            );
          }
        }
        return;
    }
  }

  Widget _buildCompactHeader(ThemeProvider theme) {
    final title = _clubData?['title'] ?? '';
    final logo = _clubData?['logo'];
    final verified = _clubData?['is_verified'] == true;

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

            // Small logo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: logo != null
                    ? Image.network(
                        logo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Row(
                children: [
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
                  if (verified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 14, color: _gold),
                  ],
                ],
              ),
            ),

            // Right-hand action — Create (members/owners) or More (everyone else)
            GestureDetector(
              onTap: _handleCreateClubPost,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSegmentedNav(ThemeProvider theme) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.black.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                _segButton(label: 'Updates', index: 0),
                _segButton(label: 'Events', index: 1),
                // _segButton(label: 'Members', index: 2),
                _segButton(label: 'Community', index: 2),
                _segButton(label: 'About', index: 3),
              ],
            ),
          );
        },
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
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isActive ? _gold : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: _gold.withOpacity(0.35),
                      blurRadius: 6,
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

  Widget _buildCommunityPanel(ThemeProvider theme) {
    return _ClubCommunityFeed(
      clubId: _clubData?['id']?.toString() ?? '',
      onCompose: _handleCreateClubPost,
      isMember: _isMember,
      isOwner: _isOwner,
      handleJoinLeave: _handleJoinLeave,
      hasPendingRequest: _hasPendingRequest,
      isPublicClub: !_isLockedForPrivacy,
    );
  }

  Widget _buildTopOverlay(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back
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

          // More — PopupMenuButton from above
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            color: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            itemBuilder: (context) {
              // Owner / admin — full menu
              if (_isOwner || _isAdmin) {
                return [
                  _menuItem('share', Icons.share_outlined, 'Share', _ink),
                  _menuItem('edit', Icons.edit_outlined, 'Edit club', _ink),
                  const PopupMenuDivider(height: 1),
                  _menuItem(
                    'delete',
                    Icons.delete_outline,
                    'Delete club',
                    Colors.red,
                    textColor: Colors.red,
                  ),
                ];
              }

              // Member — Share + Leave
              if (_isMember) {
                return [
                  _menuItem('share', Icons.share_outlined, 'Share', _ink),
                  const PopupMenuDivider(height: 1),
                  _menuItem(
                    'leave',
                    Icons.logout,
                    'Leave club',
                    Colors.red,
                    textColor: Colors.red,
                  ),
                ];
              }

              // Pending request — Share + Cancel request
              if (_hasPendingRequest) {
                return [
                  _menuItem('share', Icons.share_outlined, 'Share', _ink),
                  const PopupMenuDivider(height: 1),
                  _menuItem(
                    'cancel_request',
                    Icons.close,
                    'Cancel request',
                    Colors.red,
                    textColor: Colors.red,
                  ),
                ];
              }

              // Not a member — Share only
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

  void _handleMoreMenuSelection(String value) {
    switch (value) {
      case 'share':
        Share.share(
          'Check out this club on DriveLife: ${_clubData?['title']}\n\n'
          'https://app.mydrivelife.com/club/${_clubData?['id']}',
        );
        break;
      case 'edit':
        Navigator.pushNamed(
          context,
          '/add-club',
          arguments: {'existingClubId': _clubData!['id'].toString()},
        ).then((result) {
          if (!mounted) return;
          if (result == 'deleted') {
            Navigator.pop(context, 'deleted');
            return;
          }
          if (result == true) _refreshClub();
        });
        break;
      case 'delete':
        _deleteClub();
        break;
      case 'leave':
      case 'cancel_request':
        _handleJoinLeave(); // existing method handles both
        break;
    }
  }

  Future<void> _deleteClub() async {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: const Text('Delete Club'),
        content: const Text(
          'Are you sure you want to delete this club? This action cannot be undone.',
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
      final selectedCountry =
          Provider.of<UserProvider>(
            context,
            listen: false,
          ).user?.lastLocation?.country ??
          'gb';

      try {
        final response = await ClubApiService.deleteClub(
          clubId: _clubData!['id'].toString(),
          site: selectedCountry,
        );

        if (response == null || response['success'] != true) {
          throw Exception(response?['message'] ?? 'Failed to delete club');
        }

        if (!mounted) return;

        Navigator.pop(context, 'deleted');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Club deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete club'),
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

  Widget _buildHeaderArea(ThemeProvider theme) {
    final coverImage = _clubData?['cover_image'];
    final logo = _clubData?['logo'];
    final title = (_clubData?['title'] ?? '') as String;
    final memberCount = _clubData?['member_count'] ?? 0;
    // final clubType = _clubData?['club_type'] == '1' ? 'Private' : 'Public';
    // final location = _clubData?['location'] ?? 'National Club';
    final verified = _clubData?['is_verified'] == true;

    return SafeArea(
      bottom: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover image
              SizedBox(
                height: 240,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverImage != null
                        ? Image.network(
                            coverImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildCoverPlaceholder(theme),
                          )
                        : _buildCoverPlaceholder(theme),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.30),
                            Colors.transparent,
                            Colors.black.withOpacity(0.15),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              // Below-logo content
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Name + verified
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (verified)
                          const Icon(Icons.verified, size: 18, color: _gold),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Meta row
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.center,
                    //   children: [
                    //     const SizedBox(height: 8),
                    //     GestureDetector(
                    //       // onTap: _isLockedForPrivacy ? null : _openMembersModal,
                    //       behavior: HitTestBehavior.opaque,
                    //       child: Row(
                    //         mainAxisAlignment: MainAxisAlignment.center,
                    //         mainAxisSize: MainAxisSize.min,
                    //         children: [
                    //           const Icon(
                    //             Icons.person_outline,
                    //             size: 16,
                    //             color: _gold,
                    //           ),
                    //           const SizedBox(width: 6),
                    //           Text(
                    //             '${_formatCount(memberCount)} ',
                    //             style: const TextStyle(
                    //               color: _ink,
                    //               fontSize: 14,
                    //               fontWeight: FontWeight.w700,
                    //             ),
                    //           ),
                    //           const Text(
                    //             'members',
                    //             style: TextStyle(color: _muted, fontSize: 13),
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ],
                    // ),
                    const SizedBox(height: 16),
                    _buildActionRow(theme),
                  ],
                ),
              ),
            ],
          ),
          // Logo + status pill (positioned to overlap cover by 48px)
          Positioned(
            left: 20,
            right: 20,
            top: 240 - 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 116,
                  height: 116,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: logo != null
                        ? Image.network(
                            logo,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildLogoFallback(),
                          )
                        : _buildLogoFallback(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(dynamic count) {
    final n = count is int
        ? count
        : int.tryParse(count?.toString() ?? '0') ?? 0;
    if (n < 1000) return n.toString();
    // Insert commas every 3 digits
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _openMembersModal() async {
    // Trigger the members load now if not already done
    if (!_membersLoaded) {
      _loadMembers();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) {
          return Column(
            children: [
              // Drag handle
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Members',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${_clubData?['member_count'] ?? 0}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // Reuse the existing members panel logic, passing in the
              // scrollController so DraggableScrollableSheet can drive it
              Expanded(
                child: AnimatedBuilder(
                  animation: this is Listenable
                      ? this as Listenable
                      : const AlwaysStoppedAnimation(0),
                  builder: (context, _) {
                    return _buildMembersPanel(
                      Provider.of<ThemeProvider>(context),
                      scrollController,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrivateLockedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline, size: 28, color: _gold),
            ),
            const SizedBox(height: 16),
            Text(
              _clubData!['club_type'] ==
                  '1'
                      ? 'Private Club'
                      : 'Join Club',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Join the club to view posts and events',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (!_hasPendingRequest) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 180,
                child: _PrimaryActionButton(
                  icon: Icons.add,
                  label: 'Join Club',
                  onTap: _handleJoinLeave,
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _chip,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_empty, size: 14, color: _muted),
                    SizedBox(width: 6),
                    Text(
                      'Request pending',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogoFallback() {
    return Container(
      color: _ink,
      alignment: Alignment.center,
      child: const Text(
        '⫽',
        style: TextStyle(
          color: _gold,
          fontSize: 38,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor.withOpacity(0.7), theme.primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildActionRow(ThemeProvider theme) {
    // More chip — shown for everyone
    final moreButton = _ChipActionButton(
      icon: Icons.link_outlined,
      label: 'More',
      onTap: _showClubLinks,
    );

    // Owner / Admin — Create Post + Members + More
    if (_isOwner || _isAdmin) {
      return Row(
        children: [
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.add,
              label: 'Create',
              onTap: _handleCreateClubPost,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.person_outline,
              label: 'Members',
              onTap: _openMembersModal,
            ),
          ),
          const SizedBox(width: 8),
          moreButton,
        ],
      );
    }

    // Member — Create Post + More
    if (_isMember) {
      return Row(
        children: [
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.add,
              label: 'Post',
              onTap: _handleCreateClubPost,
            ),
          ),
          const SizedBox(width: 8),
          moreButton,
        ],
      );
    }

    // Pending request — Request Pending + More
    if (_hasPendingRequest) {
      return Row(
        children: [
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.hourglass_empty,
              label: 'Request Pending',
              onTap: _handleJoinLeave,
            ),
          ),
          const SizedBox(width: 8),
          moreButton,
        ],
      );
    }

    // Non-member — Join Club + More
    return Row(
      children: [
        Expanded(
          child: _PrimaryActionButton(
            icon: Icons.add,
            label: 'Join Club',
            onTap: _handleJoinLeave,
          ),
        ),
        const SizedBox(width: 8),
        moreButton,
      ],
    );
  }

  Future<void> _handleCreateClubPost() async {
    if (!_isMember && !_isOwner && !_isAdmin) {
      // Not a member — show toast and return early
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join the club to create posts')),
      );
      return;
    }

    final result = await Navigator.pushNamed(
      context,
      '/create-post',
      arguments: {
        'association_id': _clubData?['id'].toString(),
        'association_type': 'club',
        'association_label': _clubData?['title'] ?? '',
      },
    );

    // Refresh the club so any new post/announcement shows up
    if (result == true && mounted) {
      _refreshClub();
    }
  }

  Widget _buildPendingRequestsBanner(ThemeProvider theme) {
    return InkWell(
      onTap: () async {
        final result = await Navigator.pushNamed(
          context,
          '/club-pending-requests',
          arguments: {
            'clubId': _clubData!['id'],
            'clubName': _clubData!['title'],
          },
        );
        if (result == true) {
          _loadPendingRequestsCount();
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$_pendingRequestsCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _pendingRequestsCount == 1
                    ? '1 pending membership request'
                    : '$_pendingRequestsCount pending membership requests',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: _gold),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsPanel(ThemeProvider theme) {
    if (_isLockedForPrivacy) return _buildPrivateLockedView();

    if (_loadingEvents) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    final canCreate = _isOwner || _isAdmin;

    if (_events.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (canCreate) _buildCreateEventCard(),
          const SizedBox(height: 48),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 56,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 14),
                Text(
                  'No upcoming events',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  canCreate
                      ? 'Tap above to add the first one'
                      : 'Check back soon',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (canCreate) _buildCreateEventCard(),
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
                '${_events.length} ${_events.length == 1 ? "event" : "events"}',
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
        for (final event in _events)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: EventCard(
              event: event,
              onTap: () => Navigator.pushNamed(
                context,
                '/event-detail',
                arguments: {'event': event},
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCreateEventCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleCreateEvent,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create new event',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Plan a drive, meet or track day',
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: _muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCreateEvent() async {
    final result = await Navigator.pushNamed(
      context,
      '/add-event', // adjust to your route name
      arguments: {'clubId': _clubData?['id'], 'clubName': _clubData?['title']},
    );

    if (result == true && mounted) {
      setState(() => _eventsLoaded = false);
      _loadClubEvents();
    }
  }

  Widget _buildAboutPanel(ThemeProvider theme) {
    final description = (_clubData?['description'] ?? '') as String;
    // final location = (_clubData?['location'] ?? '') as String;
    // final locationType = _clubData?['location_type'] == 1
    //     ? 'National'
    //     : 'Local / Regional';
    // final website = (_clubData?['website'] ?? '') as String;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        if (description.isNotEmpty) ...[
          const Text(
            'About',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Html(
            data: description,
            style: {
              'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
              'p': Style(
                fontSize: FontSize(14),
                lineHeight: LineHeight(1.5),
                color: _ink.withOpacity(0.85),
                margin: Margins.only(bottom: 12),
              ),
              'b': Style(fontWeight: FontWeight.w600),
              'i': Style(fontStyle: FontStyle.italic),
              'a': Style(color: _gold, textDecoration: TextDecoration.none),
            },
            onAnchorTap: (url, _, __) => _openUrl(url ?? ''),
            onLinkTap: (url, _, __) => _openUrl(url ?? ''),
          ),
          const SizedBox(height: 16),
        ],
        // const Text(
        //   'Details',
        //   style: TextStyle(
        //     color: _ink,
        //     fontSize: 15,
        //     fontWeight: FontWeight.w700,
        //   ),
        // ),
        // const SizedBox(height: 12),
        // // HARDCODED: founded date — no field in your data model yet
        // const _DetailRow(
        //   icon: Icons.calendar_today_outlined,
        //   label: 'Founded',
        //   value: 'March 2017',
        // ),
        // const SizedBox(height: 12),
        // _DetailRow(
        //   icon: Icons.location_on_outlined,
        //   label: 'Based in',
        //   value: location.isNotEmpty ? location : locationType,
        // ),
        // if (website.isNotEmpty) ...[
        //   const SizedBox(height: 12),
        //   _DetailRow(
        //     icon: Icons.public,
        //     label: 'Website',
        //     value: website,
        //     isLink: true,
        //     onTap: () => _openUrl(website),
        //   ),
        // ],
        // // HARDCODED: contact email — no field on club model
        // const SizedBox(height: 12),
        // const _DetailRow(
        //   icon: Icons.mail_outline,
        //   label: 'Contact',
        //   value: 'hello@example.com',
        // ),
        // const SizedBox(height: 24),
        // // HARDCODED: rules — no field on club model
        // const Text(
        //   'Rules & guidelines',
        //   style: TextStyle(
        //     color: _ink,
        //     fontSize: 15,
        //     fontWeight: FontWeight.w700,
        //   ),
        // ),
        // const SizedBox(height: 8),
        // for (final rule in const [
        //   'Be respectful — this is a community first.',
        //   'No selling cars or parts in the main feed.',
        //   'Drive responsibly. We endorse legal driving only.',
        //   'Keep event sign-ups honest — no shows hurt the club.',
        // ])
        //   Padding(
        //     padding: const EdgeInsets.only(bottom: 6),
        //     child: Row(
        //       crossAxisAlignment: CrossAxisAlignment.start,
        //       children: [
        //         Padding(
        //           padding: const EdgeInsets.only(top: 8),
        //           child: Container(
        //             width: 4,
        //             height: 4,
        //             decoration: BoxDecoration(
        //               color: _ink.withOpacity(0.85),
        //               shape: BoxShape.circle,
        //             ),
        //           ),
        //         ),
        //         const SizedBox(width: 10),
        //         Expanded(
        //           child: Text(
        //             rule,
        //             style: TextStyle(
        //               color: _ink.withOpacity(0.85),
        //               fontSize: 14,
        //               height: 1.5,
        //             ),
        //           ),
        //         ),
        //       ],
        //     ),
        //   ),
      ],
    );
  }

  Widget _buildSkeleton(ThemeProvider theme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(height: 200, color: Colors.grey.shade200),
          const SizedBox(height: 60),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 20,
            width: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 14,
            width: 140,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubCommunityFeed extends StatefulWidget {
  final String clubId;
  final VoidCallback onCompose;
  final bool isMember;
  final bool isOwner;
  final bool hasPendingRequest;
  final VoidCallback handleJoinLeave;
  final bool isPublicClub;

  const _ClubCommunityFeed({
    required this.clubId,
    required this.onCompose,
    required this.isMember,
    required this.isOwner,
    required this.hasPendingRequest,
    required this.handleJoinLeave,
    required this.isPublicClub,
  });

  @override
  State<_ClubCommunityFeed> createState() => _ClubCommunityFeedState();
}

class _ClubCommunityFeedState extends State<_ClubCommunityFeed>
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
      final result = await ClubApiService.fetchClubPosts(
        clubId: widget.clubId,
        page: _page + 1,
        perPage: _pageSize,
        kind: 'community',
      );

      if (!mounted) return;

      final newPosts =
          (result?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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

  Widget _buildPrivateLockedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline, size: 28, color: _gold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Private Club',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Join the club to view posts and events',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (!widget.hasPendingRequest) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 180,
                child: _PrimaryActionButton(
                  icon: Icons.add,
                  label: 'Join Club',
                  onTap: widget.handleJoinLeave,
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _chip,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_empty, size: 14, color: _muted),
                    SizedBox(width: 6),
                    Text(
                      'Request pending',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // ── Non-member view: only show the locked screen ─────────────────
    if (!widget.isMember && !widget.isOwner && !widget.isPublicClub) {
      return _buildPrivateLockedView();
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          // Compose prompt — only for members/owners
          if (widget.isMember || widget.isOwner)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _ComposePrompt(onTap: widget.onCompose),
              ),
            ),

          // Empty state when no posts and not loading
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
                      widget.isMember || widget.isOwner
                          ? 'Be the first to share something'
                          : 'Members will start posting here',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Posts — lazy via SliverList
          if (_posts.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final post = _posts[i];

                return PostCard(
                  key: ValueKey(post['id']),
                  post: post,
                  onTapProfile: () {},
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

          // Loading / end-of-feed indicator
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
                    ? Text(
                        'You\'re all caught up',
                        style: const TextStyle(color: _muted, fontSize: 13),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Bottom padding for floating pill nav
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _ComposePrompt extends StatelessWidget {
  final VoidCallback onTap;

  const _ComposePrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    final avatarUrl = user?.profileImage;

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
                clipBehavior: Clip.antiAlias,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person,
                          size: 20,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Share something with the club…',
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

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _gold,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
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
      color: _chip,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _ink, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
