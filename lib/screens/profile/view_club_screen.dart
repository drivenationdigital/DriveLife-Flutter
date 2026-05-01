import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/join_club_modal.dart';
import 'package:drivelife/screens/clubs/request_modal.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// Design tokens — match the new club profile mock
// =============================================================================
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
    this.tab
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    
    _loadClubData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          final tabIndex = ['feed', 'events', 'members', 'about']
              .indexOf(widget.tab!.toLowerCase());
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

  // ===========================================================================
  // Build
  // ===========================================================================
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

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: !widget.showAppBar,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(child: _buildHeaderArea(theme)),
              if (_isOwner && _pendingRequestsCount > 0)
                SliverToBoxAdapter(child: _buildPendingRequestsBanner(theme)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(_buildTabBar(theme)),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildPostsPanel(theme),
                _buildEventsPanel(theme),
                _buildMembersPanel(theme),
                _buildAboutPanel(theme),
              ],
            ),
          ),
          // Floating overlay only when there's no app bar (cover edge-to-edge)
          if (!widget.showAppBar) _buildTopOverlay(context),
        ],
      ),
    );
  }

  Future<void> _openRequestModal(Map<String, dynamic> member) async {
    print(member);
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
         _MemberRow(
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

  void _openMemberProfile(Map<String, dynamic> member) {
    print(member);
    Navigator.pushNamed(
      context,
      '/view-profile',
      arguments: {'userId': member['user_id']},
    );
  }

  Future<void> _handleMemberAdminAction(
    Map<String, dynamic> member,
    _MemberAdminAction action,
  ) async {
    final name = member['name'] ?? 'this member';

    switch (action) {
      case _MemberAdminAction.viewProfile:
        _openMemberProfile(member);
        return;

      case _MemberAdminAction.makeAdmin:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name promoted to admin')));
        return;
      case _MemberAdminAction.removeAdmin:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$name's admin role removed")));
        return;

      case _MemberAdminAction.remove:
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
          icon: const Icon(Icons.search, color: Colors.black),
          onPressed: () => Navigator.pushNamed(context, AppRoutes.search),
        ),
        ...SharedHeaderIcons.actionIcons(
          iconColor: Colors.black,
          showQr: false,
          showNotifications: true,
        ),
      ],
    );
  }

  // ===========================================================================
  // Top floating overlay (only when no app bar)
  // ===========================================================================
  Widget _buildTopOverlay(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _OverlayCircleButton(
                icon: Icons.chevron_left,
                onTap: () => Navigator.maybePop(context),
              ),
              Row(
                children: [
                  _OverlayCircleButton(
                    icon: Icons.share_outlined,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _OverlayCircleButton(icon: Icons.more_horiz, onTap: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Header: cover + overlapping logo + name + meta + actions
  // ===========================================================================
  Widget _buildHeaderArea(ThemeProvider theme) {
    final coverImage = _clubData?['cover_image'];
    final logo = _clubData?['logo'];
    final title = (_clubData?['title'] ?? '') as String;
    final memberCount = _clubData?['member_count'] ?? 0;
    final clubType = _clubData?['club_type'] == '1' ? 'Private' : 'Public';
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
                      const Icon(
                        Icons.directions_car_outlined,
                        size: 14,
                        color: _gold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        location,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _muted.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
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
          top: 200 - 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 130,
                height: 130,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: logo != null
                      ? Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildLogoFallback(),
                        )
                      : _buildLogoFallback(),
                ),
              ),
              const SizedBox(height: 60),
              // Type pill (Public/Private) — replaces "Active community" pill
              // Padding(
              //   padding: const EdgeInsets.only(bottom: 4),
              //   child: Container(
              //     padding: const EdgeInsets.symmetric(
              //       horizontal: 10,
              //       vertical: 5,
              //     ),
              //     decoration: BoxDecoration(
              //       color: _chip,
              //       borderRadius: BorderRadius.circular(999),
              //     ),
              //     child: Row(
              //       mainAxisSize: MainAxisSize.min,
              //       children: [
              //         Container(
              //           width: 6,
              //           height: 6,
              //           decoration: const BoxDecoration(
              //             color: _activeGreen,
              //             shape: BoxShape.circle,
              //           ),
              //         ),
              //         const SizedBox(width: 6),
              //         Text(
              //           clubType,
              //           style: const TextStyle(
              //             color: _ink,
              //             fontSize: 12,
              //             fontWeight: FontWeight.w600,
              //           ),
              //         ),
              //       ],
              //     ),
              //   ),
              // ),
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
          const SizedBox(height: 10),
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
                onTap: _showClubLinks
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
          onTap: _showClubLinks
        ),
      ],
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

  // ===========================================================================
  // Pending requests banner (owner-only)
  // ===========================================================================
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
  
  bool _hasSocials() {
    final fb = _clubData?['facebook'];
    final ig = _clubData?['instagram'];
    final ws = _clubData?['website'];
    return (fb != null && fb.toString().isNotEmpty) ||
        (ig != null && ig.toString().isNotEmpty) ||
        (ws != null && ws.toString().isNotEmpty);
  }

  List<Widget> _buildSocialChips(ThemeProvider theme) {
    final fb = _clubData?['facebook'];
    final ig = _clubData?['instagram'];
    final ws = _clubData?['website'];
    final chips = <Widget>[];

    if (fb != null && fb.toString().isNotEmpty) {
      chips.add(_SocialChip(icon: Icons.facebook, onTap: () => _openUrl(fb)));
    }
    if (ig != null && ig.toString().isNotEmpty) {
      chips.add(
        _SocialChip(icon: Icons.camera_alt_outlined, onTap: () => _openUrl(ig)),
      );
    }
    if (ws != null && ws.toString().isNotEmpty) {
      chips.add(
        _SocialChip(icon: Icons.language_rounded, onTap: () => _openUrl(ws)),
      );
    }

    // Inject 8px spacing between chips
    final spaced = <Widget>[];
    for (int i = 0; i < chips.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 8));
      spaced.add(chips[i]);
    }
    return spaced;
  }
 
  Widget _buildTabBar(ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _gold,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorWeight: 2.5,
        labelColor: _ink,
        unselectedLabelColor: _muted,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: -0.1,
        ),
        tabs: const [
          Tab(text: 'Posts'),
          Tab(text: 'Events'),
          Tab(text: 'Members'),
          Tab(text: 'About'),
        ],
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
                if (!mounted) return;
                final post = _clubPosts[i];
                if (post['is_event'] == true) return;
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
            _AnnouncementCard(
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
            child: _EventCard(
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
    final location = (_clubData?['location'] ?? '') as String;
    final locationType = _clubData?['location_type'] == 1
        ? 'National'
        : 'Local / Regional';
    final website = (_clubData?['website'] ?? '') as String;

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

    final questions = List<String>.from(
      _clubData!['membership_questions'] ?? [],
    );

    if (questions.isEmpty) {
      questions.add(
        'This club requires no additional information. Do you want to submit your request to join?',
      );
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

  void _openUrl(String url) {
    print('Opening URL: $url');
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _AnnouncementCard extends StatelessWidget {
  final String authorName;
  final String posted;
  final String content;
  final String? logoUrl;

  const _AnnouncementCard({
    required this.authorName,
    required this.posted,
    required this.content,
    this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: _ink,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: logoUrl != null
                      ? Image.network(
                          logoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _logoFallback(),
                        )
                      : _logoFallback(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: _gold),
                        ],
                      ),
                      if (posted.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          posted,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              content,
              style: const TextStyle(color: _ink, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoFallback() => Container(
    color: _ink,
    alignment: Alignment.center,
    child: const Text(
      '⫽',
      style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w900),
    ),
  );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabBarDelegate(this.child);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 48;
  @override
  double get minExtent => 48;
  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

class _OverlayCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _OverlayCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.40),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
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

class _SocialChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SocialChip({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withOpacity(0.18)),
        ),
        child: Icon(icon, color: _gold, size: 18),
      ),
    );
  }
}

// =============================================================================
// Event card
// =============================================================================
class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;
  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final coverImage = event['cover_image'];
    final title = (event['name'] ?? '') as String;
    final startDate = (event['start_date'] ?? '') as String;
    final location = (event['location'] ?? 'TBA') as String;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: coverImage != null
                  ? Image.network(
                      coverImage,
                      width: 78,
                      height: 78,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _eventPlaceholder(),
                    )
                  : _eventPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (startDate.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: _gold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatEventDate(startDate),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: _gold,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold, width: 1.2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'View',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventPlaceholder() {
    return Container(
      width: 78,
      height: 78,
      color: Colors.grey.shade200,
      child: Icon(Icons.event, color: Colors.grey.shade400, size: 28),
    );
  }

  String _formatEventDate(String date) {
    try {
      final parts = date.split(' ');
      if (parts.isEmpty) return date;
      final dateParts = parts[0].split('/');
      if (dateParts.length != 3) return date;
      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);
      const monthNames = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${monthNames[month]} $day, $year';
    } catch (e) {
      return date;
    }
  }
}

