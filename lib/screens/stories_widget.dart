import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/stories_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

class StoriesRow extends StatefulWidget {
  const StoriesRow({super.key});

  @override
  State<StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends State<StoriesRow> {
  static const Color _gold = Color(0xFFAE9159);

  List<StoryUser> _users = [];
  bool _loading = true;

  // Cached so we don't re-fetch on every render
  int _currentUserId = 0;
  String _currentUsername = '';
  String? _currentProfileImage;

  static final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void didUpdateWidget(covariant StoriesRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-init if widget rebuilds (e.g. account switch)
    _initAndLoad();
  }

  // Fetch current user ONCE, then load stories
  Future<void> _initAndLoad() async {
    final user = await _authService.getUser();
    if (!mounted) return;

    if (user != null) {
      _currentUserId = user['id'] as int;
      _currentUsername = user['username'] as String;
      _currentProfileImage = user['profile_image'] as String?;
    }

    await _loadStories();
  }

  Future<void> _loadStories() async {
    final users = await StoriesService.getFeed();
    if (!mounted) return;

    // Inject own entry at index 0 if API didn't return one
    final hasOwnEntry = users.any((u) => u.userId == _currentUserId);
    if (!hasOwnEntry && _currentUserId != 0) {
      users.insert(
        0,
        StoryUser(
          userId: _currentUserId,
          username: _currentUsername,
          displayName: _currentUsername,
          profileImage: _currentProfileImage,
          stories: [],
          seen: false,
        ),
      );
    }

    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _handleAddStory() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2160,
      maxHeight: 2160,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final token = await _authService.getToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to upload stories')),
      );
      return;
    }

    final success = await StoriesService.uploadStory(
      token: token,
      imageFile: File(picked.path),
    );

