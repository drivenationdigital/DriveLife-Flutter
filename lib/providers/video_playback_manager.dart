import 'package:video_player/video_player.dart';

class VideoPlaybackManager {
  VideoPlaybackManager._();
  static final VideoPlaybackManager instance = VideoPlaybackManager._();

  VideoPlayerController? _activeController;
  String? _activeUrl;

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
