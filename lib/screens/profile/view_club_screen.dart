import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
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
const Color _panelBg = Color(0xFFF7F7F7);

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

  // Upload completion tracking — refresh club posts when an upload finishes
  final Set<String> _completedUploads = {};
  bool _refreshScheduled = false;
  UploadPostProvider? _uploadProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);

    _loadClubData();
  }

  @override
  void dispose() {
    _uploadProvider?.removeListener(_onUploadsChanged);
    _tabController.dispose();
    super.dispose();
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
    if (_tabController.index == 2 && !_membersLoaded) {
      _loadMembers();
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
        setState(() => _hasPendingRequest = true);
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

  Future<void> _loadClubPosts() async {
    if (_loadingClubPosts || _clubData == null) return;

    setState(() => _loadingClubPosts = true);

    try {
      final data = await ClubApiService.fetchClubPosts(
        clubId: _clubData!['id'].toString(),
        page: 1,
        perPage: 10,
      );

      if (!mounted) return;

      if (data != null && data['success'] == true) {
        setState(() {
          _clubPosts = (data['data'] as List?) ?? [];
          _clubPostsLoaded = true;
          _loadingClubPosts = false;
        });
      } else {
        setState(() {
          _clubPostsLoaded = true;
          _loadingClubPosts = false;
        });
      }
    } catch (e) {
      print('❌ Error loading club posts: $e');
      if (mounted) setState(() => _loadingClubPosts = false);
    }
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
    final isPrivate = _clubData!['club_type'] == '1';
    return isPrivate && !_isMember && !_isOwner;
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

        // If widget.tab is set, open that tab instead of defaulting to "Posts"
        if (widget.tab != null) {
          print('Opening club with tab: ${widget.tab}');
          final tabIndex = [
            'feed',
            'events',
            'members',
            'about',
          ].indexOf(widget.tab!.toLowerCase());
          if (tabIndex != -1) {
            _tabController.index = tabIndex;
          }
        }

        _loadClubEvents();
        _loadClubPosts();
        _loadPendingRequestsCount();
      } else {
        final data = await ClubApiService.getClubDetails(
          clubPostId: widget.clubPostId!,
        );

        if (mounted && data != null) {
          setState(() {
            _clubData = data;
            _isMember = data['is_member'] ?? false;
            _isOwner = data['is_owner'] ?? false;
            _hasPendingRequest = data['has_pending_request'] ?? false;
            _isLoading = false;
          });

          // If widget.tab is set, open that tab instead of defaulting to "Posts"
          if (widget.tab != null) {
            print('Opening club with tab: ${widget.tab}');
            final tabIndex = [
              'feed',
              'events',
              'members',
              'about',
            ].indexOf(widget.tab!.toLowerCase());
            if (tabIndex != -1) {
              _tabController.index = tabIndex;
            }
          }

          _loadClubEvents();
          _loadClubPosts();
        }
      }
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
        appBar: widget.showAppBar ? _buildAppBar() : null,
        body: _buildSkeleton(theme),
      );
    }

    if (_clubData == null) {
      return Scaffold(
        appBar: widget.showAppBar ? _buildAppBar() : null,
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
          appBar: isUpdates ? _buildAppBar() : null,
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
                        _buildMembersPanel(theme),
                        _buildCommunityPanel(theme),
                        _buildAboutPanel(theme),
                      ],
                    ),
                  ),
                ],
              ),
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
      slivers: [
        // Cover + logo + name + meta + actions
        SliverToBoxAdapter(child: _buildHeaderArea(theme)),

        // Owner pending-requests banner
        if (_isOwner && _pendingRequestsCount > 0)
          SliverToBoxAdapter(child: _buildPendingRequestsBanner(theme)),

        // Empty state when no content
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
          ),

        // Posts — lazy-rendered via SliverList
        if (hasPosts)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              // Interleave a thin divider between posts
              if (i.isOdd) {
                return Container(height: 8, color: const Color(0xFFF5F5F5));
              }
              final postIndex = i ~/ 2;
              final post = _clubPosts[postIndex] as Map<String, dynamic>;

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
            }, childCount: _clubPosts.length * 2 - 1),
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

        // Announcements — also lazy via SliverList
        if (hasAnnouncements)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              if (i.isOdd) {
                return Container(height: 8, color: const Color(0xFFF5F5F5));
              }
              final aIndex = i ~/ 2;
              return AnnouncementCard(
                authorName: _clubData?['title'] ?? 'Club',
                posted: (announcements[aIndex]['date'] ?? '').toString(),
                content: (announcements[aIndex]['content'] ?? '').toString(),
                logoUrl: _clubData?['logo'] as String?,
              );
            }, childCount: announcements.length * 2 - 1),
          ),

        // Bottom padding so the floating pill nav doesn't cover the last card
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
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

  Widget _buildMembersPanel(ThemeProvider theme) {
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
            isViewerAdmin: _isOwner,
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
            // Optimistic update
            setState(() {
              _members.removeWhere((m) => m['id'] == member['id']);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$name removed from the club')),
            );
          }
        }
        return;
    }
  }

  AppBar _buildAppBar() {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leadingWidth: 96,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          ),
        ],
      ),
      title: Image.asset('assets/logo-dark.png', height: 18),
      actions: [
        IconButton(
          icon: iconSvg(
            'assets/app-icons/header-search.svg',
            theme,
            size: 20,
            alwaysActive: true,
          ),
          onPressed: () {
            Navigator.pushNamed(context, AppRoutes.search);
          },
        ),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.black),
          onPressed: () {
            Share.share(
              'Check out this club on DriveLife: ${_clubData?['title'] ?? 'a club'}\n\n'
              'https://app.mydrivelife.com/club/${_clubData?['id']}',
            );
          },
        ),
        const SizedBox(width: 8), // right-edge breathing room
      ],
    );
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

            GestureDetector(
              onTap: () {
                Share.share(
                  'Check out this club on DriveLife: ${_clubData?['title']}\n\n'
                  'https://drivelife.app/club/${_clubData?['id']}',
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
                child: const Icon(Icons.more_horiz, size: 18, color: _ink),
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
                _segButton(label: 'Members', index: 2),
                _segButton(label: 'Community', index: 3),
                _segButton(label: 'About', index: 4),
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
          padding: const EdgeInsets.symmetric(vertical: 9),
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
              fontSize: 11.5, // small for 5 tabs
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommunityPanel(ThemeProvider theme) {
    return _CommunityPanel(onCompose: _handleCreateClubPost);
  }

  Widget _buildTopOverlay(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 4,
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
          GestureDetector(
            onTap: () => _showMoreMenu(context),
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

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: _ink),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                Share.share(
                  'Check out this club on DriveLife: ${_clubData?['title']}\n\n'
                  'https://drivelife.app/club/${_clubData?['id']}',
                );
              },
            ),
            if (_isOwner) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: _ink),
                title: const Text('Edit club'),
                onTap: () {
                  Navigator.pop(context);
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
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderArea(ThemeProvider theme) {
    final coverImage = _clubData?['cover_image'];
    final logo = _clubData?['logo'];
    final title = (_clubData?['title'] ?? '') as String;
    final memberCount = _clubData?['member_count'] ?? 0;
    // final clubType = _clubData?['club_type'] == '1' ? 'Private' : 'Public';
    final location = _clubData?['location'] ?? 'National Club';
    final verified = _clubData?['is_verified'] == true;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            SizedBox(
              height: 200,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // const Icon(
                      //   Icons.directions_car_outlined,
                      //   size: 14,
                      //   color: _gold,
                      // ),
                      // const SizedBox(width: 6),
                      // Text(
                      //   location,
                      //   style: const TextStyle(color: _muted, fontSize: 13),
                      // ),
                      // const SizedBox(width: 10),
                      // Container(
                      //   width: 4,
                      //   height: 4,
                      //   decoration: BoxDecoration(
                      //     color: _muted.withOpacity(0.6),
                      //     shape: BoxShape.circle,
                      //   ),
                      // ),
                      const SizedBox(width: 10),
                      const Icon(Icons.people_outline, size: 14, color: _gold),
                      const SizedBox(width: 6),
                      // Members — tappable to open ClubMembersScreen
                      GestureDetector(
                        onTap: _isLockedForPrivacy
                            ? null
                            : () {
                                _tabController.animateTo(2);
                              },
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$memberCount ',
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(
                                text: 'members',
                                style: TextStyle(color: _muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Actions — depends on owner / member / pending state
                  _buildActionRow(theme),
                  // Social chips, if any
                  // if (_hasSocials())
                  //   Padding(
                  //     padding: const EdgeInsets.only(top: 14),
                  //     child: Row(children: _buildSocialChips(theme), mainAxisAlignment: MainAxisAlignment.center,),
                  //   ),
                ],
              ),
            ),
          ],
        ),
        // Logo + status pill (positioned to overlap cover by 48px)
        Positioned(
          left: 20,
          right: 20,
          top: 200 - 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
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
    if (_isOwner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // const SizedBox(height: 10),
          // Owner badge sits below the action row
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, size: 14, color: _gold),
                  SizedBox(width: 6),
                  Text(
                    'Club Owner',
                    style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.add,
                  label: 'Create Post',
                  onTap: _handleCreateClubPost,
                ),
              ),
              const SizedBox(width: 8),
              _ChipActionButton(
                icon: Icons.link_outlined,
                label: 'More',
                onTap: _showClubLinks,
              ),
              const SizedBox(width: 8),
              _ChipActionButton(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/add-club',
                    arguments: {'existingClubId': _clubData!['id'].toString()},
                  ).then((result) {
                    if (!mounted) return;

                    if (result == 'deleted') {
                      // Club was deleted — pop the view screen back to the list
                      Navigator.pop(context, 'deleted');
                      return;
                    }

                    if (result == true) {
                      _refreshClub();
                    }
                  });
                },
              ),
            ],
          ),
        ],
      );
    }

    final joinLabel = _isMember
        ? 'Leave Club'
        : _hasPendingRequest
        ? 'Cancel Request'
        : 'Join Club';
    final joinIcon = _isMember
        ? Icons.exit_to_app
        : _hasPendingRequest
        ? Icons.close
        : Icons.add;

    return Row(
      children: [
        Expanded(
          child: _PrimaryActionButton(
            icon: joinIcon,
            label: joinLabel,
            onTap: _handleJoinLeave,
          ),
        ),
        const SizedBox(width: 8),
        _ChipActionButton(
          icon: Icons.link,
          label: 'More',
          onTap: _showClubLinks,
        ),
      ],
    );
  }

  Future<void> _handleCreateClubPost() async {
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

  Widget _buildPostsPanel(ThemeProvider theme) {
    if (_isLockedForPrivacy) return _buildPrivateLockedView();

    // Initial load spinner
    if (_loadingClubPosts && _clubPosts.isEmpty && !_clubPostsLoaded) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    final announcements = (_clubData?['announcements'] is List)
        ? (_clubData!['announcements'] as List)
        : const [];

    final hasPosts = _clubPosts.isNotEmpty;
    final hasAnnouncements = announcements.isNotEmpty;

    // Both empty
    if (!hasPosts && !hasAnnouncements) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              'Nothing here yet',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Check back soon',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Real club posts
        if (hasPosts)
          for (int i = 0; i < _clubPosts.length; i++) ...[
            PostCard(
              key: ValueKey(_clubPosts[i]['id']),
              post: _clubPosts[i] as Map<String, dynamic>,
              onTapProfile: () {
                // if (!mounted) return;
                // final post = _clubPosts[i];
                // if (post['is_event'] == true) return;
                // Navigator.pushNamed(
                //   context,
                //   '/view-profile',
                //   arguments: {
                //     'userId': post['user_id'],
                //     'username': post['username'],
                //   },
                // );
              },
              onLikeChanged: (isLiked) {
                setState(() {
                  final post = _clubPosts[i] as Map<String, dynamic>;
                  post['is_liked'] = isLiked;
                  post['likes_count'] =
                      (post['likes_count'] as int) + (isLiked ? 1 : -1);
                });
              },
              onDelete: () {
                _refreshClub();
              },
            ),
            if (i < _clubPosts.length - 1)
              Container(height: 8, color: const Color(0xFFF5F5F5)),
          ],

        // Divider between posts and announcements
        if (hasPosts && hasAnnouncements)
          Container(height: 8, color: const Color(0xFFF5F5F5)),

        // Section header for announcements (only if both sections exist)
        if (hasAnnouncements && hasPosts)
          Padding(
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

        // Announcements
        if (hasAnnouncements)
          for (int i = 0; i < announcements.length; i++) ...[
            AnnouncementCard(
              authorName: _clubData?['title'] ?? 'Club',
              posted: (announcements[i]['date'] ?? '').toString(),
              content: (announcements[i]['content'] ?? '').toString(),
              logoUrl: _clubData?['logo'] as String?,
            ),
            if (i < announcements.length - 1)
              Container(height: 8, color: const Color(0xFFF5F5F5)),
          ],
      ],
    );
  }

  Widget _buildEventsPanel(ThemeProvider theme) {
    if (_isLockedForPrivacy) return _buildPrivateLockedView();

    if (_loadingEvents) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_events.isEmpty) {
      return Center(
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
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
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

class _CommunityPanel extends StatefulWidget {
  final VoidCallback onCompose;

  const _CommunityPanel({required this.onCompose});

  @override
  State<_CommunityPanel> createState() => _CommunityPanelState();
}

enum _CommunitySubTab { latest, photos, discussion, questions }

class _CommunityPanelState extends State<_CommunityPanel>
    with AutomaticKeepAliveClientMixin {
  _CommunitySubTab _active = _CommunitySubTab.latest;

  @override
  bool get wantKeepAlive => true; // ← keeps state when switching club tabs

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    return Column(
      children: [
        // Compose prompt
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: GestureDetector(
            onTap: widget.onCompose,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: const ClipOval(
                      child: Icon(Icons.person, size: 18, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Share something with the club…',
                      style: TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add, size: 16, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Filter chips
        const SizedBox(height: 12),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chipWidget(_CommunitySubTab.latest, 'Latest'),
              _chipWidget(_CommunitySubTab.photos, 'Photos'),
              _chipWidget(_CommunitySubTab.discussion, 'Discussion'),
              _chipWidget(_CommunitySubTab.questions, 'Questions'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Sub-tab content — IndexedStack keeps each tab's state alive
        Expanded(
          child: IndexedStack(
            index: _active.index,
            sizing: StackFit.expand,
            children: const [
              _LatestFeed(),
              _PhotosFeed(),
              _DiscussionFeed(),
              _QuestionsFeed(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipWidget(_CommunitySubTab tab, String label) {
    final active = _active == tab;
    return GestureDetector(
      onTap: () => setState(() => _active = tab),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _ink : _chip,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LatestFeed extends StatefulWidget {
  const _LatestFeed();

  @override
  State<_LatestFeed> createState() => _LatestFeedState();
}

class _LatestFeedState extends State<_LatestFeed>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;

  static const int _pageSize = 8;

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
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    // Hardcoded data generator — replace with real API call later
    final newPage = List.generate(_pageSize, (i) {
      final idx = _page * _pageSize + i;
      return _samplePost(idx);
    });

    setState(() {
      _posts.addAll(newPage);
      _loading = false;
      _page++;
      // Hard cap for hardcoded data — pretend we run out at 40 items
      if (_posts.length >= 40) _hasMore = false;
    });
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
      onRefresh: _refresh,
      color: _gold,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              if (i.isOdd) {
                return Container(height: 8, color: const Color(0xFFF5F5F5));
              }
              return _CommunityPostCard(post: _posts[i ~/ 2]);
            }, childCount: _posts.length * 2 - (_posts.isEmpty ? 0 : 1)),
          ),

          // Loading spinner / end indicator
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _hasMore
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _gold,
                        ),
                      )
                    : Text(
                        _posts.isEmpty
                            ? 'No posts yet'
                            : 'You\'re all caught up',
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
              ),
            ),
          ),

          // Bottom padding for the floating pill
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _PhotosFeed extends StatefulWidget {
  const _PhotosFeed();

  @override
  State<_PhotosFeed> createState() => _PhotosFeedState();
}

class _PhotosFeedState extends State<_PhotosFeed>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  final List<String> _photos = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;

  static const int _pageSize = 12;

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
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final newPage = List.generate(_pageSize, (i) {
      final idx = _page * _pageSize + i;
      return _samplePhoto(idx);
    });

    setState(() {
      _photos.addAll(newPage);
      _loading = false;
      _page++;
      if (_photos.length >= 60) _hasMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PhotoTile(url: _photos[i]),
              childCount: _photos.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: _hasMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    )
                  : Text(
                      _photos.isEmpty
                          ? 'No photos yet'
                          : 'You\'re all caught up',
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _DiscussionFeed extends StatelessWidget {
  const _DiscussionFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text(
            'Discussion threads',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Long-form posts and ongoing conversations '
              'will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionsFeed extends StatelessWidget {
  const _QuestionsFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.help_outline, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text(
            'Q&A',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Members can ask questions and get answers '
              'from the community here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  const _CommunityPostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final imageUrl = post['image_url'] as String?;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post['author'] as String,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${post['handle']} · ${post['time']}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_horiz, size: 20, color: _muted),
              ],
            ),
          ),

          if (imageUrl != null) ...[
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: Colors.grey.shade200,
                child: Image.network(imageUrl, fit: BoxFit.cover),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                post['caption'] as String,
                style: const TextStyle(color: _ink, fontSize: 14, height: 1.4),
              ),
            ),
          ],

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.favorite_border, size: 22, color: _ink),
                const SizedBox(width: 6),
                Text(
                  '${post['likes']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(width: 20),
                const Icon(Icons.mode_comment_outlined, size: 22, color: _ink),
                const SizedBox(width: 6),
                Text(
                  '${post['comments']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),

          if (imageUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text:
                          '${(post['handle'] as String).replaceAll('@', '')} ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: post['caption'] as String),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  const _PhotoTile({required this.url});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        color: Colors.grey.shade200,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          // Important — Flutter's cache is per URL, so repeat URLs cost nothing
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : Container(color: Colors.grey.shade200),
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.grey.shade400,
            ),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _samplePost(int idx) {
  final authors = [
    ('Kelly Bennett', '@classic_kelly', 'ADMIN'),
    ('Tom Eastwood', '@tom_e36', 'MOD'),
    ('Sophie Wright', '@sophie.drives', null),
    ('James Robertson', '@james_r33', null),
    ('Sarah Mills', '@sarahdrives', null),
  ];
  final a = authors[idx % authors.length];

  final imgs = [
    'https://images.unsplash.com/photo-1542362567-b07e54358753?w=1200',
    'https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=1200',
    'https://images.unsplash.com/photo-1544829099-b9a0c07fad1a?w=1200',
    null, // text-only
    'https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=1200',
  ];

  final captions = [
    'Caught the GT3 in perfect light on the way back from Hardwick.',
    'Anyone running Michelin Cup 2s through winter? Looking for honest takes.',
    'Saturday morning detail before the Dales run. Took longer than the drive itself.',
    'Best meet of the year so far. Already counting down to next month.',
    'New wheels finally fitted. Worth the six-week wait.',
  ];

  return {
    'id': idx,
    'author': a.$1,
    'handle': a.$2,
    'badge': a.$3,
    'time': '${idx + 1}h ago',
    'image_url': imgs[idx % imgs.length],
    'caption': captions[idx % captions.length],
    'likes': 12 + (idx * 7) % 90,
    'comments': 2 + (idx * 3) % 25,
  };
}

String _samplePhoto(int idx) {
  final photos = [
    'https://images.unsplash.com/photo-1542362567-b07e54358753?w=600',
    'https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=600',
    'https://images.unsplash.com/photo-1544829099-b9a0c07fad1a?w=600',
    'https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=600',
    'https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=600',
    'https://images.unsplash.com/photo-1517994112540-009c47ea476b?w=600',
  ];
  return photos[idx % photos.length];
}
