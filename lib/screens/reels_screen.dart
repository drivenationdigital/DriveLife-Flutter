import 'package:flutter/material.dart';
import '../api/reels_api.dart';
import '../widgets/feed_video_player.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  List<Map<String, dynamic>> reels = [];
  int page = 1;
  bool isLoading = true;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadReels();
  }

  Future<void> _loadReels() async {
    final data = await ReelsAPI.getReels(userId: 1, page: page);
    final sampleVideos = [
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      'https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4',
      'https://media.w3.org/2010/05/sintel/trailer.mp4',
      'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
      'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    ];

    print('Loaded ${data.length} reels');
    print(data);

    for (var post in data) {
      if (post['media'] is List && post['media'].isNotEmpty) {
        // 30% chance to convert 1 media item into a "video"
        final randomVideo = sampleVideos[post.hashCode % sampleVideos.length];
        post['media'][0] = {'media_url': randomVideo, 'type': 'video'};
      }
    }

    print('Final reels data:');
    print(data);

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
        scrollDirection: Axis.vertical,
        onPageChanged: (i) {
          setState(() => currentIndex = i);

          // Load more reels when scrolling near bottom
          if (i > reels.length - 5) _loadReels();
        },
        itemCount: reels.length,
        itemBuilder: (context, i) {
          final post = reels[i];
          final media = post['media'] as List<dynamic>? ?? [];
          final video = media.firstWhere(
            (m) => (m['media_type'] == 'video'),
            orElse: () => null,
          );

          if (video == null) {
            // Skip rendering invalid post
            return const SizedBox.shrink();
          }

          return Stack(
            alignment: Alignment.bottomLeft,
            children: [
              FeedVideoPlayer(
                url: video['media_url'], // ✅ will replace with HLS soon
                isActive: i == currentIndex,
                fit: BoxFit.cover,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '@${post['username']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