    if (!mounted) return;
    if (success) {
      _loadStories();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload story')));
    }
  }

  void _openViewer({
    required List<StoryUser> users,
    required int initialIndex,
  }) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => StoryViewerScreen(
          users: users,
          initialUserIndex: initialIndex,
          currentUserId: _currentUserId,
          onStorySeen: (storyId) => StoriesService.markSeen(storyId: storyId),
          onStoryDeleted: (storyId) =>
              StoriesService.deleteStory(storyId: storyId),
        ),
      ),
    ).then((_) => _loadStories());
  }

  @override
  Widget build(BuildContext context) {
    // Read theme once per build — no extra fetches
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    if (_loading) {
      return SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.primaryColor,
          ),
        ),
      );
    }

    final otherUsers = _users.where((u) => u.userId != _currentUserId).toList();
    final ownEntry = _users.firstWhereOrNull((u) => u.userId == _currentUserId);
    final hasOwnStory = ownEntry != null && ownEntry.stories.isNotEmpty;
    final fullList = ownEntry != null ? [ownEntry, ...otherUsers] : otherUsers;

    return Container(
      height: 100,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: otherUsers.length + 1, // +1 for own bubble
        itemBuilder: (context, index) {
          // ── Index 0: always own bubble ────────────────────────────────
          if (index == 0) {
            return GestureDetector(
              onTap: () {
                if (hasOwnStory) {
                  _openViewer(users: fullList, initialIndex: 0);
                } else {
                  _handleAddStory();
                }
              },
              child: _buildOwnBubble(ownEntry),
            );
          }

          // ── Index 1+: other users ─────────────────────────────────────
          final user = otherUsers[index - 1];
          final viewerIndex = ownEntry != null ? index : index - 1;

          return GestureDetector(
            onTap: () =>
                _openViewer(users: fullList, initialIndex: viewerIndex),
            child: _buildUserBubble(user),
          );
        },
      ),
    );
  }

  Widget _buildOwnBubble(StoryUser? ownEntry) {
    final hasStory = ownEntry != null && ownEntry.stories.isNotEmpty;

    return Container(
      width: 64,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Ring
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasStory
                      ? const LinearGradient(
                          colors: [Color(0xFFAE9159), Color(0xFFD4A96A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: hasStory ? null : Colors.grey.shade300,
                ),
              ),
              // White gap
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              // Avatar — tap opens story or picker
              ClipOval(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: _currentProfileImage != null
                      ? CachedNetworkImage(
                          imageUrl: _currentProfileImage!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _buildFallback(_currentUsername),
                        )
                      : _buildFallback(_currentUsername),
                ),
              ),

              // "+" badge — always visible, always opens picker
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _handleAddStory, // always picker
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Your Story',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserBubble(StoryUser user) {
    return Container(
      width: 64,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: !user.seen
                  ? const LinearGradient(
                      colors: [Color(0xFFAE9159), Color(0xFFD4A96A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: user.seen ? Colors.grey.shade300 : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: user.profileImage != null
                      ? CachedNetworkImage(
                          imageUrl: user.profileImage!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _buildFallback(user.username),
                        )
                      : _buildFallback(user.username),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallback(String name) {
    return Container(
      color: _gold.withOpacity(0.15),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _gold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

class StoryViewerScreen extends StatefulWidget {
  final List<StoryUser> users;
  final int initialUserIndex;
  final int currentUserId;
  final void Function(int storyId)? onStorySeen;
  final void Function(int storyId)? onStoryDeleted;

  const StoryViewerScreen({
    super.key,
    required this.users,
    required this.currentUserId,
    this.initialUserIndex = 0,
    this.onStorySeen,
    this.onStoryDeleted,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  static const Color _gold = Color(0xFFAE9159);
  static const Duration _storyDuration = Duration(seconds: 5);

  late int _userIndex;
  int _storyIndex = 0;

  late AnimationController _progressController;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  Timer? _holdTimer;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _userIndex = widget.initialUserIndex;

    _progressController =
        AnimationController(vsync: this, duration: _storyDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _nextStory();
          });

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _slideController.forward();
    _startProgress();
    _markCurrentSeen();

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _progressController.dispose();
    _slideController.dispose();
    _holdTimer?.cancel();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  void _startProgress() {
    _progressController.reset();
    _progressController.forward();
  }

  void _markCurrentSeen() {
    final story = widget.users[_userIndex].stories[_storyIndex];
    if (!story.isSeen && !_isOwnStory) {
      widget.onStorySeen?.call(story.storyId);
    }
  }

  void _nextStory() {
    final user = widget.users[_userIndex];
    if (_storyIndex < user.stories.length - 1) {
      setState(() => _storyIndex++);
      _startProgress();
      _markCurrentSeen();
    } else {
      _nextUser();
    }
  }

  void _prevStory() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startProgress();
    } else {
      _prevUser();
    }
  }

  void _nextUser() {
    if (_userIndex < widget.users.length - 1) {
      setState(() {
        widget.users[_userIndex].seen = true;
        _userIndex++;
        _storyIndex = 0;
      });
      _startProgress();
      _markCurrentSeen();
    } else {
      _close();
    }
  }

  void _prevUser() {
    if (_userIndex > 0) {
      setState(() {
        _userIndex--;
        _storyIndex = 0;
      });
      _startProgress();
    }
  }

  void _close() {
    widget.users[_userIndex].seen = true;
    _slideController.reverse().then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _onLongPressStart(_) {
    _holdTimer = Timer(const Duration(milliseconds: 100), () {
      setState(() => _isPaused = true);
      _progressController.stop();
    });
  }

  void _onLongPressEnd(_) {
    _holdTimer?.cancel();
    if (_isPaused) {
      setState(() => _isPaused = false);
      _progressController.forward();
    }
  }

  Future<void> _confirmDeleteStory() async {
    _progressController.stop();
    setState(() => _isPaused = true);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete story?'),
        content: const Text('This story will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      final story = widget.users[_userIndex].stories[_storyIndex];
      widget.onStoryDeleted?.call(story.storyId);

      // Remove from local list
      setState(() {
        widget.users[_userIndex].stories.removeAt(_storyIndex);
      });

      if (widget.users[_userIndex].stories.isEmpty) {
        if (_userIndex < widget.users.length - 1) {
          _nextUser();
        } else {
          _close();
        }
      } else {
        setState(() {
          // clamp so index never exceeds new list length
          _storyIndex = _storyIndex.clamp(
            0,
            widget.users[_userIndex].stories.length - 1,
          );
        });
        _startProgress();
      }
    } else {
      // Resume on cancel
      setState(() => _isPaused = false);
      _progressController.forward();
    }
  }

  bool get _isOwnStory =>
      widget.users[_userIndex].userId == widget.currentUserId;

  @override
  Widget build(BuildContext context) {
    final user = widget.users[_userIndex];

    // Guard: if stories list is empty, don't render — close is already in flight
    if (user.stories.isEmpty) return const SizedBox.shrink();

    final story = user.stories[_storyIndex];
    final size = MediaQuery.of(context).size;

    return SlideTransition(
      position: _slideAnimation,
      child: SafeArea(
        // backgroundColor: Colors.black,
        bottom: false,
        child: GestureDetector(
          onLongPressStart: _onLongPressStart,
          onLongPressEnd: _onLongPressEnd,
          onTapUp: (details) {
            final x = details.globalPosition.dx;
            if (x < size.width / 2) {
              _prevStory();
            } else {
              _nextStory();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Story image with blurred background ───────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: SizedBox.expand(
                  key: ValueKey('${_userIndex}_$_storyIndex'),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Blurred background
                      CachedNetworkImage(
                        imageUrl: story.blurredImageUrl ?? story.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey.shade900),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey.shade900),
                      ),
                      // Dark overlay
                      Container(color: Colors.black.withOpacity(0.3)),
                      // Contained foreground
                      CachedNetworkImage(
                        imageUrl: story.imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Gradient overlays ─────────────────────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: const Alignment(0, 0.4),
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: const Alignment(0, 0.7),
                      colors: [
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Progress bars ─────────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 12,
                right: 12,
                child: AnimatedOpacity(
                  opacity: _isPaused ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    children: List.generate(user.stories.length, (i) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _ProgressBar(
                            isCompleted: i < _storyIndex,
                            isActive: i == _storyIndex,
                            controller: i == _storyIndex
                                ? _progressController
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // ── Header ────────────────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 12,
                right: 12,
                child: AnimatedOpacity(
                  opacity: _isPaused ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _gold, width: 2),
                        ),
                        child: GestureDetector(
                          onTap: () => {
                            Navigator.pushNamed(
                              context,
                              '/view-profile',
                              arguments: {
                                'userId': user.userId,
                                'username': user.username,
                              },
                            ),
                          },
                          child: ClipOval(
                            child: user.profileImage != null
                                ? CachedNetworkImage(
                                    imageUrl: user.profileImage!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: _gold.withOpacity(0.3),
                                    child: Center(
                                      child: Text(
                                        user.username[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => {
                            Navigator.pushNamed(
                              context,
                              '/view-profile',
                              arguments: {
                                'userId': user.userId,
                                'username': user.username,
                              },
                            ),
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                story.timeAgo,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Pause indicator
                      if (_isPaused)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.pause_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),

                      const SizedBox(width: 8),

                      // Delete button — own stories only
                      if (_isOwnStory) ...[
                        GestureDetector(
                          onTap: _confirmDeleteStory,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Add inside the Stack, after the gradient overlays
                      // Only visible for own stories
                      if (_isOwnStory)
                        Positioned(
                          bottom: MediaQuery.of(context).padding.bottom + 16,
                          left: 16,
                          right: 16,
                          child: AnimatedOpacity(
                            opacity: _isPaused ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.remove_red_eye_outlined,
                                        color: Colors.white,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${story.seenCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Close
                      GestureDetector(
                        onTap: _close,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Left / right tap zones ────────────────────────────────────
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: size.width * 0.35,
                child: const SizedBox.expand(),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: size.width * 0.65,
                child: const SizedBox.expand(),
              ),

              // Reply bar removed
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final bool isCompleted;
  final bool isActive;
  final AnimationController? controller;

  const _ProgressBar({
    required this.isCompleted,
    required this.isActive,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: isCompleted
            ? const LinearProgressIndicator(
                value: 1,
                backgroundColor: Colors.white30,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              )
            : isActive && controller != null
            ? AnimatedBuilder(
                animation: controller!,
                builder: (_, __) => LinearProgressIndicator(
                  value: controller!.value,
                  backgroundColor: Colors.white30,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const LinearProgressIndicator(
                value: 0,
                backgroundColor: Colors.white30,
                valueColor: AlwaysStoppedAnimation(Colors.transparent),
              ),
      ),
    );
  }
}
