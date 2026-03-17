import 'package:video_player/video_player.dart';

class VideoPlaybackManager {
  VideoPlaybackManager._();
  static final VideoPlaybackManager instance = VideoPlaybackManager._();

  VideoPlayerController? _activeController;
  String? _activeUrl;

  final Map<String, double> _visibilityMap = {};
  final Map<String, VideoPlayerController> _controllerMap = {};

  void updateVisibility(
    String url,
    double fraction,
    VideoPlayerController controller,
    bool muted,
  ) {
    _visibilityMap[url] = fraction;
    _controllerMap[url] = controller;

    // Find the single most visible video above threshold
    String? topUrl;
    double topFraction = 0.15;
    _visibilityMap.forEach((u, f) {
      if (f > topFraction) {
        topFraction = f;
        topUrl = u;
      }
    });

    if (topUrl == _activeUrl) return; // already playing the right one

    // Pause whatever is currently playing
    if (_activeController != null && _activeController!.value.isPlaying) {
      _activeController!.pause();
      _activeController!.setVolume(0);
    }

    _activeUrl = topUrl;
    _activeController = topUrl != null ? _controllerMap[topUrl] : null;

    if (_activeController != null) {
      _activeController!.setVolume(muted ? 0 : 1);
      _activeController!.play();
    }
  }

  void removeFromVisibility(String url) {
    _visibilityMap.remove(url);
    _controllerMap.remove(url);
    if (_activeUrl == url) {
      _activeController = null;
      _activeUrl = null;
    }
  }

  void register(VideoPlayerController controller, String url) {
    // If another video is currently active → kill it
    if (_activeController != null && _activeController != controller) {
      _activeController!
        ..pause()
        ..setVolume(0);
    }

    _activeController = controller;
    _activeUrl = url;
  }

  void play(VideoPlayerController controller, bool muted) {
    if (_activeController != controller) {
      register(controller, '');
    }

    controller
      ..setVolume(muted ? 0 : 1)
      ..play();
  }

  void pause(VideoPlayerController controller) {
    if (controller.value.isPlaying) {
      controller
        ..pause()
        ..setVolume(0);
    }

    if (_activeController == controller) {
      _activeController = null;
      _activeUrl = null;
    }
  }

  void stopAll() {
    if (_activeController != null) {
      _activeController!
        ..pause()
        ..setVolume(0);
    }
    _activeController = null;
    _activeUrl = null;
  }
}
