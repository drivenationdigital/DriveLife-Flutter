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
  bool _isDisposed = false;
  bool _hasError = false;
  int _retryCount = 0;

  static const int _maxRetries = 5;
  static const Duration _retryDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _setupController(widget.url);
  }

  Future<void> _setupController(String url) async {
    if (_isDisposed) return;

    // Clean up existing controller
    final old = _controller;
    _controller = null;
    old?.dispose();

    if (mounted) {
      setState(() {
        _hasError = false;
      });
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;

    try {
      await controller.initialize();

      if (_isDisposed || !mounted) {
        controller.dispose();
        return;
      }

      await controller.setLooping(true);
      await controller.setVolume(0);

      _retryCount = 0;
      setState(() {});
    } catch (e) {
      // Cloudflare returns 404 while the video is still processing.
      // Retry a few times with increasing delay before showing error UI.
      if (_isDisposed || !mounted) return;

      debugPrint('Video load failed (attempt ${_retryCount + 1}): $e');

      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delay = _retryDelay * _retryCount; // 3s, 6s, 9s, 12s, 15s
        debugPrint('Retrying in ${delay.inSeconds}s...');

        await Future.delayed(delay);

        if (_isDisposed || !mounted) return;
        _setupController(url);
      } else {
        // Exhausted retries — show error state, don't crash
        if (mounted) {
          setState(() => _hasError = true);
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.url != oldWidget.url) {
      _retryCount = 0;
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

    // ── Error state — video still processing or permanently unavailable ──
    if (_hasError) {
      return SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.65,
        child: Container(
          color: Colors.black12,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                color: Colors.white38,
                size: 36,
              ),
              const SizedBox(height: 10),
              const Text(
                'Video unavailable',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  _retryCount = 0;
                  _setupController(widget.url);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Tap to retry',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Loading state ────────────────────────────────────────────────────
    if (_controller == null || !_controller!.value.isInitialized) {
      return SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.65,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2,
              ),
              if (_retryCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Processing video… ($_retryCount/$_maxRetries)',
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ── Playback ─────────────────────────────────────────────────────────
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
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 0.65,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.center,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),

          // Mute button
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
