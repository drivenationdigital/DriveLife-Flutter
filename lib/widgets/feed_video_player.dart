import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../providers/video_mute_provider.dart';

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
  bool _isDisposed = false; // ✅ Track disposal

  @override
  void initState() {
    super.initState();
    _setupController(widget.url);
  }

  void _setupController(String url) {
    _currentUrl = url;

    // ✔ safely dispose old controller
    _controller?.removeListener(_controllerListener);
    _controller?.dispose();

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(_controllerListener)
      ..initialize().then((_) {
        if (!mounted || _isDisposed) return;
        setState(() {});
        if (widget.isActive) _controller?.play();
      });

    _controller?.setLooping(true);
  }

  void _controllerListener() {
    if (_isDisposed) return;
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ If the video URL changed → rebuild controller
    if (widget.url != _currentUrl) {
      _setupController(widget.url);
      return;
    }

    // ✅ Only control playback if initialized & not disposed
    if (_controller?.value.isInitialized == true && !_isDisposed) {
      widget.isActive ? _controller?.play() : _controller?.pause();
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // ✅ mark destroyed BEFORE disposing
    _controller?.removeListener(_controllerListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.watch<VideoMuteProvider>().muted;
    _controller?.setVolume(muted ? 0 : 1);

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final videoWidth = _controller!.value.size.width;
    final videoHeight = _controller!.value.size.height;
    final aspect = videoWidth / videoHeight;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate natural render height at full width
    final naturalHeight = screenWidth / aspect;

    // Max height allowed (65% of screen)
    final maxHeight = screenHeight * 0.65;

    // Decide whether to crop or contain
    final bool shouldCrop = naturalHeight > maxHeight;
    final double renderHeight = shouldCrop ? maxHeight : naturalHeight;
    final BoxFit fit = shouldCrop ? BoxFit.cover : BoxFit.contain;

    return VisibilityDetector(
      key: Key(widget.url),
      onVisibilityChanged: (info) {
        if (_isDisposed) return;
        if (info.visibleFraction < 0.1) {
          _controller?.pause();
        } else if (widget.isActive) {
          _controller?.play();
        }
      },
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          SizedBox(
            width: screenWidth,
            height: renderHeight,
            child: FittedBox(
              fit: fit,
              alignment: Alignment.center,
              child: SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),

          // 🔇 Global sound toggle
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
