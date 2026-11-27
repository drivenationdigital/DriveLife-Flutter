import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Keeps a long-form video playing when the app is not on screen.
///
/// ── WHAT THIS ACTUALLY BUYS ─────────────────────────────────────────
///
/// Two different things, and it is worth being clear which is which.
///
/// On iOS the audio would very nearly continue on its own: the
/// video_player plugin already puts the audio session in the Playback
/// category, and it installs no lifecycle handlers, so it does not
/// pause itself when the app goes away. All it needed was the `audio`
/// background mode in Info.plist. What this class adds there is the
/// LOCK SCREEN - the title, the artwork, and controls that work.
///
/// On Android it is the whole feature. An app in the background is a
/// process Android is entitled to freeze and then kill, and ExoPlayer
/// goes quiet with it. The only thing that stops that is a foreground
/// service with a media notification, which is precisely what
/// audio_service starts on the first playing state published below.
///
/// ── WHY A HANDLER RATHER THAN A SECOND PLAYER ───────────────────────
///
/// audio_service is usually paired with just_audio, which would mean a
/// second player holding a second copy of the stream, and then the job
/// of keeping two positions in step. There is nothing to gain from
/// that: audio_service does not care what makes the sound, only that
/// something answers play, pause and seek and says where it is up to.
///
/// So this is a thin shell over the VideoPlayerController the watch
/// screen already owns. One player, one position, one source of truth
/// - and the lock screen is a VIEW of it rather than a second copy.
///
/// ── NOT FOR YOUTUBE ────────────────────────────────────────────────
///
/// Only Cloudflare-backed videos are ever attached. A YouTube embed is
/// a WebView that stops when it is suspended, and - much more to the
/// point - YouTube's API terms prohibit background and audio-only
/// playback outright. See VideoWatchScreen, which gates on this.
class VideoAudioHandler extends BaseAudioHandler {
  /// The one instance, created by [AudioService.init] during launch.
  ///
  /// Null when the service failed to start, which is a thing that can
  /// happen on a device with notifications switched off at the OS
  /// level. Every caller treats that as "no lock screen" and carries
  /// on playing normally, because a missing nicety must not take the
  /// video player down with it.
  static VideoAudioHandler? instance;

  /// How far the lock-screen skip buttons move, matching the ones on
  /// the watch screen itself.
  static const Duration skipInterval = Duration(seconds: 15);

  VideoPlayerController? _controller;
  VoidCallback? _listener;

  bool get isAttached => _controller != null;

  /// Starts reporting [controller] to the OS.
  ///
  /// Called once the video is playable, not when the screen opens: a
  /// lock screen that appears before there is anything to play is a
  /// notification somebody has to dismiss.
  void attach({
    required VideoPlayerController controller,
    required String id,
    required String title,
    String? artist,
    String? artUri,
  }) {
    // Defensive. Opening a second video without leaving the first
    // should not leave two listeners writing to one playback state.
    detach();

    _controller = controller;

    final art = (artUri ?? '').trim();

    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        album: 'DriveLife',
        artist: artist == null || artist.trim().isEmpty ? null : artist.trim(),
        duration: controller.value.duration,
        artUri: art.isEmpty ? null : Uri.tryParse(art),
      ),
    );

    // The same listener the watch screen uses, for the same reason:
    // it fires on every value change, so there is nothing to arm and
    // nothing that can be left un-armed.
    _listener = _publish;
    controller.addListener(_publish);

    _publish();
  }

  /// Stops reporting, and takes the notification away with it.
  void detach() {
    final controller = _controller;

    if (controller != null && _listener != null) {
      controller.removeListener(_publish);
    }

    _controller = null;
    _listener = null;

    // idle rather than just playing: false. On Android this is what
    // lets the foreground service stop, and a media notification left
    // behind for a video nobody is watching is the single most
    // annoying thing this feature could do.
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  /// Mirrors the controller's state out to the OS.
  void _publish() {
    final controller = _controller;

    if (controller == null) return;

    final value = controller.value;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          if (value.isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
        ],
        // So dragging the lock screen's own progress bar works rather
        // than being a read-only strip.
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: !value.isInitialized
            ? AudioProcessingState.loading
            : (value.isBuffering
                  ? AudioProcessingState.buffering
                  : AudioProcessingState.ready),
        playing: value.isPlaying,
        updatePosition: value.position,
        bufferedPosition: value.buffered.isEmpty
            ? Duration.zero
            : value.buffered.last.end,
        speed: value.playbackSpeed,
      ),
    );

    // The duration is not known at attach time for every source, and
    // a lock screen whose scrubber has no length cannot be dragged.
    final item = mediaItem.value;

    if (item != null &&
        value.duration > Duration.zero &&
        item.duration != value.duration) {
      mediaItem.add(item.copyWith(duration: value.duration));
    }
  }

  // ── What the lock screen and the headphone buttons call ───────────

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seek(Duration position) async {
    final controller = _controller;

    if (controller == null) return;

    final total = controller.value.duration;

    await controller.seekTo(
      position < Duration.zero
          ? Duration.zero
          : (total > Duration.zero && position > total ? total : position),
    );
  }

  @override
  Future<void> rewind() => seek(_relative(-skipInterval));

  @override
  Future<void> fastForward() => seek(_relative(skipInterval));

  Duration _relative(Duration by) {
    return (_controller?.value.position ?? Duration.zero) + by;
  }

  /// The X on the notification, and "stop" from a headset.
  @override
  Future<void> stop() async {
    await _controller?.pause();

    detach();

    await super.stop();
  }
}