// =============================================================================
// Detail row (About panel)
// =============================================================================
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLink;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLink = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: _gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isLink ? _gold : _ink,
                    fontSize: 14,
                    fontWeight: isLink ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _MemberAdminAction { viewProfile, makeAdmin, removeAdmin, remove }

class _MemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isViewerAdmin;
  final VoidCallback onTap;
  final VoidCallback? onViewRequest;
  final void Function(_MemberAdminAction) onAdminAction;

  const _MemberRow({
    required this.member,
    required this.isViewerAdmin,
    required this.onTap,
    required this.onAdminAction,
    this.onViewRequest,
  });

  @override
  Widget build(BuildContext context) {
    final name = (member['name'] ?? '') as String;
    final avatar = member['avatar'] as String?;
    final isOwner = member['is_owner'] == true;
    final isAdmin = member['is_admin'] == true;
    final isPending = member['is_pending'] == true;

    return InkWell(
      onTap: isPending ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _gold.withOpacity(0.15),
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isOwner || isAdmin || isPending) ...[
                    const SizedBox(height: 2),
                    _RoleBadge(
                      label: isOwner
                          ? 'Owner'
                          : isAdmin
                          ? 'Admin'
                          : 'Pending',
                      isPending: isPending,
                    ),
                  ],
                ],
              ),
            ),

            // Right-side action area
            if (isPending && isViewerAdmin && onViewRequest != null)
              OutlinedButton(
                onPressed: onViewRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: const BorderSide(color: _gold, width: 1.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text(
                  'View request',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              )
            else if (isViewerAdmin && !isOwner && !isPending)
              PopupMenuButton<_MemberAdminAction>(
                icon: const Icon(Icons.more_horiz, color: _muted),
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: onAdminAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _MemberAdminAction.viewProfile,
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 18, color: _ink),
                        SizedBox(width: 10),
                        Text('View profile'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _MemberAdminAction.remove,
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_remove_outlined,
                          size: 18,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Remove from club',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else if (!isPending)
              const Icon(Icons.chevron_right, size: 18, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final bool isPending;
  const _RoleBadge({required this.label, this.isPending = false});

  @override
  Widget build(BuildContext context) {
    final color = isPending ? Colors.orange.shade700 : _gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
