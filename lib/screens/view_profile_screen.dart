import 'package:drivelife/widgets/garage_tab.dart';
import 'package:drivelife/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_service.dart';
import '../providers/user_provider.dart';
import '../widgets/profile_post_grid.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ViewProfileScreen extends StatefulWidget {
  final int? userId;
  final String username;
  final bool showAppBar; // ✅ NEW: Control whether to show app bar

  const ViewProfileScreen({
    super.key,
    required this.userId,
    required this.username,
    this.showAppBar =
        true, // ✅ Default to true (show app bar when navigating to other profiles)
  });

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserService _userService = UserService();

  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isOwnProfile = false;

  static final Map<int, Map<String, dynamic>> _profileCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _checkIfOwnProfile();
    _loadUserProfileOptimized();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _checkIfOwnProfile() {
    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser != null) {
      _isOwnProfile =
          currentUser['id'] == widget.userId ||
          currentUser['username'] == widget.username;
    }
  }

  Future<void> _loadUserProfileOptimized() async {
    if (!mounted) return;

    if (widget.userId != null && _profileCache.containsKey(widget.userId)) {
      print('📦 [Profile] Using cached data for user ${widget.userId}');
      setState(() {
        _userProfile = _profileCache[widget.userId!];
        _isLoading = false;
      });

      if (!_isOwnProfile && _userProfile!['id'] != null) {
        _checkFollowStatus(_userProfile!['id']);
      }

      return;
    }

    setState(() => _isLoading = true);

    try {
      final profile = await _userService.getUserProfile(
        userId: widget.userId,
        username: widget.username,
      );

      if (!mounted) return;

      if (profile != null) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });

        if (widget.userId != null) {
          _profileCache[widget.userId!] = profile;
          print('💾 [Profile] Cached data for user ${widget.userId}');
        }

        if (!_isOwnProfile && profile['id'] != null) {
          _checkFollowStatus(profile['id']);
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load profile'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      print('Error loading profile: $e');
    }
  }

  // ✅ NEW: Refresh handler for pull-to-refresh
  Future<void> _refreshProfile() async {
    print('🔄 [Profile] Refreshing profile...');

    // Clear cache for this user
    if (widget.userId != null) {
      _profileCache.remove(widget.userId!);
    }

    // Reload profile
    await _loadUserProfileOptimized();

    // Show feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile refreshed'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _checkFollowStatus(int userId) async {
    final following = await _userService.isFollowing(userId);

    if (!mounted) return;

    setState(() => _isFollowing = following);
  }

  Future<void> _toggleFollow() async {
    if (_userProfile == null || !mounted) return;

    final userId = _userProfile!['id'];
    bool success;

    if (_isFollowing) {
      success = await _userService.unfollowUser(userId);
    } else {
      success = await _userService.followUser(userId);
    }

    if (!mounted) return;

    if (success) {
      setState(() {
        _isFollowing = !_isFollowing;

        final currentFollowers = _getFollowerCount(_userProfile!['followers']);
        if (_isFollowing) {
          _userProfile!['followers_count'] = currentFollowers + 1;
        } else {
          _userProfile!['followers_count'] = currentFollowers - 1;
        }

        if (widget.userId != null) {
          _profileCache[widget.userId!] = _userProfile!;
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFollowing ? 'Failed to unfollow' : 'Failed to follow',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _getFollowerCount(dynamic followers) {
    if (followers == null) return 0;
    if (followers is int) return followers;
    if (followers is List) return followers.length;
    if (followers is String) return int.tryParse(followers) ?? 0;
    return 0;
  }

  int _getFollowingCount(dynamic following) {
    if (following == null) return 0;
    if (following is int) return following;
    if (following is List) return following.length;
    if (following is String) return int.tryParse(following) ?? 0;
    return 0;
  }

  int _getPostsCount(dynamic postsCount) {
    if (postsCount == null) return 0;
    if (postsCount is int) return postsCount;
    if (postsCount is String) return int.tryParse(postsCount) ?? 0;
    return 0;
  }

  Future<void> _launchSocialMedia(String platform, String? username) async {
    if (username == null || username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No ${platform.capitalize()} link available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    String url = '';
    switch (platform) {
      case 'instagram':
        url = 'https://instagram.com/$username';
        break;
      case 'facebook':
        url = 'https://facebook.com/$username';
        break;
      case 'tiktok':
        url = 'https://tiktok.com/@$username';
        break;
      case 'youtube':
        url = 'https://youtube.com/@$username';
        break;
    }

    if (url.isNotEmpty) {
      print('🔗 Opening URL: $url');
      final uri = Uri.parse(url);

      try {
        final canLaunch = await canLaunchUrl(uri);

        if (canLaunch) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cannot open ${platform.capitalize()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        print('❌ Error launching URL: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening link: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showMoreOptions() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text(
                  'Share Profile',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement share
                },
              ),
              if (!_isOwnProfile) ...[
                ListTile(
                  leading: const Icon(Icons.report, color: Colors.white),
                  title: const Text(
                    'Report',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Implement report
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.white),
                  title: const Text(
                    'Block',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Implement block
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Show skeleton with app bar instead of full-page spinner
    if (_isLoading && _userProfile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.black),
                  iconSize: 38,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                centerTitle: true,
                title: Image.asset(
                  'assets/logo-dark.png',
                  height: 18,
                  alignment: Alignment.center,
                ),
              )
            : null,
        body: _buildProfileSkeleton(),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Text('Profile'),
              )
            : null,
        body: const Center(
          child: Text(
            'Profile not found',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      // ✅ Conditionally show AppBar
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.black),
                iconSize: 38,
                onPressed: () => Navigator.of(context).pop(),
              ),
              centerTitle: true,
              title: Image.asset(
                'assets/logo-dark.png',
                height: 18,
                alignment: Alignment.center,
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR Code feature coming soon!'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code, color: Colors.black),
                ),
                IconButton(
                  onPressed: _showMoreOptions,
                  icon: const Icon(Icons.more_horiz, color: Colors.black),
                ),
              ],
            )
          : null,
      // ✅ Wrap entire body in RefreshIndicator
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        color: Colors.orange,
        backgroundColor: const Color(0xFF2A2A2A),
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                automaticallyImplyLeading: false,
                backgroundColor: const Color(0xFF1E1E1E),
                pinned: true,
                expandedHeight: 440,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildProfileHeader(),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(0),
                  child: Container(
                    color: const Color(0xFF1E1E1E),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.orange,
                      indicatorWeight: 3,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: const [
                        Tab(text: 'Posts'),
                        Tab(text: 'Garage'),
                        Tab(text: 'Events'),
                        Tab(text: 'Tags'),
                      ],
                    ),
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              ProfilePostGrid(userId: _userProfile!['id'], isTagged: false),
              GarageTab(userId: _userProfile!['id']),
              _buildPlaceholderTab(
                icon: Icons.event,
                message: 'Events coming soon',
              ),
              ProfilePostGrid(userId: _userProfile!['id'], isTagged: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  image:
                      _userProfile!['cover_image'] != null &&
                          _userProfile!['cover_image'].toString().isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_userProfile!['cover_image']),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: _userProfile!['cover_image'] == null
                      ? const Color(0xFFAE9159)
                      : null,
                ),
              ),
              _userProfile!['cover_image'] != null &&
                      _userProfile!['cover_image'].toString().isNotEmpty
                  ? Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF1E1E1E).withOpacity(0.8),
                              const Color(0xFF1E1E1E),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),

          Transform.translate(
            offset: const Offset(0, -80),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF1E1E1E),
                      width: 4,
                    ),
                  ),
                  child: ProfileAvatar(
                    imageUrl: _userProfile!['profile_image'],
                    radius: 50,
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 30,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${_userProfile!['first_name'] ?? ''} ${_userProfile!['last_name'] ?? ''}'
                                  .trim(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_userProfile!['verified'] == true) ...[
                              SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: Colors.blue,
                              ), // ✅ After name
                            ],
                          ],
                        ),
                        Text(
                          '@${_userProfile!['username']}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Container(width: 1, height: 40, color: Colors.grey),
                      ],
                    ),
                    _buildStat(
                      _getFollowerCount(_userProfile!['followers']).toString(),
                      'Followers',
                    ),
                    _buildStat(
                      _getPostsCount(_userProfile!['posts_count']).toString(),
                      'Posts',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _isOwnProfile
                      ? _buildOwnProfileButtons()
                      : _buildOtherProfileButtons(),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _buildSocialButton(
                        icon:
                            FontAwesomeIcons.instagram, // ✅ Real Instagram icon
                        label: 'Instagram',
                        onTap: () => _launchSocialMedia(
                          'instagram',
                          _userProfile!['instagram'],
                        ),
                        isEnabled:
                            _userProfile!['instagram']?.isNotEmpty ?? false,
                      ),
                      const SizedBox(width: 8),
                      _buildSocialButton(
                        icon: FontAwesomeIcons.facebook, // ✅ Real Facebook icon
                        label: 'Facebook',
                        onTap: () => _launchSocialMedia(
                          'facebook',
                          _userProfile!['facebook'],
                        ),
                        isEnabled:
                            _userProfile!['facebook']?.isNotEmpty ?? false,
                      ),
                      const SizedBox(width: 8),
                      _buildSocialButton(
                        icon: FontAwesomeIcons.tiktok, // ✅ Real TikTok icon
                        label: 'TikTok',
                        onTap: () => _launchSocialMedia(
                          'tiktok',
                          _userProfile!['tiktok'],
                        ),
                        isEnabled: _userProfile!['tiktok']?.isNotEmpty ?? false,
                      ),
                      const SizedBox(width: 8),
                      _buildSocialButton(
                        icon: FontAwesomeIcons.youtube, // ✅ Real YouTube icon
                        label: 'YouTube',
                        onTap: () => _launchSocialMedia(
                          'youtube',
                          _userProfile!['youtube'],
                        ),
                        isEnabled:
                            _userProfile!['youtube']?.isNotEmpty ?? false,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnProfileButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to edit profile
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Edit Profile',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to edit garage
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAE9159),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Edit Garage',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherProfileButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _toggleFollow,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFollowing
                  ? const Color(0xFFAE9159)
                  : const Color(0xFF2e2e2e),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _isFollowing ? 'Following' : 'Follow',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isEnabled,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.3,
          child: Container(
            height: 64, // ✅ Increased from 56
            padding: const EdgeInsets.all(8), // ✅ Reduced padding
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // ✅ Prevents overflow
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void clearCache() {
    _profileCache.clear();
    print('🗑️ [Profile] Cache cleared');
  }

  static void clearUserCache(int userId) {
    _profileCache.remove(userId);
    print('🗑️ [Profile] Cleared cache for user $userId');
  }

  // ✅ Profile skeleton loader
  Widget _buildProfileSkeleton() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Cover skeleton
          // Container(height: 50, color: const Color(0xFF2A2A2A)),
          const SizedBox(height: 90),

          // Avatar skeleton
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 20),

          // Stats skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  // Name skeleton
                  Container(
                    width: 150,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Username skeleton
                  Container(
                    width: 100,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 30),
              _buildStatSkeleton(),
              const SizedBox(width: 40),
              _buildStatSkeleton(),
            ],
          ),
          const SizedBox(height: 20),

          // Button skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Social icons skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              4,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatSkeleton() {
    return Column(
      children: [
        Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
