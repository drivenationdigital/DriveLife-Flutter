import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class StoriesRow extends StatelessWidget {
  const StoriesRow({super.key});

  static const Color _gold = Color(0xFFAE9159);

  // Dummy data
  // In StoriesRow, replace the dummy list with StoryUser objects:
static final _storyUsers = [
  StoryUser(
    username: 'your_story',
    profileImage: null,
    seen: false,
    stories: [
      StoryItem(
        imageUrl: 'https://picsum.photos/seed/s1/600/1000',
        username: 'your_story',
        timeAgo: 'Just now',
      ),
    ],
  ),
  StoryUser(
    username: 'm88xrk',
    profileImage: 'https://i.pravatar.cc/150?img=1',
    seen: false,
    stories: [
      StoryItem(imageUrl: 'https://picsum.photos/seed/s2/600/1000', username: 'm88xrk', timeAgo: '3m ago'),
      StoryItem(imageUrl: 'https://picsum.photos/seed/s3/600/1000', username: 'm88xrk', timeAgo: '3m ago'),
    ],
  ),
  StoryUser(
    username: 'drivelife_uk',
    profileImage: 'https://i.pravatar.cc/150?img=3',
    seen: true,
    stories: [
      StoryItem(imageUrl: 'https://picsum.photos/seed/s4/600/1000', username: 'drivelife_uk', timeAgo: '1h ago'),
    ],
  )
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _storyUsers.length,
        itemBuilder: (context, index) {
          final storyUser = _storyUsers[index];
          final isOwn = storyUser.username == 'your_story';
          final seen = storyUser.seen;
          final image = storyUser.profileImage;
          final name = storyUser.username;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  opaque: false,
                  barrierColor: Colors.black,
                  transitionDuration:
                      Duration.zero, // slide handles its own animation
                  pageBuilder: (_, __, ___) => StoryViewerScreen(
                    users: _storyUsers,
                    initialUserIndex: index,
                  ),
                ),
              );
            },
            child: Container(
              width: 64,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                children: [
                  // ── Avatar with ring ───────────────────
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Gradient ring (unseen) or grey (seen)
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: seen || isOwn
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFAE9159),
                                    Color(0xFFD4A96A),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          color: seen ? Colors.grey.shade300 : null,
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
                      // Avatar
                      ClipOval(
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: image != null
                              ? CachedNetworkImage(
                                  imageUrl: image,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      _buildFallback(name),
                                )
                              : _buildFallback(name),
                        ),
                      ),
                      // "+" button for own story
                      if (isOwn)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: _gold,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // ── Username ───────────────────────────
                  Text(
                    isOwn ? 'Your Story' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isOwn ? FontWeight.w600 : FontWeight.w400,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFallback(String name) {
    return Container(
      color: const Color(0xFFAE9159).withOpacity(0.15),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFFAE9159),
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

// ── Data model ───────────────────────────────────────────────
class StoryItem {
  final String imageUrl;
  final String username;
  final String? profileImage;
  final String timeAgo;

  const StoryItem({
    required this.imageUrl,
    required this.username,
    this.profileImage,
    this.timeAgo = '2m ago',
  });
}

class StoryUser {
  final String username;
  final String? profileImage;
  final List<StoryItem> stories;
  bool seen;

  StoryUser({
    required this.username,
    required this.stories,
    this.profileImage,
    this.seen = false,
  });
}

// ── Viewer ───────────────────────────────────────────────────
class StoryViewerScreen extends StatefulWidget {
  final List<StoryUser> users;
  final int initialUserIndex;

  const StoryViewerScreen({
    super.key,
    required this.users,
    this.initialUserIndex = 0,
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

    // Progress bar controller
    _progressController = AnimationController(
      vsync: this,
      duration: _storyDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _nextStory();
      });

    // Slide-in animation
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _slideController.forward();
    _startProgress();

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

  void _nextStory() {
    final user = widget.users[_userIndex];
    if (_storyIndex < user.stories.length - 1) {
      setState(() => _storyIndex++);
      _startProgress();
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

  @override
  Widget build(BuildContext context) {
    final user    = widget.users[_userIndex];
    final story   = user.stories[_storyIndex];
    final size    = MediaQuery.of(context).size;

    return SlideTransition(
      position: _slideAnimation,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
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
              // ── Story image ───────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: CachedNetworkImage(
                  key: ValueKey('${_userIndex}_$_storyIndex'),
                  imageUrl: story.imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (_, __) => Container(color: Colors.grey.shade900),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.shade900,
                    child: const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                  ),
                ),
              ),

              // ── Gradient overlays ─────────────────────────
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
                      end: const Alignment(0, 0.5),
                      colors: [
                        Colors.black.withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Progress bars ─────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 12,
                right: 12,
                child: Row(
                  children: List.generate(user.stories.length, (i) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _ProgressBar(
                          isCompleted: i < _storyIndex,
                          isActive:    i == _storyIndex,
                          controller:  i == _storyIndex ? _progressController : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // ── Header ────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 26,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _gold, width: 2),
                      ),
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
                    const SizedBox(width: 10),
                    // Username + time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.username,
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
                    // Pause indicator
                    if (_isPaused)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
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

              // ── Left / right tap zones (visual hint) ─────
              Positioned(
                left: 0, top: 0, bottom: 0,
                width: size.width * 0.35,
                child: const SizedBox.expand(),
              ),
              Positioned(
                right: 0, top: 0, bottom: 0,
                width: size.width * 0.65,
                child: const SizedBox.expand(),
              ),

              // ── Bottom reply bar ──────────────────────────
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.white.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          'Reply to ${user.username}...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.send_rounded,
                      color: Colors.white.withOpacity(0.8),
                      size: 26,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Progress bar segment ─────────────────────────────────────
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
                      valueColor:
                          const AlwaysStoppedAnimation(Colors.white),
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