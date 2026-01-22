import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/video_playback_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../providers/video_mute_provider.dart';

class FeedVideoPlayer extends StatefulWidget {
  final String url;
  final bool isActive;
  final BoxFit fit;
  final Alignment alignment;

  const FeedVideoPlayer({
    super.key,
    required this.url,
    required this.isActive,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  String? _currentUrl;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _setupController(widget.url);
  }

  void _setupController(String url) {
    _currentUrl = url;

    _controller?.dispose();

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;

    controller
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted || _isDisposed) return;
        setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.url != oldWidget.url) {
      _setupController(widget.url);
      return;
    }

    if (!widget.isActive && _controller != null) {
      VideoPlaybackManager.instance.pause(_controller!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Listen for mute changes and apply immediately
    final muted = context.watch<VideoMuteProvider>().muted;

    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_isDisposed) {
      _controller!.setVolume(muted ? 0 : 1);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    if (_controller != null) {
      VideoPlaybackManager.instance.pause(_controller!);
      _controller!.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final muted = context.watch<VideoMuteProvider>().muted;

    if (_controller == null || !_controller!.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    // Video’s natural size
    final size = _controller!.value.size;
    final videoWidth = size.width;
    final videoHeight = size.height;

    final screenWidth = MediaQuery.of(context).size.width;

    // 👉 Dynamic height preserving aspect ratio
    final dynamicHeight = videoHeight == 0
        ? 500
        : (screenWidth * videoHeight / videoWidth);

    return VisibilityDetector(
      key: Key(widget.url),
      onVisibilityChanged: (info) {
        if (_isDisposed || _controller == null) return;

        if (info.visibleFraction < 0.1) {
          VideoPlaybackManager.instance.pause(_controller!);
          return;
        }

        if (!widget.isActive) {
          VideoPlaybackManager.instance.pause(_controller!);
          return;
        }

        VideoPlaybackManager.instance.register(_controller!, widget.url);
        VideoPlaybackManager.instance.play(_controller!, muted);
      },
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // ✅ FIXED FULL-WIDTH CROPPING VIEWPORT
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 0.65, // feed height
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover, // ✅ CROPS instead of squeezing
                alignment: Alignment.center,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),

          // ✅ Mute Button
          GestureDetector(
            onTap: () => context.read<VideoMuteProvider>().toggle(),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
