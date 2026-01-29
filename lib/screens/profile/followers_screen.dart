import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/widgets/profile/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/user_service.dart';

class FollowersScreen extends StatefulWidget {
  final int userId;

  const FollowersScreen({super.key, required this.userId});

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final UserService _userService = UserService();

  List<Map<String, dynamic>> _allFollowers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];

  bool _loading = true;
  bool _loadingMore = false;
  int _currentPage = 1;
  int _totalPages = 999; // High number, will update when no more data
  bool _isOwnProfile = false;

  @override
  void initState() {
    super.initState();
    _checkIfOwnProfile();
    _loadFollowers();
    _searchController.addListener(_filterFollowers);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreFollowers();
    }
  }

  Future<void> _loadFollowers() async {
    setState(() => _loading = true);

    final followers = await _userService.getFollowers(widget.userId, 1);

    if (!mounted) return;

    setState(() {
      _allFollowers = followers;
      _filteredFollowers = List.from(followers);
      _currentPage = 1;
      _loading = false;
    });
  }

  Future<void> _loadMoreFollowers() async {
    if (_loadingMore || _currentPage >= _totalPages) return;

    setState(() => _loadingMore = true);

    final newFollowers = await _userService.getFollowers(
      widget.userId,
      _currentPage + 1,
    );

    if (!mounted) return;

    if (newFollowers.isEmpty) {
      // No more followers to load
      setState(() {
        _totalPages = _currentPage;
        _loadingMore = false;
      });
      return;
    }

    setState(() {
      _allFollowers.addAll(newFollowers);
      _currentPage++;
      _loadingMore = false;
    });

    _filterFollowers(); // Reapply filter if search is active
  }

  void _filterFollowers() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredFollowers = List.from(_allFollowers);
      } else {
        _filteredFollowers = _allFollowers.where((follower) {
          final username = follower['user_login'].toString().toLowerCase();
          return username.contains(query);
        }).toList();
      }
    });
  }

  void _checkIfOwnProfile() {
    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser != null) {
      _isOwnProfile = currentUser.id == widget.userId;
    }
  }

  Future<void> _handleRemove(
    Map<String, dynamic> follower,
    ThemeProvider theme,
  ) async {
    final success = await _userService.removeFollower(follower['ID']);

    if (success && mounted) {
      setState(() {
        _allFollowers.remove(follower);
        _filteredFollowers.remove(follower);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed @${follower['user_login']} from followers'),
          backgroundColor: theme.primaryColor,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove @${follower['user_login']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: theme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Followers',
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: _searchController,
              builder: (context, child) {
                return TextField(
                  controller: _searchController,
                  style: TextStyle(color: theme.textColor),
                  decoration: InputDecoration(
                    hintText: 'Search followers...',
                    hintStyle: TextStyle(color: theme.subtextColor),
                    prefixIcon: Icon(Icons.search, color: theme.subtextColor),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: theme.subtextColor),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                );
              },
            ),
          ),

          // Followers list
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  )
                : _filteredFollowers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_search,
                          size: 64,
                          color: theme.subtextColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isNotEmpty
                              ? 'No followers found'
                              : 'No followers yet',
                          style: TextStyle(
                            color: theme.subtextColor,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount:
                        _filteredFollowers.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _filteredFollowers.length) {
                        // Show loading indicator at bottom
                        return Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: theme.primaryColor,
                            ),
                          ),
                        );
                      }

                      final follower = _filteredFollowers[index];
                      return _buildFollowerTile(follower, theme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowerTile(
    Map<String, dynamic> follower,
    ThemeProvider theme,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: ProfileAvatar(imageUrl: follower['profile_image'], radius: 24),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            '${follower['user_login']}',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (follower['verified'] == true) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified, size: 14, color: theme.primaryColor),
          ],
        ],
      ),
      trailing: !_isOwnProfile
          ? null
          : ElevatedButton(
              onPressed: () => _handleRemove(follower, theme),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Remove',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
      onTap: () {
        Navigator.pushNamed(
          context,
          '/view-profile',
          arguments: {
            'userId': follower['ID'],
            'username': follower['user_login'],
          },
        );
      },
    );
  }
}
