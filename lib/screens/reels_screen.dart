import 'package:flutter/material.dart';
import '../api/reels_api.dart';
import '../widgets/feed/feed_video_player.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();
  List<Map<String, dynamic>> reels = [];
  int page = 1;
  bool isLoading = true;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadReels();
  }

  @override
  void dispose() {
    _pageController.dispose(); // ✅ Dispose controller
    super.dispose();
  }

  Future<void> _loadReels() async {
    if (!mounted) return; // ✅ Check before starting

    final data = await ReelsAPI.getReels(userId: 1, page: page);

    // ✅ CRITICAL: Check mounted after async operation
    if (!mounted) return;

    final sampleVideos = [
      // 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      'https://videodelivery.net/c2b98b8485461a046d6fc867d57b6782/manifest/video.m3u8',
      'https://videodelivery.net/f2c5e16577b2dbfc2b629b9ebedba218/manifest/video.m3u8',
    ];

    for (var post in data) {
      if (post['media'] is List && post['media'].isNotEmpty) {
        final randomVideo = sampleVideos[post.hashCode % sampleVideos.length];

        post['media'][0] = {'media_url': randomVideo, 'media_type': 'video'};
      }
    }

    // ✅ Safe to call setState now
    setState(() {
      reels.addAll(data);
      isLoading = false;
      page++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && reels.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: reels.length,
        onPageChanged: (i) {
          if (!mounted) return; // ✅ Check mounted in callback

          setState(() => currentIndex = i);

          if (i > reels.length - 3) {
            _loadReels(); // ✅ Infinite scroll preload (has its own mounted check)
          }
        },
        itemBuilder: (context, i) {
          final post = reels[i];
          final media = post['media'] as List<dynamic>? ?? [];

          final video = media.firstWhere(
            (m) => (m['media_type'] == 'video'),
            orElse: () => null,
          );

          if (video == null) return const SizedBox.shrink();

          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // ✅ FULLSCREEN CROPPED VIDEO
              FeedVideoPlayer(
                url: video['media_url'],
                isActive: i == currentIndex,
                fit: BoxFit.fitWidth,
              ),

              // ✅ GRADIENT OVERLAY (BOTTOM)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 220,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),

              // ✅ USERNAME + CAPTION
              Positioned(
                left: 16,
                bottom: 24,
                right: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${post['username'] ?? 'user'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      post['caption'] ?? 'Amazing video 🔥',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // ✅ RIGHT SIDE ACTIONS (UI ONLY)
              Positioned(
                right: 12,
                bottom: 80,
                child: Column(
                  children: [
                    _ActionButton(icon: Icons.favorite, label: '1.2K'),
                    const SizedBox(height: 14),
                    _ActionButton(icon: Icons.comment, label: '320'),
                    const SizedBox(height: 14),
                    _ActionButton(icon: Icons.share, label: 'Share'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black54,
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
