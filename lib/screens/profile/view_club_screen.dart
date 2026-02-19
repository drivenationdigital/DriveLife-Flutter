import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/join_club_modal.dart';
import 'package:drivelife/screens/clubs/view_members_screen.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';

class ClubViewScreen extends StatefulWidget {
  final int? clubPostId;
  final bool showAppBar;
  final bool isOwnClub;

  const ClubViewScreen({
    super.key,
    this.clubPostId,
    this.showAppBar = true,
    this.isOwnClub = false,
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

  List<Map<String, dynamic>> _events = [];
  bool _loadingEvents = false;
  bool _eventsLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadClubData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 0 && !_eventsLoaded) {
      _loadClubEvents();
    }
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

      print(data);

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

        print(data);
        if (mounted && data != null) {
          setState(() {
            _clubData = data;
            _isMember = data['is_member'] ?? false;
            _isOwner = data['is_owner'] ?? false;
            _hasPendingRequest = data['has_pending_request'] ?? false;
            _isLoading = false;
          });

          
          _loadClubEvents();
        }
      }
    } catch (e) {
      print('❌ Error loading club: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshClub() async {
    setState(
      () => _eventsLoaded = false,
    ); // Reset events loaded state to allow reloading
    await _loadClubData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                leadingWidth: 96,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                title: Image.asset('assets/logo-dark.png', height: 18),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.black),
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.search);
                    },
                  ),
                  // ✅ Using the actionIcons helper for multiple icons at once
                  ...SharedHeaderIcons.actionIcons(
                    iconColor: Colors.black,
                    showQr: false, // Already shown in leading
                    showNotifications: true,
                  ),
                ],
              )
            : null,
        body: _buildSkeleton(theme),
      );
    }

    if (_clubData == null) {
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                leadingWidth: 96,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                title: Image.asset('assets/logo-dark.png', height: 18),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.black),
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.search);
                    },
                  ),
                  // ✅ Using the actionIcons helper for multiple icons at once
                  ...SharedHeaderIcons.actionIcons(
                    iconColor: Colors.black,
                    showQr: false, // Already shown in leading
                    showNotifications: true,
                  ),
                ],
              )
            : null,
        backgroundColor: theme.backgroundColor,
        body: const Center(child: Text('Club not found')),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      // ✅ Transparent app bar that floats over the cover image
      extendBodyBehindAppBar: widget.showAppBar,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              leadingWidth: 96,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
                  ),
                ],
              ),
              title: Image.asset('assets/logo-dark.png', height: 18),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.black),
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.search);
                  },
                ),
                // ✅ Using the actionIcons helper for multiple icons at once
                ...SharedHeaderIcons.actionIcons(
                  iconColor: Colors.black,
                  showQr: false, // Already shown in leading
                  showNotifications: true,
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshClub,
        color: theme.primaryColor,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            // ✅ Cover image — scrolls away naturally (NOT pinned)
            SliverToBoxAdapter(child: _buildCoverWithLogo(theme)),
            // ✅ Club info scrolls with the page
            SliverToBoxAdapter(child: _buildClubInfo(theme)),
            // ✅ Tab bar — NOT pinned, scrolls with content
            SliverToBoxAdapter(child: _buildTabBar(theme)),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildEventsTab(theme),
              _buildAnnouncementsTab(theme),
              _buildAboutTab(theme),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Cover image with gradient overlay + logo overlapping bottom edge
  Widget _buildCoverWithLogo(ThemeProvider theme) {
    final logo = _clubData?['logo'];

    return SizedBox(
      height: widget.showAppBar ? 350 : 240, // Extra space if app bar is shown
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover photo
          Positioned.fill(
            child: _clubData?['cover_image'] != null
                ? Image.network(
                    _clubData!['cover_image'],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildCoverPlaceholder(theme),
                  )
                : _buildCoverPlaceholder(theme),
          ),

          // Gradient scrim at bottom for readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.45)],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),

          // Logo badge — centered, overlapping the bottom edge
          Positioned(
            bottom: -48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.backgroundColor, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  color: Colors.white,
                  image: logo != null
                      ? DecorationImage(
                          image: NetworkImage(logo),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: logo == null
                    ? Icon(
                        Icons.car_repair,
                        size: 44,
                        color: theme.primaryColor,
                      )
                    : null,
              ),
            ),
          ),
        ],
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

  // ✅ Club name, stats, buttons — all scroll freely
  Widget _buildClubInfo(ThemeProvider theme) {
    final clubType = _clubData!['club_type'] == '1' ? 'Private' : 'Public';
    final memberCount = _clubData!['member_count'] ?? 0;
    final facebook = _clubData!['facebook'];
    final instagram = _clubData!['instagram'];
    final website = _clubData!['website'];

    return Padding(
      padding: const EdgeInsets.only(top: 60, bottom: 4),
      child: Column(
        children: [
          // Club name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _clubData!['title'] ?? '',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 6),

          // Type • members
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  clubType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubMembersScreen(
                      clubId: _clubData!['id'].toString(),
                      clubName: _clubData!['title'] ?? '',
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$memberCount members',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 15,
                      color: Colors.grey[500],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Action buttons
          if (!_isOwner)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: _isMember
                          ? 'Leave Club'
                          : _hasPendingRequest
                          ? 'Cancel Request'
                          : 'Join Club',
                      icon: _isMember
                          ? Icons.exit_to_app
                          : _hasPendingRequest
                          ? Icons.cancel
                          : Icons.group_add,
                      filled: !_isMember,
                      color: theme.primaryColor,
                      onTap: _handleJoinLeave,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: 'Email Club',
                      icon: Icons.email_outlined,
                      filled: false,
                      color: theme.primaryColor,
                      onTap: _handleEmailClub,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: 'Merch',
                      icon: Icons.shopping_bag_outlined,
                      filled: false,
                      color: theme.primaryColor,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),

          // Owner/Admin badge
          if (_isOwner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_rounded,
                    size: 16,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isOwner ? 'Club Owner' : 'Club Admin',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Social links
          if (_hasSocials(facebook, instagram, website))
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (facebook != null && facebook.toString().isNotEmpty)
                  _buildSocialChip(
                    Icons.facebook,
                    'Facebook',
                    theme,
                    () => _openUrl(facebook),
                  ),
                if (instagram != null && instagram.toString().isNotEmpty)
                  _buildSocialChip(
                    Icons.camera_alt_outlined,
                    'Instagram',
                    theme,
                    () => _openUrl(instagram),
                  ),
                if (website != null && website.toString().isNotEmpty)
                  _buildSocialChip(
                    Icons.language_rounded,
                    'Website',
                    theme,
                    () => _openUrl(website),
                  ),
              ],
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  bool _hasSocials(dynamic facebook, dynamic instagram, dynamic website) {
    return (facebook != null && facebook.toString().isNotEmpty) ||
        (instagram != null && instagram.toString().isNotEmpty) ||
        (website != null && website.toString().isNotEmpty);
  }

  Widget _buildSocialChip(
    IconData icon,
    String label,
    ThemeProvider theme,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.primaryColor.withOpacity(0.18)),
          ),
          child: Icon(icon, color: theme.primaryColor, size: 20),
        ),
      ),
    );
  }

  // ✅ Tab bar rendered as a normal widget (not a SliverPersistentHeader), so it scrolls
  Widget _buildTabBar(ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'Events'),
          Tab(text: 'Announcements'),
          Tab(text: 'About'),
        ],
      ),
    );
  }

  Widget _buildEventsTab(ThemeProvider theme) {
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        return _buildEventCard(event, theme);
      },
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, ThemeProvider theme) {
    final startDate = event['start_date'] ?? '';
    final location = event['location'] ?? 'TBA';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/event-detail',
            arguments: {'event': event},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // Event image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: event['cover_image'] != null
                  ? Image.network(
                      event['cover_image'],
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildEventPlaceholder(),
                    )
                  : _buildEventPlaceholder(),
            ),

            // Event details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (startDate.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatEventDate(startDate),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      location,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventPlaceholder() {
    return Container(
      width: 100,
      height: 100,
      color: Colors.grey.shade300,
      child: const Icon(Icons.event, size: 40, color: Colors.grey),
    );
  }

  String _formatEventDate(String date) {
    try {
      // Parse "02/15/2026 10:00 AM" format
      final parts = date.split(' ');
      if (parts.isEmpty) return date;

      final dateParts = parts[0].split('/');
      if (dateParts.length != 3) return date;

      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);

      final monthNames = [
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

  Widget _buildAnnouncementsTab(ThemeProvider theme) {
    if (_clubData!['announcements'] != null &&
        (_clubData!['announcements'] as List).isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: (_clubData!['announcements'] as List).length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final announcement = _clubData!['announcements'][index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.announcement_rounded,
                color: theme.primaryColor,
                size: 20,
              ),
            ),
            title: Text(
              announcement['content'] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              announcement['date'] ?? '',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          );
        },
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.announcement_rounded,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 14),
          Text(
            'No announcements yet',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab(ThemeProvider theme) {
    final description = _clubData!['description'] ?? '';
    final location = _clubData!['location'] ?? '';
    final locationType = _clubData!['location_type'] == 1
        ? 'National'
        : 'Local / Regional';
    final website = _clubData!['website'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty) ...[
            _buildSectionHeader('About'),
            const SizedBox(height: 10),
            // Text(
            //   description,
            //   style: TextStyle(
            //     fontSize: 14,
            //     height: 1.65,
            //     color: Colors.grey.shade700,
            //   ),
            // ),
            // render HTML description with basic tags (p, br, b, i)
            Html(
              data: description,
              style: {
                'p': Style(
                  fontSize: FontSize(14),
                  lineHeight: LineHeight(1.65),
                  color: Colors.grey.shade700,
                ),
                'b': Style(fontWeight: FontWeight.w600),
                'i': Style(fontStyle: FontStyle.italic),
              },
              onAnchorTap: (url, attributes, element) =>
                  _openUrl(url!), // Handle link taps
              onLinkTap: (url, attributes, element) =>
                  _openUrl(url!), // Handle link taps
            ),
            const SizedBox(height: 28),
          ],
          _buildSectionHeader('Details'),
          const SizedBox(height: 12),
          _buildDetailCard(theme, [
            _DetailItem(label: 'Type', value: locationType),
            if (location.isNotEmpty)
              _DetailItem(label: 'Location', value: location),
            if (website.isNotEmpty)
              _DetailItem(label: 'Website', value: website, isLink: true),
          ]),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildDetailCard(ThemeProvider theme, List<_DetailItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: item.isLink
                          ? GestureDetector(
                              onTap: () => _openUrl(item.value),
                              child: Text(
                                item.value,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.primaryColor,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            )
                          : Text(
                              item.value,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              if (i < items.length - 1)
                Divider(height: 1, color: Colors.grey.shade200),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSkeleton(ThemeProvider theme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Cover shimmer
          Container(height: 240, color: Colors.grey.shade200),
          const SizedBox(height: 60),
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 20,
            width: 160,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 14,
            width: 100,
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
      // TODO: leave logic
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

  void _handleEmailClub() {
    // TODO: Implement email club
  }

  void _openUrl(String url) {
    // TODO: url_launcher
  }
}

// ─── Reusable action button ────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: filled ? color : Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detail item model ─────────────────────────────────────────────────────

class _DetailItem {
  final String label;
  final String value;
  final bool isLink;

  const _DetailItem({
    required this.label,
    required this.value,
    this.isLink = false,
  });
}
