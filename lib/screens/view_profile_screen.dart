import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/edit_profile_settings_screen.dart';
import 'package:drivelife/screens/followers_screen.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:drivelife/widgets/post_detail_screen.dart';
import 'package:drivelife/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_service.dart';
import '../providers/user_provider.dart';
import '../models/post_model.dart';
import '../services/posts_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../utils/navigation_helper.dart';
import '../api/garage_api.dart';
import 'package:drivelife/utils/profile_cache.dart';

class ViewProfileScreen extends StatefulWidget {
  final int? userId;
  final String username;
  final bool showAppBar;

  const ViewProfileScreen({
    super.key,
    required this.userId,
    required this.username,
    this.showAppBar = true,
  });

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserService _userService = UserService();
  final PostsService _postsService = PostsService();
  final ScrollController _scrollController = ScrollController();

  ImageProvider? _coverProvider;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isOwnProfile = false;

  // Posts data
  List<Post> _posts = [];
  List<Post> _taggedPosts = [];
  int _postsPage = 1;
  int _taggedPage = 1;
  bool _loadingPosts = false;
  bool _loadingTagged = false;
  bool _hasMorePosts = true;
  bool _hasMoreTagged = true;

  // Garage data
  List<dynamic> _currentVehicles = [];
  List<dynamic> _pastVehicles = [];
  List<dynamic> _dreamVehicles = [];
  bool _loadingGarage = false;
  bool _garageLoaded = false; // ✅ Track if garage has been loaded

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _checkIfOwnProfile();
    _loadUserProfileOptimized();
    // ✅ Removed _loadTabContent() - will be called after profile loads
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();

    // ✅ Free memory
    _posts.clear();
    _taggedPosts.clear();
    _currentVehicles.clear();
    _pastVehicles.clear();
    _dreamVehicles.clear();

    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
      _loadTabContent();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMoreContent();
    }
  }

  void _loadTabContent() {
    final index = _tabController.index;
    if (index == 0 && _posts.isEmpty) {
      _loadPosts();
    } else if (index == 1 && !_garageLoaded) {
      // ✅ Only load garage if not loaded before
      _loadGarage();
    } else if (index == 3 && _taggedPosts.isEmpty) {
      _loadTaggedPosts();
    }
  }

  void _loadMoreContent() {
    final index = _tabController.index;
    if (index == 0) {
      _loadPosts();
    } else if (index == 3) {
      _loadTaggedPosts();
    }
  }

  Future<void> _loadPosts() async {
    if (_loadingPosts || !_hasMorePosts || _userProfile == null) return;

    setState(() => _loadingPosts = true);

    try {
      final response = await _postsService.getUserPosts(
        userId: _userProfile!['id'],
        page: _postsPage,
        limit: 9,
        tagged: false,
      );

      if (!mounted) return;

      if (response != null && response.data.isNotEmpty) {
        setState(() {
          _posts.addAll(response.data);
          _postsPage++;
          _hasMorePosts = _postsPage <= response.totalPages;
          _loadingPosts = false;
        });
      } else {
        setState(() {
          _hasMorePosts = false;
          _loadingPosts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _loadTaggedPosts() async {
    if (_loadingTagged || !_hasMoreTagged || _userProfile == null) return;

    setState(() => _loadingTagged = true);

    try {
      final response = await _postsService.getUserPosts(
        userId: _userProfile!['id'],
        page: _taggedPage,
        limit: 9,
        tagged: true,
      );

      if (!mounted) return;

      if (response != null && response.data.isNotEmpty) {
        setState(() {
          _taggedPosts.addAll(response.data);
          _taggedPage++;
          _hasMoreTagged = _taggedPage <= response.totalPages;
          _loadingTagged = false;
        });
      } else {
        setState(() {
          _hasMoreTagged = false;
          _loadingTagged = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTagged = false);
    }
  }

  Future<void> _loadGarage() async {
    if (_loadingGarage || _userProfile == null) return;

    setState(() => _loadingGarage = true);

    final garage = await GarageAPI.getUserGarage(_userProfile!['id']);

    if (!mounted) return;

    if (garage != null) {
      final current = <dynamic>[];
      final past = <dynamic>[];
      final dream = <dynamic>[];

      for (final vehicle in garage) {
        if (vehicle['primary_car'] == '2') {
          dream.add(vehicle);
        } else if (vehicle['owned_until'] == '' ||
            vehicle['owned_until']?.toLowerCase() == 'present') {
          current.add(vehicle);
        } else {
          past.add(vehicle);
        }
      }

      setState(() {
        _currentVehicles = current;
        _pastVehicles = past;
        _dreamVehicles = dream;
        _loadingGarage = false;
        _garageLoaded = true; // ✅ Mark garage as loaded
      });
    } else {
      setState(() {
        _loadingGarage = false;
        _garageLoaded = true; // ✅ Mark as loaded even if empty
      });
    }
  }

  void _checkIfOwnProfile() {
    final currentUser = Provider.of<UserProvider>(context, listen: false).user;

    if (currentUser != null) {
      _isOwnProfile =
          currentUser['id'] == widget.userId ||
          currentUser['username'] == widget.username;
    }
  }

  Future<void> _preloadCoverImage(String? url) async {
    if (!mounted) return;

    if (url == null || url.trim().isEmpty) {
      _coverProvider = null;
      return;
    }

    final provider = NetworkImage(url);

    // warm up the image cache
    try {
      await precacheImage(provider, context);
      if (!mounted) return;
      _coverProvider = provider;
    } catch (_) {
      // if it fails, don't block UI
      _coverProvider = provider; // you can also set null if you prefer fallback
    }
  }

  Future<void> _loadUserProfileOptimized() async {
    if (!mounted) return;

    // ✅ Own profile → Use UserProvider (no cache)
    if (_isOwnProfile) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      // print all user data for debugging
      // loop through user map and print key-value pairs
      user!.forEach((key, value) {
        print('UserProvider data: $key => $value');
      });

      if (user != null) {
        setState(() {
          _userProfile = Map<String, dynamic>.from(user);
          _isLoading = false;
        });
        _loadTabContent();
        return;
      }
    }

    // ✅ Other profiles → Check smart cache
    if (widget.userId != null) {
      final cached = ProfileCache.get(widget.userId!);
      if (cached != null) {
        setState(() {
          _userProfile = cached;
          _isLoading = false;
        });

        if (_userProfile!['id'] != null) {
          _checkFollowStatus(_userProfile!['id']);
        }

        _loadTabContent();
        return;
      }
    }

    // ✅ No cache → Fetch from API
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

        // Cache other users' profiles only
        if (!_isOwnProfile && widget.userId != null) {
          ProfileCache.put(widget.userId!, profile);
        }

        if (!_isOwnProfile && profile['id'] != null) {
          _checkFollowStatus(profile['id']);
        }

        _loadTabContent();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshProfile() async {
    print('🔄 Refreshing profile...');

    // Clear cache
    if (widget.userId != null) {
      ProfileCache.remove(widget.userId!);
    }

    setState(() {
      _posts.clear();
      _taggedPosts.clear();
      _currentVehicles.clear();
      _pastVehicles.clear();
      _dreamVehicles.clear();
      _postsPage = 1;
      _taggedPage = 1;
      _hasMorePosts = true;
      _hasMoreTagged = true;
      _garageLoaded = false;
    });

    await _loadUserProfileOptimized();
    print('✅ Profile refreshed');
  }

  Future<void> _checkFollowStatus(int userId) async {
    final sessionUserFollowing =
        Provider.of<UserProvider>(context, listen: false).user?['following']
            as List<dynamic>?;

    if (sessionUserFollowing == null) return;

    // Now checks UserProvider's following list directly
    // Handles both int and string IDs
    final following = sessionUserFollowing.any((id) {
      if (id is int) return id == userId;
      if (id is String) return int.tryParse(id) == userId;
      return false;
    });

    if (!mounted) return;
    setState(() => _isFollowing = following);
  }

  Future<void> _toggleFollow() async {
    if (_userProfile == null || !mounted) return;

    final userId = _userProfile!['id'];
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUserId = userProvider.user?['id'];

    if (userId == null || currentUserId == null) return;

    bool success = await _userService.followUser(userId, currentUserId);

    if (!mounted) return;

    if (success) {
      setState(() {
        _isFollowing = !_isFollowing;

        // Update follower count and list
        final followers = _userProfile!['followers'] as List<dynamic>? ?? [];
        if (_isFollowing) {
          // Add current user to followers list
          _userProfile!['followers'] = [...followers, currentUserId];
        } else {
          // Remove current user from followers list
          _userProfile!['followers'] = followers.where((id) {
            if (id is int) return id != currentUserId;
            if (id is String) return int.tryParse(id) != currentUserId;
            return true;
          }).toList();
        }

        // Update cache
        if (widget.userId != null) {
          ProfileCache.put(widget.userId!, _userProfile!);
        }
      });

      // Update UserProvider's following list
      final currentUser = Map<String, dynamic>.from(userProvider.user ?? {});
      final following = List<dynamic>.from(currentUser['following'] ?? []);

      if (_isFollowing) {
        // Add to following list if not already there
        if (!following.any((id) {
          if (id is int) return id == userId;
          if (id is String) return int.tryParse(id) == userId;
          return false;
        })) {
          following.add(userId);
        }
      } else {
        // Remove from following list
        following.removeWhere((id) {
          if (id is int) return id == userId;
          if (id is String) return int.tryParse(id) == userId;
          return false;
        });
      }

      currentUser['following'] = following;
      userProvider.setUser(currentUser);

      print('✅ [ViewProfileScreen] Follow status updated:');
      print('   Following: $_isFollowing');
      print(
        '   Profile followers: ${(_userProfile!['followers'] as List).length}',
      );
      print('   Current user following: ${following.length}');
    }
  }

  int _parseFollowerCount(dynamic followers) {
    if (followers == null) return 0;
    if (followers is int) return followers;
    if (followers is List) return followers.length;
    if (followers is String) return int.tryParse(followers) ?? 0;
    return 0;
  }

  String _getFollowerCount({dynamic followers, bool formattedString = false}) {
    const suffixes = ['', 'K', 'M', 'B'];
    const int divisor = 1000;
    final intCount = _parseFollowerCount(followers);

    if (formattedString) {
      int index = 0;
      double count = intCount.toDouble();

      while (count >= divisor && index < suffixes.length - 1) {
        count /= divisor;
        index++;
      }

      return '${count.toStringAsFixed(count.truncateToDouble() == count ? 0 : 1)}${suffixes[index]}';
    } else {
      return intCount.toString();
    }
  }

  int _getPostsCount(dynamic postsCount) {
    if (postsCount == null) return 0;
    if (postsCount is int) return postsCount;
    if (postsCount is String) return int.tryParse(postsCount) ?? 0;
    return 0;
  }

  Future<void> _launchSocialMedia(String platform, String? username) async {
    if (username == null || username.isEmpty) return;

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
      final uri = Uri.parse(url);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        print('Error: $e');
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
                onTap: () => Navigator.pop(context),
              ),
              if (!_isOwnProfile) ...[
                ListTile(
                  leading: const Icon(Icons.report, color: Colors.white),
                  title: const Text(
                    'Report',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.white),
                  title: const Text(
                    'Block',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context),
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
    final theme = Provider.of<ThemeProvider>(context);

    if (_isLoading && _userProfile == null) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: theme.backgroundColor,
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
        body: _buildProfileSkeleton(theme),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        body: const Center(child: Text('Profile not found')),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: theme.backgroundColor,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.chevron_left, color: theme.textColor),
                iconSize: 38,
                onPressed: () => Navigator.of(context).pop(),
              ),
              centerTitle: true,
              title: Image.asset('assets/logo-dark.png', height: 18),
              actions: [
                // In AppBar actions
                IconButton(
                  onPressed: () async {
                    final result = await QrScannerService.showScanner(context);
                    if (result != null && mounted) {
                      QrScannerService.handleScanResult(
                        context,
                        result,
                        onSuccess: (data) {
                          // Navigate based on entity type
                          if (data['entity_type'] == 'profile') {
                            Navigator.pushNamed(
                              context,
                              '/view-profile',
                              arguments: {'userId': data['entity_id']},
                            );
                          } else if (data['entity_type'] == 'vehicle') {
                            Navigator.pushNamed(
                              context,
                              '/vehicle-detail',
                              arguments: {
                                'garageId': data['entity_id'].toString(),
                              },
                            );
                          }
                        },
                      );
                    }
                  },
                  icon: Icon(Icons.qr_code),
                ),
                IconButton(
                  onPressed: _showMoreOptions,
                  icon: Icon(Icons.more_horiz, color: theme.textColor),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        color: theme.primaryColor,
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // ✅ Add swipe to change tabs
            if (details.primaryVelocity! > 0) {
              // Swipe right - go to previous tab
              if (_tabController.index > 0) {
                _tabController.animateTo(_tabController.index - 1);
              }
            } else if (details.primaryVelocity! < 0) {
              // Swipe left - go to next tab
              if (_tabController.index < _tabController.length - 1) {
                _tabController.animateTo(_tabController.index + 1);
              }
            }
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Header
              SliverToBoxAdapter(child: _buildProfileHeader(theme)),

              // Tabs
              SliverToBoxAdapter(
                child: Container(
                  color: theme.backgroundColor,
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorColor: theme.primaryColor,
                    indicatorWeight: 3,
                    labelColor: theme.textColor,
                    unselectedLabelColor: theme.subtextColor,
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

              // Active tab content
              _buildActiveTabContent(theme),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(ThemeProvider theme) {
    switch (_tabController.index) {
      case 0:
        return _buildPostsGrid(_posts, theme);
      case 1:
        return _buildGarageContent(theme);
      case 2:
        return _buildPlaceholder(Icons.event, 'Events coming soon', theme);
      case 3:
        return _buildPostsGrid(_taggedPosts, theme);
      default:
        return _buildPostsGrid(_posts, theme);
    }
  }

  Widget _buildPostsGrid(List<Post> posts, ThemeProvider theme) {
    // ✅ Show skeleton loading when initially loading posts
    if (posts.isEmpty && (_loadingPosts || _loadingTagged || _isLoading)) {
      return SliverPadding(
        padding: const EdgeInsets.all(2),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 1,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildSkeletonTile(theme),
            childCount: 9, // Show 9 skeleton tiles
          ),
        ),
      );
    }

    if (posts.isEmpty && !_loadingPosts && !_loadingTagged) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: theme.subtextColor,
              ),
              const SizedBox(height: 16),
              Text('No posts yet', style: TextStyle(color: theme.subtextColor)),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(2),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index < posts.length) {
              return _buildPostTile(posts[index], theme);
            }
            // ✅ Show loading skeleton at bottom when loading more
            return _buildSkeletonTile(theme);
          },
          childCount:
              posts.length + ((_loadingPosts || _loadingTagged) ? 3 : 0),
        ),
      ),
    );
  }

  Widget _buildSkeletonTile(ThemeProvider theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            decoration: BoxDecoration(
              color: theme.isDarkMode
                  ? Colors.grey.shade800
                  : Colors.grey.shade300,
            ),
          ),
        );
      },
      onEnd: () {
        // Loop animation if still mounted
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) setState(() {});
          });
        }
      },
    );
  }

  Widget _buildPostTile(Post post, ThemeProvider theme) {
    return GestureDetector(
      onTap: () => NavigationHelper.navigateTo(
        context,
        PostDetailScreen(postId: post.id),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          image: post.thumbnailUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(post.thumbnailUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: post.thumbnailUrl.isEmpty
            ? Icon(
                Icons.image_not_supported,
                color: theme.subtextColor,
                size: 32,
              )
            : Stack(
                children: [
                  if (post.media.length > 1 || post.hasVideo)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          post.hasVideo ? Icons.play_arrow : Icons.collections,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildGarageContent(ThemeProvider theme) {
    if (_loadingGarage) {
      return SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _buildGarageSection('Current Vehicles', _currentVehicles, theme),
          const SizedBox(height: 24),
          _buildGarageSection('Past Vehicles', _pastVehicles, theme),
          const SizedBox(height: 24),
          _buildGarageSection('Dream Vehicles', _dreamVehicles, theme),
        ]),
      ),
    );
  }

  Widget _buildGarageSection(
    String title,
    List<dynamic> vehicles,
    ThemeProvider theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.textColor,
          ),
        ),
        const SizedBox(height: 12),
        if (vehicles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'No ${title.toLowerCase()}',
              style: TextStyle(color: theme.subtextColor),
            ),
          )
        else
          ...vehicles.map(
            (vehicle) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 60,
                    height: 60,
                    color: theme.dividerColor,
                    child: vehicle['cover_photo'] != null
                        ? Image.network(
                            vehicle['cover_photo'],
                            fit: BoxFit.cover,
                          )
                        : Icon(Icons.directions_car, color: theme.subtextColor),
                  ),
                ),
                title: Text(
                  '${vehicle['make']} ${vehicle['model']}',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: theme.subtextColor),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/vehicle-detail',
                    arguments: {'garageId': vehicle['id'].toString()},
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder(IconData icon, String message, ThemeProvider theme) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.subtextColor),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(color: theme.subtextColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeProvider theme) {
    return Container(
      color: theme.cardColor,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Cover image
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
                      ? theme.primaryColor.withOpacity(0.1)
                      : null,
                ),
              ),

              // ✅ White overlay gradient
              if (_userProfile!['cover_image'] != null &&
                  _userProfile!['cover_image'].toString().isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          theme.cardColor.withOpacity(0.6),
                          theme.cardColor,
                        ],
                      ),
                    ),
                  ),
                ),

              // ✅ Floating avatar (only this element overlaps)
              Positioned(
                bottom: -50, // Half of avatar size overlaps
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.backgroundColor, width: 4),
                  ),
                  child: ProfileAvatar(
                    imageUrl: _userProfile!['profile_image'],
                    radius: 60,
                  ),
                ),
              ),
            ],
          ),

          // ✅ Normal flow content (no transform translate!)
          const SizedBox(height: 60), // Space for overlapping avatar
          // Name and username
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text(
                        '${_userProfile!['first_name'] ?? ''} ${_userProfile!['last_name'] ?? ''}'
                            .trim(),
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_userProfile!['verified'] == true) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          size: 16,
                          color: theme.primaryColor,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '@${_userProfile!['username']}',
                    style: TextStyle(
                      color: theme.subtextColor,
                      fontSize: _userProfile!['username'].length > 15 ? 12 : 14,
                    ),
                  ),
                ],
              ),

              // ✅ Gap between username and stats
              const SizedBox(width: 20),
              Container(width: 1, height: 40, color: theme.dividerColor),
              const SizedBox(width: 20),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 30,
                children: [
                  GestureDetector(
                    onTap: () => NavigationHelper.navigateTo(
                      context,
                      FollowersScreen(userId: _userProfile!['id']),
                    ),
                    child: _buildStat(
                      _getFollowerCount(
                        followers: _userProfile!['followers'],
                        formattedString: true,
                      ),
                      'Followers',
                      theme,
                    ),
                  ),
                  Container(width: 1, height: 40, color: theme.dividerColor),
                  _buildStat(
                    _getPostsCount(_userProfile!['posts_count']).toString(),
                    'Posts',
                    theme,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _isOwnProfile
                ? _buildOwnProfileButtons(theme)
                : _buildOtherProfileButtons(theme),
          ),
          const SizedBox(height: 12),

          // Social buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildSocialButton(
                  icon: FontAwesomeIcons.instagram,
                  label: 'Instagram',
                  onTap: () => _launchSocialMedia(
                    'instagram',
                    _userProfile!['profile_links']?['instagram'],
                  ),
                  isEnabled:
                      _userProfile!['profile_links']?['instagram']
                          ?.isNotEmpty ??
                      false,
                  theme: theme,
                ),
                const SizedBox(width: 8),
                _buildSocialButton(
                  icon: FontAwesomeIcons.facebook,
                  label: 'Facebook',
                  onTap: () => _launchSocialMedia(
                    'facebook',
                    _userProfile!['profile_links']?['facebook'],
                  ),
                  isEnabled:
                      _userProfile!['profile_links']?['facebook']?.isNotEmpty ??
                      false,
                  theme: theme,
                ),
                const SizedBox(width: 8),
                _buildSocialButton(
                  icon: FontAwesomeIcons.tiktok,
                  label: 'TikTok',
                  onTap: () => _launchSocialMedia(
                    'tiktok',
                    _userProfile!['profile_links']?['tiktok'],
                  ),
                  isEnabled:
                      _userProfile!['profile_links']?['tiktok']?.isNotEmpty ??
                      false,
                  theme: theme,
                ),
                const SizedBox(width: 8),
                _buildSocialButton(
                  icon: FontAwesomeIcons.youtube,
                  label: 'YouTube',
                  onTap: () => _launchSocialMedia(
                    'youtube',
                    _userProfile!['profile_links']?['youtube'],
                  ),
                  isEnabled:
                      _userProfile!['profile_links']?['youtube']?.isNotEmpty ??
                      false,
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOwnProfileButtons(ThemeProvider theme) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () async {
              final result = await NavigationHelper.navigateTo(
                context,
                const EditProfileSettingsScreen(),
              );

              // Refresh profile if details were updated
              if (result == true && mounted) {
                _refreshProfile();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAE9159),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
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
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
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

  Widget _buildOtherProfileButtons(ThemeProvider theme) {
    return SizedBox(
      width: double.infinity, // ✅ Full width
      child: ElevatedButton(
        onPressed: _toggleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isFollowing
              ? theme.primaryColor
              : theme.secondaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          _isFollowing ? 'Following' : 'Follow',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, ThemeProvider theme) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: theme.subtextColor, fontSize: 13)),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isEnabled,
    required ThemeProvider theme,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.3,
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.secondaryCardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(icon, color: theme.textColorSecondary, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: theme.textColorSecondary,
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

  Widget _buildProfileSkeleton(ThemeProvider theme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 90),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: theme.isDarkMode
                  ? Colors.grey.shade800
                  : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  Container(
                    width: 150,
                    height: 20,
                    decoration: BoxDecoration(
                      color: theme.isDarkMode
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 100,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.isDarkMode
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 30),
              _buildStatSkeleton(theme),
              const SizedBox(width: 40),
              _buildStatSkeleton(theme),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: theme.isDarkMode
                    ? Colors.grey.shade800
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 20),
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
                    color: theme.isDarkMode
                        ? Colors.grey.shade800
                        : Colors.grey.shade300,
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

  Widget _buildStatSkeleton(ThemeProvider theme) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: theme.isDarkMode
                ? Colors.grey.shade800
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 14,
          decoration: BoxDecoration(
            color: theme.isDarkMode
                ? Colors.grey.shade800
                : Colors.grey.shade300,
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
