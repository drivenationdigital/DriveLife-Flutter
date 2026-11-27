import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/api/interactions_api.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/screens/comments_bottom_sheet.dart';
import 'package:drivelife/screens/media/video_edit_screen.dart';
import 'package:drivelife/services/video_audio_handler.dart';
import 'package:drivelife/widgets/expandable_text.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// Watching one long-form video.
///
/// ── WHAT IT BORROWS RATHER THAN REBUILDS ────────────────────────────
///
/// Comments. A video is a post - see the note on [LongVideo] - so the
/// comment button opens [CommentsBottomSheet], the same sheet the feed
/// opens, against the same post id. Replies, likes on comments, image
/// comments, tagging, moderation and deletion all work because none of
/// it is new.
///
/// Likes go through InteractionsAPI.maybeLikePost for the same reason.
///
/// ── AND WHAT IT HAD TO DO ITSELF ────────────────────────────────────
///
/// Resuming. [FeedVideoPlayer] is built for a feed - muted, autoplay,
/// whatever is most visible wins - and almost none of that is wanted
/// here. This screen is the opposite: one video, sound on, playing
/// because somebody asked, and remembering where they got to.
class VideoWatchScreen extends StatefulWidget {
  final LongVideo video;

  const VideoWatchScreen({super.key, required this.video});

  @override
  State<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

class _VideoWatchScreenState extends State<VideoWatchScreen>
    with WidgetsBindingObserver {
  // ── TWO PLAYERS, ONE SCREEN ──────────────────────────────────────
  //
  // A video either lives in Cloudflare Stream, where it is a file we
  // hand to video_player, or on YouTube, where it is an iframe in a
  // WebView. Only one of these is ever non-null - see _video.isYoutube
  // - and everything below the picture is identical either way:
  // likes, comments, the author row, progress, view counting, delete.
  //
  // So the alternative to this was two watch screens with one player
  // each and seven hundred lines of social UI copied between them,
  // which is the version that quietly drifts apart. The players differ
  // in four things - position, duration, playing, and how to issue a
  // command - so those four are behind the facade below and the rest
  // of the screen does not know which player it has.
  VideoPlayerController? _controller;

  YoutubePlayerController? _yt;

  // ── WHY YOUTUBE STATE IS MIRRORED INTO FIELDS ────────────────────
  //
  // video_player holds its position in a ValueNotifier, so a build
  // method can simply read it. The embed cannot: position arrives on
  // a stream and currentTime is a Future that crosses into
  // JavaScript, which is no use during layout. So the last reported
  // values are kept here.
  Duration _ytPosition = Duration.zero;
  Duration _ytDuration = Duration.zero;
  PlayerState _ytState = PlayerState.unknown;

  StreamSubscription<YoutubeVideoState>? _ytPositionSub;
  StreamSubscription<YoutubePlayerValue>? _ytValueSub;

  /// Drives the hide-controls clock for the embed.
  ///
  /// The Cloudflare path gets this free: its listener fires several
  /// times a second whatever the state, so a timestamp checked on each
  /// tick is enough. The embed's position stream only emits while the
  /// video is actually playing, so there would be nothing to check
  /// against on a video that has just been un-paused.
  Timer? _ytTicker;

  bool get _isYoutube => _video.isYoutube;

  /// Whether there is a player to issue commands to.
  bool get _ready =>
      _isYoutube ? _yt != null : (_controller?.value.isInitialized ?? false);

  Duration get _position =>
      _isYoutube ? _ytPosition : (_controller?.value.position ?? Duration.zero);

  /// How long it runs.
  ///
  /// Falls back to the duration the server sent, which for a YouTube
  /// video is how the scrubber has a scale at all in the second before
  /// the player's metadata lands - and, on the very first play of a
  /// newly added one, is zero because nobody knows yet.
  Duration get _total {
    if (_isYoutube) {
      return _ytDuration != Duration.zero
          ? _ytDuration
          : Duration(seconds: _video.durationSeconds);
    }

    return _controller?.value.duration ?? Duration.zero;
  }

  bool get _playing => _isYoutube
      ? _ytState == PlayerState.playing
      : (_controller?.value.isPlaying ?? false);

  Future<void> _playerPlay() async {
    if (_isYoutube) {
      _yt?.playVideo();

      return;
    }

    await _controller?.play();
  }

  Future<void> _playerPause() async {
    if (_isYoutube) {
      _yt?.pauseVideo();

      return;
    }

    await _controller?.pause();
  }

  Future<void> _playerSeek(Duration to) async {
    final target = to < Duration.zero ? Duration.zero : to;

    if (_isYoutube) {
      // allowSeekAhead, so a seek past what is buffered actually moves
      // rather than being clamped to the loaded range.
      await _yt?.seekTo(
        seconds: target.inMilliseconds / 1000,
        allowSeekAhead: true,
      );

      // Optimistic. The next emission from the position stream is up
      // to 200ms away, and a scrubber that does not move until then
      // reads as a control that missed.
      if (mounted) setState(() => _ytPosition = target);

      return;
    }

    await _controller?.seekTo(target);
  }

  Future<void> _playerSpeed(double rate) async {
    if (_isYoutube) {
      await _yt?.setPlaybackRate(rate);

      return;
    }

    // Only while playing. setPlaybackSpeed on a paused controller
    // starts it again on some platforms, which is a surprising thing
    // for a speed button to do. The embed has no such habit.
    final controller = _controller;

    if (controller != null && controller.value.isPlaying) {
      await controller.setPlaybackSpeed(rate);
    }
  }

  bool _preparing = true;
  String? _error;

  late LongVideo _video;

  /// Where they were when the screen opened, so the "resumed from"
  /// note can say so without reading the live position.
  int? _resumedFrom;

  /// Throttles saving. The position listener fires many times a
  /// second; the store only wants whole seconds that have changed.
  int _lastSaved = -1;

  /// Whether this watch has been counted yet.
  ///
  /// Once per screen, not once per app launch: somebody who comes
  /// back to a video tomorrow and watches more of it has watched it
  /// again, and that is a view.
  bool _counted = false;

  /// How long playback must run before it counts.
  ///
  /// Opening a video and backing straight out is not a view. Five
  /// seconds is long enough to exclude a mis-tap and short enough
  /// that anybody who meant to watch is counted.
  static const int _viewAfterSeconds = 5;

  /// Whether the picture has the whole screen.
  ///
  /// ── TWO MECHANISMS, ONE BEHAVIOUR ──────────────────────────────
  ///
  /// The Cloudflare picture is a texture this screen draws, so
  /// fullscreen is this screen choosing to draw it over everything
  /// else - see [_cloudflareFullscreen]. No route is pushed: one
  /// screen means one copy of the state, the controls and the
  /// scrubber rather than two that have to agree.
  ///
  /// The embed is a WebView the package owns, inside an OverlayPortal,
  /// and it has its own fullscreen which expands that overlay to the
  /// screen and keeps our controls above it. Reparenting a live
  /// WebView ourselves would reload the video, so for the embed we
  /// ask the package and follow.
  ///
  /// Shared either way: this flag, the orientation, the controls and
  /// the way back out.
  bool _fullscreen = false;

  /// Whether fullscreen should be PORTRAIT for this video.
  ///
  /// ── A SHORT TURNED SIDEWAYS IS TWO BLACK BARS ──────────────────
  ///
  /// The first attempt at fullscreen forced landscape for everything,
  /// which was written when every video here was 16:9. A Short is
  /// 9:16: rotating the phone to watch one leaves a thin strip of
  /// video between two enormous bars, and makes the person turn the
  /// phone back to read anything.
  ///
  /// So the orientation follows the VIDEO. [LongVideo.isShort] is the
  /// server's answer and the only one available for an embed - the
  /// iframe API never reports a video's dimensions. For Cloudflare the
  /// real ratio is known once the controller initialises, so a
  /// portrait upload behaves like a Short without being flagged as
  /// one.
  bool get _prefersPortrait {
    if (_video.isShort) return true;

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return false;

    return _pictureRatio(controller) < 1;
  }

  bool _scrubbing = false;

  /// Where the finger is during a drag, in seconds.
  ///
  /// Only read while [_scrubbing]. The Cloudflare player seeks on
  /// every frame of the drag so its position IS this; the embed does
  /// not, so the label has to be driven from here instead - see the
  /// note in _scrubber.
  double _scrubTo = 0;

  /// The first few comments, shown inline under the video.
  List<dynamic> _comments = const [];
  bool _loadingComments = true;

  /// Whether to offer Delete. Asked of the server rather than
  /// inferred from the uploader id: an admin can remove somebody
  /// else's video, and a non-admin uploader should not see it.
  bool _canDelete = false;

  /// Whether the controls are drawn over the picture.
  ///
  /// Starts TRUE. A player that opens with everything hidden looks
  /// like a video that has not started, and the first thing somebody
  /// does is tap it - which, with the controls hidden, pauses it.
  bool _showControls = true;

  /// When they were last shown.
  ///
  /// ── WHY A TIMESTAMP AND NOT A TIMER ─────────────────────────────
  ///
  /// A Timer has to be armed by somebody, and twice it was not:
  ///
  ///   * Nothing armed one when the video first started playing, so
  ///     the controls sat there until the picture was tapped.
  ///   * A timer that fired mid-scrub found _scrubbing true, declined
  ///     to hide, and was then gone - nothing re-armed it when the
  ///     drag ended, so the controls stayed up for the rest of the
  ///     video.
  ///
  /// Both are the same bug: state that has to be maintained by every
  /// caller. A timestamp checked on each position tick cannot be
  /// forgotten, because the ticks arrive on their own as long as
  /// something is playing - so this heals itself rather than needing
  /// every new control to remember to re-arm it.
  DateTime? _shownAt;

  /// How long they linger once playback is running.
  static const Duration _lingerFor = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();

    // For the wakelock, which must follow whether this screen is in
    // FRONT of somebody as well as whether something is playing. See
    // _syncWakelock.
    WidgetsBinding.instance.addObserver(this);

    _video = widget.video;

    _prepare();

    unawaited(_loadComments());
    unawaited(_checkAdmin());
  }

  Future<void> _loadComments() async {
    final response = await InteractionsAPI.fetchComments(_video.postId);

    if (!mounted) return;

    setState(() {
      _comments = response.comments;
      _loadingComments = false;

      // The count comes from what was actually fetched rather than
      // from whatever the card was carrying when this screen opened.
      // It is the one number here that can be known exactly, so it
      // should not be the one that is out of date.
      _video = _video.copyWith(commentCount: response.comments.length);
    });
  }

  Future<void> _checkAdmin() async {
    final permission = await VideosAPI.uploadPermission();

    if (mounted) setState(() => _canDelete = permission.canUpload);
  }

  /// Title, description and playlists. Admin only, and gated by the
  /// same check that shows this menu at all.
  Future<void> _edit() async {
    final controller = _controller;
    final wasPlaying = controller?.value.isPlaying ?? false;

    if (wasPlaying) await controller!.pause();

    if (!mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VideoEditScreen(video: _video)),
    );

    if (!mounted) return;

    // Re-read rather than guess at what was typed: the server
    // sanitises the title and may not have stored it character for
    // character.
    if (saved == true) await _reloadVideo();

    if (wasPlaying && mounted) {
      await controller!.play();

      if (_speed != 1) await controller.setPlaybackSpeed(_speed);
    }
  }

  /// Pulls this video's row again, after an edit.
  Future<void> _reloadVideo() async {
    final videos = await VideosAPI.list(limit: 50);

    if (!mounted) return;

    for (final video in videos) {
      if (video.postId == _video.postId) {
        setState(() => _video = video);
        return;
      }
    }
  }

  Future<void> _confirmDelete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this video?'),
        // Said plainly, because it is not just a row in a table:
        // deleting removes it from Cloudflare too, which frees the
        // storage and cannot be undone from here.
        content: const Text(
          'It will be removed from the app and from Cloudflare. The '
          'video itself cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (yes != true || !mounted) return;

    final gone = await VideosAPI.delete(_video.postId);

    if (!mounted) return;

    if (!gone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete that video.')),
      );

      return;
    }

    Navigator.of(context).pop(true);
  }

  Future<void> _prepare() async {
    if (!_video.isPlayable) {
      setState(() {
        _preparing = false;
        _error = 'This video is still processing. Try again shortly.';
      });

      return;
    }

    // Read the resume position BEFORE the controller is ready, so the
    // seek happens as part of starting rather than as a visible jump
    // a second after playback begins.
    final resume = await WatchProgress.positionFor(_video.postId);

    if (!mounted) return;

    if (_isYoutube) {
      await _prepareYoutube(resume);

      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_video.videoUrl),
      // ── THE ONE THING THAT MAKES BACKGROUND AUDIO WORK ─────────
      //
      // video_player installs a lifecycle observer of its OWN unless
      // this is set, and that observer does exactly this:
      //
      //     if (state == AppLifecycleState.paused) {
      //       _wasPlayingBeforePause = _controller.value.isPlaying;
      //       _controller.pause();
      //     }
      //
      // So minimising the app paused the video from the Dart side,
      // above every bit of native configuration - the iOS background
      // mode, the Android foreground service, the media session, all
      // of it correct and all of it beaten to the punch.
      //
      // Setting this does ONE thing: it stops that observer being
      // installed. Nothing else changes.
      //
      // ── AND ONLY HERE ──────────────────────────────────────────
      //
      // Not in the feed. A clip in a scrolling feed SHOULD stop when
      // the app goes away - it is muted, it autoplays, and nobody
      // asked for it. This screen is the opposite: one video, sound
      // on, playing because somebody pressed play. Only that deserves
      // to carry on.
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
    );

    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('[video] initialize failed: $e');

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _preparing = false;
        _error = 'Could not play this video.';
      });

      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    // Never past the end. A stored position from a re-uploaded, shorter
    // video would otherwise seek beyond the duration and sit there.
    final total = controller.value.duration.inSeconds;

    if (resume != null && resume > 0 && resume < total - 5) {
      await controller.seekTo(Duration(seconds: resume));
      _resumedFrom = resume;
    }

    controller.addListener(_onTick);

    setState(() {
      _controller = controller;
      _preparing = false;
    });

    // ── THE LOCK SCREEN, AND BACKGROUND AUDIO WITH IT ────────────
    //
    // Here rather than when the screen opened: a lock-screen entry
    // for a video that turned out not to play is a notification
    // somebody has to dismiss for nothing.
    //
    // Null when the media session could not start - see main.dart.
    // The video plays regardless; it simply does not survive being
    // backgrounded on Android, and has no lock-screen controls.
    //
    // Cloudflare only. The YouTube path never reaches this line
    // because it returns in _prepare long before - which is correct
    // twice over: a suspended WebView stops anyway, and YouTube's
    // terms prohibit background playback.
    VideoAudioHandler.instance?.attach(
      controller: controller,
      id: _video.postId,
      title: _video.title,
      artist: _video.authorName,
      artUri: _video.thumbnailUrl,
    );

    await controller.play();

    if (_speed != 1) await controller.setPlaybackSpeed(_speed);

    // Start the clock. Without this the controls opened and stayed,
    // because nothing had marked when they appeared.
    _revealControls();
  }

  /// Starting the embed.
  ///
  /// Shorter than the Cloudflare path and in one place better than it:
  /// the resume position is handed over as startSeconds, so the video
  /// begins where it left off instead of starting at zero and seeking
  /// a moment later. There is nothing to initialise and nothing that
  /// can fail locally - a dead video id is reported by the player
  /// itself, through the error on YoutubePlayerValue.
  Future<void> _prepareYoutube(int? resume) async {
    final id = _youtubeId();

    if (id == null) {
      setState(() {
        _preparing = false;
        _error = 'This video has no YouTube id.';
      });

      return;
    }

    // Never past the end, for the same reason the Cloudflare path
    // guards it: a stored position from a video that has since been
    // replaced by a shorter one would start at the credits.
    final total = _video.durationSeconds;
    final usable =
        resume != null && resume > 0 && (total <= 0 || resume < total - 5);

    final controller = YoutubePlayerController.fromVideoId(
      videoId: id,
      autoPlay: true,
      startSeconds: usable ? resume.toDouble() : null,
      params: const YoutubePlayerParams(
        // YoutubePlayer forces these off on mobile when a builder is
        // supplied. Set here as well so the desktop and web builds
        // behave the same, rather than growing YouTube's own controls
        // underneath ours.
        showControls: false,
        showFullscreenButton: false,
        // ── AND THE REST OF YOUTUBE'S CHROME ─────────────────────
        //
        // showControls: false removes the control BAR. It does not
        // remove everything: tap the picture and YouTube still brings
        // up its own title, channel avatar and share button over the
        // top of the video, and its own tap-to-pause fires underneath
        // our overlay - so one tap could reveal our controls and
        // pause the video at the same time.
        //
        // modestbranding used to help with that and does nothing at
        // all now; YouTube retired it.
        //
        // pointer-events: none is the thing that works. The package
        // writes it straight onto the iframe (see its
        // assets/player.html), so taps never reach YouTube's player
        // and there is nothing to summon its chrome. Every control is
        // ours, in the Flutter overlay above, and those are untouched
        // because they were never inside the WebView.
        //
        // Playback is unaffected: play, pause, seek and rate all go
        // through the JavaScript API, which CSS has no say over.
        //
        // This hides YouTube's INTERFACE. It does not strip the
        // branding out of the video, which is both impossible from
        // here and against their terms - nothing below tries.
        pointerEvents: PointerEvents.none,
        // Keeps the end-of-video grid to the same channel instead of
        // offering the whole of YouTube. It cannot be switched off
        // altogether - see the note at the foot of this file.
        strictRelatedVideos: true,
        showVideoAnnotations: false,
        playsInline: true,
        // Twice the 100ms default. The scrubber shows whole seconds
        // and every emission crosses a JavaScript bridge.
        videoStateUpdateInterval: 200,
      ),
    );

    if (usable) _resumedFrom = resume;

    _ytPositionSub = controller.videoStateStream.listen(_onYoutubePosition);
    _ytValueSub = controller.stream.listen(_onYoutubeValue);

    // ── NOT EVERY EXIT COMES FROM OUR BUTTON ─────────────────────
    //
    // The package wraps the player in its own PopScope and leaves
    // fullscreen on the back gesture, without telling whoever called
    // enterFullScreen. So the orientation is restored from HERE, on
    // the transition, rather than from _toggleFullscreen - that way
    // every route out of fullscreen puts the phone back.
    //
    // Nothing else in either package registers this listener, so
    // there is nobody to overwrite it.
    controller.setFullScreenListener((full) {
      if (!mounted) return;

      setState(() => _fullscreen = full);

      unawaited(full ? _allowFullscreenOrientation() : _restorePortrait());
    });

    _ytTicker = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => _maybeHideControls(),
    );

    setState(() {
      _yt = controller;
      _preparing = false;
    });

    _revealControls();
  }

  /// The id to play.
  ///
  /// Prefers the column the server sends. Falls back to pulling it out
  /// of the URL, so a build of the app that is newer than the server
  /// still plays videos whose payload predates the youtube_id field.
  String? _youtubeId() {
    final sent = _video.youtubeId.trim();

    if (sent.isNotEmpty) return sent;

    final url = _video.videoUrl.trim();

    if (url.isEmpty) return null;

    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(url)) return url;

    return YoutubePlayerController.convertUrlToId(url);
  }

  void _onYoutubePosition(YoutubeVideoState state) {
    _ytPosition = state.position;

    _afterPosition();
  }

  void _onYoutubeValue(YoutubePlayerValue value) {
    _ytState = value.playerState;

    final duration = value.metaData.duration;

    final learned = duration != Duration.zero && duration != _ytDuration;

    if (learned) _ytDuration = duration;

    // ── TELLING THE APP HOW LONG IT IS ───────────────────────────
    //
    // A YouTube video is created not knowing its own length, because
    // YouTube will not say without the Data API. The player does know,
    // a second after it loads - so the card and the countdown get the
    // real number from here, and _countView sends it to the server so
    // the next person does not have to wait for it either.
    if (learned && _video.durationSeconds == 0 && mounted) {
      _video = _video.copyWith(durationSecondsOverride: duration.inSeconds);
    }

    _syncWakelock();

    if (_playing) _playingSince ??= DateTime.now();

    // Pausing and finishing both bring the controls back and leave
    // them up. The Cloudflare path gets this from its tick arriving
    // regardless of state; the embed's stream goes quiet when paused,
    // so it is said here instead.
    if (value.playerState == PlayerState.paused ||
        value.playerState == PlayerState.ended) {
      _showControls = true;
      _shownAt = null;
    }

    // The player reports a bad id, a video that is private, or one
    // the owner has blocked from embedding. All three look the same to
    // somebody watching: it will not play.
    if (value.hasError && _error == null) {
      _error = 'This video cannot be played here.';
    }

    if (mounted) setState(() {});
  }

  /// Seconds of playback since this screen opened.
  int get _playedSeconds {
    final startedAt = _playingSince;

    if (startedAt == null) return 0;

    return DateTime.now().difference(startedAt).inSeconds;
  }

  DateTime? _playingSince;

  /// Keeps the screen on while somebody is WATCHING, and lets it
  /// sleep the moment they are not.
  ///
  /// ── WHY IT FOLLOWS PLAYBACK AND NOT THE SCREEN ──────────────────
  ///
  /// Enabling on open and disabling on dispose is simpler and wrong:
  /// a video paused halfway while somebody reads the comments would
  /// hold the screen awake indefinitely, and a phone left on this
  /// screen in a pocket would never lock.
  ///
  /// ── AND WHY PLAYING IS NO LONGER ENOUGH ON ITS OWN ──────────────
  ///
  /// Because the audio now carries on when the app is in the
  /// background - see VideoAudioHandler. "Playing" and "being watched"
  /// used to be the same thing and are not any more: somebody who
  /// locks their phone and keeps listening wants the screen OFF, and
  /// a wakelock held through that is the whole battery.
  ///
  /// So this takes both: playing, AND this screen actually in front of
  /// somebody. Backgrounding releases it without touching playback;
  /// coming back takes it again if the video is still going.
  ///
  /// Guarded by [_wakelockOn] because the tick fires several times a
  /// second and each call is a platform channel round trip.
  void _syncWakelock() {
    final want = _playing && _foreground;

    if (want == _wakelockOn) return;

    _wakelockOn = want;

    // Never awaited and never fatal. A phone that refuses to hold the
    // screen on - some Android power-saving modes do - should dim,
    // not crash the player.
    unawaited(
      WakelockPlus.toggle(
        enable: want,
      ).catchError((Object e) => debugPrint('[video] wakelock: $e')),
    );
  }

  bool _wakelockOn = false;

  /// Whether this screen is in front of somebody right now.
  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    _foreground = state == AppLifecycleState.resumed;

    // Deliberately only the wakelock. Playback is left exactly as it
    // was, which is the point of the feature - the lock screen takes
    // over from here.
    _syncWakelock();
  }

  /// Redraws when the WINDOW changes shape.
  ///
  /// ── THE HALF-ROTATED SCREEN ────────────────────────────────────
  ///
  /// Entering fullscreen used to leave the player, now and then, laid
  /// out down the left-hand 45% of a landscape screen with the rest
  /// empty - a frame composed against the PORTRAIT metrics, still on
  /// display after the window had already turned.
  ///
  /// The shape is the giveaway: everything sat inside a box the width
  /// of the portrait screen, and the embed sat at the vertical centre
  /// of the portrait HEIGHT, far below the middle of the landscape
  /// one.
  ///
  /// The window turns a beat after the request to turn it, and the
  /// frame that was already on screen stays there until something
  /// draws another. With the Cloudflare player something always does
  /// - it has a texture updating many times a second - which is why
  /// this only ever showed up on the YouTube embed, where the picture
  /// is drawn natively and the Flutter side can be completely idle.
  /// Idle, it had no reason to lay out again, so the wrong frame
  /// simply stayed up.
  ///
  /// So: any metrics change, while fullscreen, forces a fresh layout.
  /// This is the backstop. [_settleOrientation] is the part that
  /// stops the bad frame being composed in the first place, and
  /// between them nothing has to be timed correctly.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    if (!_fullscreen) return;

    // After the frame, not during it. didChangeMetrics arrives inside
    // the engine's own window-metrics handling, and calling setState
    // from there rebuilds in the middle of a layout that is already
    // under way.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fullscreen) setState(() {});
    });
  }

  /// How fast it plays.
  ///
  /// The one control on a podcast player that is not on a feed clip,
  /// and the reason it is there: an hour of talking at 1.5x is forty
  /// minutes. Nobody wants that on a fifteen-second video, which is
  /// why it has never belonged anywhere else in this app.
  double _speed = 1;

  static const List<double> _speeds = [0.8, 1, 1.25, 1.5, 1.75, 2];

  Future<void> _cycleSpeed() async {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];

    setState(() => _speed = next);

    await _playerSpeed(next);
  }

  /// "1x", or "1.5x" - never "1.0x".
  String get _speedLabel {
    final text = _speed.toStringAsFixed(2);

    return '${text.replaceAll(RegExp(r'\.?0+$'), '')}x';
  }

  Future<void> _countView() async {
    // The duration goes with it for a YouTube video the server does
    // not know the length of yet. The server only accepts it when it
    // currently has none, so this cannot rewrite a known value - see
    // dl_videos_record_view.
    final learned = _isYoutube && widget.video.durationSeconds == 0
        ? _total.inSeconds
        : null;

    final count = await VideosAPI.markViewed(
      _video.postId,
      durationSeconds: learned,
    );

    if (count == null || !mounted) return;

    setState(() => _video = _video.copyWith(viewCount: count));
  }

  void _onTick() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return;

    _syncWakelock();

    _afterPosition();
  }

  /// Everything that happens because the position moved.
  ///
  /// Shared by both players deliberately. Progress, view counting and
  /// the hide-controls clock are decisions about WATCHING, and nothing
  /// about any of them depends on where the bytes came from - so there
  /// is one copy, reading through the facade at the top of this class.
  void _afterPosition() {
    // The clock starts the first time it is genuinely playing.
    if (_playing) _playingSince ??= DateTime.now();

    // Redraw for the scrubber and the time labels.
    if (mounted && !_scrubbing) setState(() {});

    // And take the controls away once they have had their moment.
    // Here rather than on a timer for the Cloudflare player, so it
    // cannot be left un-armed - see the note on _shownAt.
    _maybeHideControls();

    final seconds = _position.inSeconds;

    // Counted from time ACTUALLY PLAYED, not from the position -
    // otherwise resuming at 40:00 would count a view the instant the
    // screen opened, before a single frame had been shown.
    if (!_counted && _playing && _playedSeconds >= _viewAfterSeconds) {
      _counted = true;

      unawaited(_countView());
    }

    if (seconds == _lastSaved) return;

    _lastSaved = seconds;

    unawaited(
      WatchProgress.save(
        postId: _video.postId,
        seconds: seconds,
        durationSeconds: _total.inSeconds,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Before the controller is disposed, because the handler holds a
    // listener on it - and before anything else, because a media
    // notification outliving the screen it belongs to is the worst
    // way this feature could fail.
    //
    // Unconditional: detach on a handler that is not attached is a
    // no-op, and leaving this to a flag is how notifications get
    // stranded.
    VideoAudioHandler.instance?.detach();

    // Unconditionally, whatever state playback was in. A wakelock
    // left on after the screen is gone is a flat battery by lunchtime
    // and there is nothing left to turn it off.
    if (_wakelockOn) {
      _wakelockOn = false;

      unawaited(
        WakelockPlus.disable().catchError(
          (Object e) => debugPrint('[video] wakelock release: $e'),
        ),
      );
    }

    // One last save on the way out, read through the facade BEFORE
    // either player is torn down. The listeners throttle to whole
    // seconds, so leaving mid-second would otherwise lose up to a
    // second - which does not matter - but leaving while PAUSED would
    // lose the pause position, which does.
    if (_ready) {
      unawaited(
        WatchProgress.save(
          postId: _video.postId,
          seconds: _position.inSeconds,
          durationSeconds: _total.inSeconds,
        ),
      );
    }

    // ── PUT THE PHONE BACK ───────────────────────────────────────
    //
    // A screen that is gone cannot restore anything, and an app left
    // in landscape with its system bars hidden is a worse bug than
    // whatever caused it. This covers the paths that do not go
    // through the fullscreen button at all: a notification tap, a
    // deep link, anything that pops this route while fullscreen is
    // open.
    if (_fullscreen) {
      unawaited(_restorePortrait());
    }

    final controller = _controller;

    if (controller != null) {
      controller.removeListener(_onTick);
      controller.dispose();
    }

    _ytTicker?.cancel();
    unawaited(_ytPositionSub?.cancel());
    unawaited(_ytValueSub?.cancel());
    _yt?.close();

    super.dispose();
  }

  // ── Controls ───────────────────────────────────────────────────────

  /// Shows the controls and starts the countdown to hiding them.
  ///
  /// Not while paused. Controls that vanish over a paused video leave
  /// a still frame with no way to start it again that anybody can
  /// see, which is the single most annoying thing a player can do.
  void _revealControls() {
    if (!mounted) return;

    setState(() {
      _showControls = true;
      _shownAt = DateTime.now();
    });
  }

  /// Hides them once they have been up long enough.
  ///
  /// Called from the position tick, which only arrives while something
  /// is playing - so a PAUSED video keeps its controls without any
  /// special case. That is deliberate: controls that vanish over a
  /// paused video leave a still frame with no visible way to start it
  /// again.
  void _maybeHideControls() {
    if (!_showControls || _scrubbing) return;

    final shownAt = _shownAt;

    if (shownAt == null) return;

    if (DateTime.now().difference(shownAt) < _lingerFor) return;

    if (mounted) setState(() => _showControls = false);
  }

  /// A tap on the picture.
  ///
  /// Reveals when hidden, hides when shown - it does NOT play or
  /// pause. Tapping the middle of a video to pause it is the
  /// behaviour of a feed clip; a long-form player puts pause on a
  /// button, because a mis-tap while reaching for the scrubber should
  /// not stop the film.
  void _tapPicture() {
    if (_showControls) {
      setState(() => _showControls = false);

      return;
    }

    _revealControls();
  }

  void _togglePlay() {
    if (!_ready) return;

    final wasPlaying = _playing;

    unawaited(wasPlaying ? _playerPause() : _playerPlay());

    // Re-applied on resume. Playing a video_player controller resets
    // its rate to 1x on iOS, so without this the speed silently
    // reverts every time somebody pauses to read a comment.
    if (!wasPlaying && _speed != 1) {
      unawaited(_playerSpeed(_speed));
    }

    // Pausing keeps them up; playing starts the countdown again.
    _revealControls();
  }

  Future<void> _skip(int seconds) async {
    if (!_ready) return;

    final target = _position + Duration(seconds: seconds);
    final total = _total;

    await _playerSeek(total > Duration.zero && target > total ? total : target);

    _revealControls();
  }

  // ── Fullscreen ───────────────────────────────────────────────────

  /// Widens the orientation lock for as long as fullscreen is open.
  ///
  /// main.dart locks the whole app to portrait, which is right for a
  /// feed and wrong for a film. [_restorePortrait] puts it back.
  ///
  /// A portrait video gets portraitUp ONLY rather than "whatever you
  /// like": allowing both would flip a Short into landscape the moment
  /// somebody tilts the phone, which is the one thing nobody wants
  /// while watching one.
  Future<void> _allowFullscreenOrientation() async {
    await SystemChrome.setPreferredOrientations(
      _prefersPortrait
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );

    // Sticky rather than plain immersive: a swipe at the edge brings
    // the bars back for a moment and they go away again by
    // themselves. Plain immersive gives them back permanently on the
    // first accidental swipe, which leaves a status bar sitting over
    // the video for the rest of the film.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Puts the orientation and the system bars back as the app had them.
  Future<void> _restorePortrait() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // ── manual WITH EVERY OVERLAY, NOT edgeToEdge ────────────────
    //
    // The first attempt restored edgeToEdge here, which was a guess
    // and the wrong one - it is why the UI was broken after coming
    // out of fullscreen.
    //
    // main.dart never calls setEnabledSystemUIMode at all, so the app
    // runs in the platform default: bars visible, content laid out
    // BELOW them. edgeToEdge draws content UNDER both bars instead,
    // and because this call is global it did that to every screen in
    // the app from the first time anybody opened fullscreen until the
    // app was killed.
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  /// Waits for the window to actually finish turning.
  ///
  /// setPreferredOrientations completes when the PLATFORM has been
  /// told, not when the device has turned - the rotation and its
  /// animation take a few hundred milliseconds more. Anything that
  /// lays itself out in that gap measures the old screen.
  ///
  /// The window is read straight from the platform dispatcher rather
  /// than from MediaQuery, deliberately: MediaQuery is the value this
  /// widget tree has been GIVEN, which during the gap is exactly the
  /// stale one being waited out.
  ///
  /// It gives up after 700ms and lets the caller carry on. A tablet,
  /// a foldable or a desktop window may never turn at all, and a
  /// fullscreen button that does nothing until a timer expires would
  /// be a worse bug than the one this fixes - the backstop in
  /// [didChangeMetrics] covers the late arrival either way.
  Future<void> _settleOrientation({required bool portrait}) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final deadline = DateTime.now().add(const Duration(milliseconds: 700));

    while (mounted && DateTime.now().isBefore(deadline)) {
      final size = view.physicalSize;

      // A zero size means the window is not currently measurable -
      // mid-configuration-change on Android. There is nothing to
      // compare against, so stop rather than spin for the full 700ms.
      if (size.isEmpty) return;

      if ((size.width < size.height) == portrait) return;

      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _toggleFullscreen() async {
    // ── THE EMBED'S OWN FULLSCREEN ───────────────────────────────
    //
    // lock: false because the rotation is OURS - the package's lock
    // flag only tells its own didChangeMetrics handler whether it may
    // react, and that handler is off anyway (autoFullScreen: false).
    if (_isYoutube) {
      final controller = _yt;

      if (controller == null) return;

      if (_fullscreen) {
        // Out first, turn after. The listener restores the
        // orientation, and the inline layout is the one the page was
        // already laid out for, so there is nothing to wait for.
        controller.exitFullScreen(lock: false);
      } else {
        // ── TURN FIRST, EXPAND SECOND ────────────────────────────
        //
        // The package computes its fullscreen rectangle from the
        // screen size at the moment fullscreen is switched on. Doing
        // that first and rotating afterwards means it measures the
        // portrait screen and then has to be corrected; doing it in
        // this order means it is only ever measured once, against the
        // screen it will actually be shown on.
        //
        // The listener calls this again when the flag flips. It is
        // the same two platform calls with the same arguments, so the
        // second pair are no-ops - worth it to keep every route into
        // fullscreen ending up in the same state.
        await _allowFullscreenOrientation();
        await _settleOrientation(portrait: _prefersPortrait);

        if (!mounted) return;

        controller.enterFullScreen(lock: false);
      }

      _revealControls();

      return;
    }

    if (_fullscreen) {
      await _restorePortrait();
    } else {
      await _allowFullscreenOrientation();
    }

    if (!mounted) return;

    // The Cloudflare picture is an AspectRatio inside this screen's
    // own tree, so it has no stale rectangle to correct - it simply
    // lays out against whatever the screen turns out to be. No
    // settle needed here.
    setState(() => _fullscreen = !_fullscreen);
    _revealControls();
  }

  Future<void> _restart() async {
    if (!_ready) return;

    await WatchProgress.clear(_video.postId);
    await _playerSeek(Duration.zero);

    if (mounted) setState(() => _resumedFrom = null);

    await _playerPlay();
  }

  Future<void> _like() async {
    // Optimistic: the count moves on the tap. A like that waits for a
    // round trip reads as a button that did not work.
    final wasLiked = _video.liked;

    setState(() {
      _video = _video.copyWith(
        liked: !wasLiked,
        likeCount: _video.likeCount + (wasLiked ? -1 : 1),
      );
    });

    final result = await InteractionsAPI.maybeLikePost(_video.postId);

    if (!mounted) return;

    // Put it back if the server disagreed.
    if (result == null) {
      setState(() {
        _video = _video.copyWith(
          liked: wasLiked,
          likeCount: widget.video.likeCount,
        );
      });
    }
  }

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => CommentsBottomSheet(
          scrollController: scrollController,
          postId: _video.postId,
        ),
      ),
      // They may have added one. Re-read so the preview and the count
      // match what they just did rather than what was true when the
      // screen opened.
    ).whenComplete(() {
      if (mounted) unawaited(_loadComments());
    });
  }

  // ── Drawing ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Light icons in the status bar. Without this the app's own theme
    // decides, and dark-on-dark leaves the clock and the battery
    // invisible against #111111 - its own version of the same
    // complaint.
    final theme = Provider.of<ThemeProvider>(context);

    // Nothing but the picture. The embed does NOT come through here -
    // its fullscreen is an overlay the package raises over this whole
    // tree, so for YouTube the page below carries on existing,
    // unseen, behind an opaque black fill.
    if (_fullscreen && !_isYoutube) return _cloudflareFullscreen();

    // ── THE PAGE FOLLOWS THE APP. THE STAGE NEVER DOES. ───────────
    //
    // Everything below the video takes its colours from
    // ThemeProvider, like the rest of DriveLife - so this screen is
    // white today and correct on the day the dark-mode switch is
    // turned on, with nothing further to do here.
    //
    // The video stage stays BLACK whatever the theme is, and that is
    // not an oversight. Letterbox bars are black in every player
    // there has ever been, because black is what reads as "no
    // picture" rather than as part of the page. White bars around a
    // video look like a rendering fault.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        // Follows the theme now. Light icons were right over a black
        // page and are invisible over a white one.
        statusBarIconBrightness: theme.isDarkMode
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: theme.isDarkMode
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: _header(theme),
        // ── NO APP BAR ────────────────────────────────────────────────
        //
        // It cost a whole toolbar's height above the picture, which
        // pushed the controls below the fold - so the first thing
        // somebody had to do to work out how to play a video was
        // scroll. On a screen whose entire job is one video, that is
        // the wrong thing to spend the top of the screen on.
        //
        // Back is still there twice over: the swipe gesture, which iOS
        // gives us for free on a pushed route, and the chevron drawn
        // over the picture with the rest of the controls.
        // ── INSIDE THE SAFE AREA ──────────────────────────────────────
        //
        // Taking the app bar away left nothing holding the picture
        // clear of the status bar, so the top of every video ran under
        // the clock and the battery.
        //
        // Full-bleed under the status bar is a real pattern - YouTube
        // does it - but only when the player owns the whole screen and
        // the chrome fades with the controls. This one scrolls, with a
        // title and comments beneath, so the picture has a top edge and
        // a bottom edge and both belong on screen.
        // SafeArea no longer wraps the top: the header is an AppBar now
        // and insets itself. Wrapping both would inset twice and leave
        // a status bar's worth of gap above the title.
        body: SafeArea(
          top: false,
          // ── THE PICTURE STAYS PUT ──────────────────────────────────
          //
          // A ListView with the stage as its first child let the video
          // scroll off the top, and for the YouTube embed that is not
          // just a shame - it PAUSES.
          //
          // The embed is a WebView hoisted into an overlay and
          // positioned against a placeholder through a LayerLink. When
          // the placeholder leaves the screen the link stops being
          // composited, the overlay hides its child, and an Android
          // platform view that is not being drawn gets suspended -
          // which YouTube reports as a pause. The package knows this
          // shape of problem: there is a comment in it about a
          // "spurious pause from WebView relayout".
          //
          // Pinning the stage means it never leaves, so there is
          // nothing to suspend. It is what every video app does, and it
          // is better for the Cloudflare player too - the description
          // and the comments scroll UNDER the video now rather than
          // pushing it away.
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _StageHeader(
                  height: _stageHeight(context),
                  child: _stage(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── ONE TITLE, NOT TWO ──────────────────────────
                      //
                      // There was a large heading here AND the title
                      // again inside the artwork row underneath it. The
                      // heading is gone: the artwork row already carries
                      // the title, the channel and the view count in the
                      // space the heading alone was using.
                      _authorRow(),
                      if (_video.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        // ── CLIPPED, BECAUSE OF WHERE THESE COME FROM ──
                        //
                        // A DriveLife upload's description is a line or
                        // two, typed by whoever uploaded it. A video
                        // pulled from a channel carries YOUTUBE's
                        // description - which is chapter timestamps,
                        // affiliate links, social handles and a sponsor
                        // read, and can run to hundreds of lines.
                        //
                        // Unclipped, that pushed the scrubber, the
                        // transport row and the comments so far down the
                        // page that the controls for the video were
                        // somewhere below the sponsor's discount code.
                        ExpandableText(
                          _video.description,
                          maxLines: 3,
                          style: TextStyle(
                            color: theme.subtextColor,
                            fontSize: 14,
                            height: 1.45,
                          ),
                          toggleStyle: TextStyle(
                            color: theme.textColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                          // The brand gold, which is what every other
                          // tappable thing in the app is.
                          linkStyle: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // The scrubber stays below the video. It needs room
                      // to be dragged accurately and a thin bar over a
                      // moving picture is hard to hit; the transport
                      // buttons moved onto the picture instead.
                      _scrubber(),
                      const SizedBox(height: 2),
                      _transportRow(theme),
                      // Where they came back in, and a way not to.
                      //
                      // Start again lost its home when the social row
                      // went; this is where it belonged all along, next
                      // to the sentence it answers.
                      if (_resumedFrom != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Resumed from '
                                '${LongVideo.formatPosition(_resumedFrom!)}',
                                style: TextStyle(
                                  color: theme.subtextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _restart,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Start again',
                                  style: TextStyle(
                                    color: theme.subtextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _commentsSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The bar above the picture.
  ///
  /// ── A CHEVRON DOWN, NOT AN ARROW BACK ───────────────────────────
  ///
  /// Because this screen is a thing that was opened over the app
  /// rather than a place you navigated into, and down is where it
  /// goes when it closes. Every player people already use says the
  /// same thing with the same glyph.
  ///
  /// The title is the SHOW, not the episode - the episode is already
  /// under the video in full. Up here it would be truncated to
  /// nothing on anything but the shortest name.
  PreferredSizeWidget _header(ThemeProvider theme) {
    return AppBar(
      backgroundColor: theme.backgroundColor,
      surfaceTintColor: theme.backgroundColor,
      foregroundColor: theme.textColor,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        iconSize: 30,
        tooltip: 'Close',
      ),
      title: Text(
        _video.authorName.isEmpty ? 'DriveLife' : _video.authorName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.textColor,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        // One overflow rather than a row of icons. Delete is the only
        // thing in it today and it is admin-only, so for most people
        // this is an empty menu - which is why it is hidden entirely
        // rather than opening onto nothing.
        if (_canDelete)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'delete') _confirmDelete();
              if (value == 'edit') _edit();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit details')),
              PopupMenuItem(value: 'delete', child: Text('Delete video')),
            ],
          ),
      ],
    );
  }

  /// Speed, skip, play, skip, playlist.
  ///
  /// ── ALWAYS ON SCREEN, UNLIKE THE OVERLAY ────────────────────────
  ///
  /// The overlay over the picture stays - it is what a tap on the
  /// video reveals, and it is the right thing when somebody is
  /// watching rather than reading. This row is the other half: the
  /// controls that should be reachable without touching the picture
  /// at all, in the place every player puts them.
  ///
  /// Five slots, evenly spread, with play twice the size of the rest.
  /// That weighting is the whole reason the row reads at a glance.
  Widget _transportRow(ThemeProvider theme) {
    final playing = _playing;
    final ready = _ready;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Speed, as a label rather than an icon, because the value IS
        // the information.
        SizedBox(
          width: 52,
          child: TextButton(
            onPressed: ready ? _cycleSpeed : null,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: theme.textColor,
            ),
            child: Text(
              _speedLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                // Marked when it is not 1x, so somebody who left it
                // at 2x three videos ago can see why everything
                // sounds odd.
                color: _speed == 1 ? theme.textColor : const Color(0xFFAE9159),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: ready ? () => _skip(-15) : null,
          icon: const Icon(Icons.replay_10_rounded),
          iconSize: 32,
          color: theme.textColor,
          tooltip: 'Back 15 seconds',
        ),
        Material(
          color: theme.textColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: ready ? _togglePlay : null,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 34,
                color: theme.backgroundColor,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: ready ? () => _skip(15) : null,
          icon: const Icon(Icons.forward_10_rounded),
          iconSize: 32,
          color: theme.textColor,
          tooltip: 'Forward 15 seconds',
        ),
        // ── NOTHING HERE, AND THAT IS DELIBERATE ────────────────
        //
        // This slot held "add to a playlist". Filing a video is the
        // uploader's job now, done once when it is published, rather
        // than something every viewer does to their own copy - so
        // there is nothing for a viewer to press.
        //
        // A fullscreen button lived here for a while and was taken
        // out again: between the device rotation, the system bars and
        // a WebView being re-laid-out mid-playback it was never
        // reliable, and an unreliable mode switch is worse than no
        // mode switch.
        //
        // The space is kept rather than removed. Without it the play
        // button stops being the centre of the row, and a transport
        // row whose play button is off-centre reads as broken even
        // when nobody can say why.
        const SizedBox(width: 52),
      ],
    );
  }

  /// How tall the picture is, for either player.
  ///
  /// Lifted out of the stage because the pinned header has to know it
  /// before it builds its child - a sliver declares its extent, it
  /// does not discover it.
  ///
  /// The cap is 62% of the screen either way, so the controls under a
  /// tall video are never pushed off the bottom.
  double _stageHeight(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final controller = _controller;

    // 16:9 for the embed always - the iframe API never reports a
    // video's real shape. For Cloudflare, the video's own ratio once
    // it is known, and 16:9 until then so the poster frame does not
    // sit in a box of the wrong shape and jump.
    final ratio = _isYoutube || controller == null
        ? _declaredRatio
        : (controller.value.isInitialized
              ? _pictureRatio(controller)
              : _declaredRatio);

    return (screen.width / ratio).clamp(0.0, screen.height * 0.62);
  }

  /// The shape to lay out for before the video's own shape is known.
  ///
  /// ── WHY A SHORT CANNOT USE 16:9 ────────────────────────────────
  ///
  /// This used to be a flat 16 / 9, which is right for everything the
  /// iframe API will not tell us about - and wrong for the one thing
  /// the SERVER already told us about.
  ///
  /// A Short declared as 16:9 gets a 16:9 iframe, and YouTube then
  /// pillarboxes the portrait video inside it: the picture ends up a
  /// narrow strip down the middle of a letterboxed box, which is
  /// about a fifth of the stage doing any work. Declaring 9:16
  /// instead gives the strip the full height of the stage, inline and
  /// in fullscreen both.
  double get _declaredRatio => _video.isShort ? 9 / 16 : 16 / 9;

  /// The shape of the picture, guarded.
  ///
  /// aspectRatio is 0 or NaN for a controller that initialised without
  /// a usable track, and laying out against that throws.
  double _pictureRatio(VideoPlayerController controller) {
    final ratio = controller.value.aspectRatio;

    return ratio > 0 && ratio.isFinite ? ratio : 16 / 9;
  }

  /// The picture itself, sized to fill as much of its box as its own
  /// shape allows.
  ///
  /// ── WHY THIS IS NOT A FittedBox ────────────────────────────────
  ///
  /// It was: a FittedBox with BoxFit.contain around a SizedBox of the
  /// video's pixel dimensions. That scales down and never scales UP.
  ///
  /// RenderFittedBox sizes ITSELF to constraints.constrain(childSize),
  /// and Center hands it LOOSE constraints - so when the child's
  /// natural size is smaller than the space available, the FittedBox
  /// simply takes the child's size and the scale factor comes out as
  /// 1. The video then renders at its raw size, centred, with black
  /// all round it.
  ///
  /// Which is not hypothetical: an adaptive HLS stream reports the
  /// size of the rendition it is CURRENTLY playing, so the first
  /// seconds of any video on a slow connection are a small track, and
  /// on a tablet the stage is big enough that nothing clamps it back
  /// into shape.
  ///
  /// AspectRatio has no such behaviour: given loose constraints it
  /// takes the largest size that satisfies the ratio, which is the
  /// thing that was wanted all along. VideoPlayer is a texture and
  /// fills whatever box it is handed, so the ratio is the only input
  /// needed and value.size is not read at all.
  Widget _picture(VideoPlayerController controller) {
    return Center(
      child: AspectRatio(
        // The whole picture, never cropped. A video is somebody's
        // framing and cutting the edges off it to fill a box is the
        // one thing not to do here.
        aspectRatio: _pictureRatio(controller),
        child: VideoPlayer(controller),
      ),
    );
  }

  /// The video, or whatever stands in for it.
  Widget _stage() {
    if (_isYoutube) return _youtubeStage();

    final controller = _controller;

    // ── ONE HEIGHT, WHATEVER SHAPE THE VIDEO IS ──────────────────
    //
    // It used to take its height from the video's own aspect ratio,
    // so the page jumped between videos and a portrait clip pushed
    // everything below it off the screen.
    //
    // Now the stage is a fixed box and the picture is fitted inside
    // it:
    //
    //   * A wide video letterboxes - black above and below, which is
    //     what every player does and what reads as correct.
    //   * A tall video gets the full height and a narrower width,
    //     pillarboxed at the sides.
    //
    // The height depends only on the SCREEN, never on the video, so
    // it is identical for every video on a given device. That is the
    // whole point: the controls underneath sit in the same place
    // every time.

    // ── A CAP, NOT A FIXED HEIGHT ────────────────────────────────
    //
    // It used to be a fixed box, and a landscape video fitted inside
    // it left a band of empty page underneath - which is what the
    // white gap under a 16:9 clip was.
    //
    // So the stage now takes the height the VIDEO needs at full
    // width, and only stops growing when it reaches the cap. A wide
    // video is exactly as tall as it has to be, with nothing under
    // it; a tall one fills the cap and narrows instead.
    //
    // The cost is that the controls no longer sit at the same height
    // for every video. That was worth having while the alternative
    // was letterboxing; it is not worth a screen of blank page.
    final stageHeight = _stageHeight(context);

    return Container(
      height: stageHeight,
      width: double.infinity,
      // Black behind the picture, not the page colour. Only a video
      // taller than the cap shows any of it now - pillarboxed at the
      // sides - and bars around a video are black in every player
      // there has ever been.
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The thumbnail sits underneath the whole time. While the
          // video loads it is the poster frame; once it plays it is
          // never seen. The alternative is a black rectangle, which
          // reads as broken on a slow connection.
          if (_video.thumbnailUrl.isNotEmpty)
            // contain, not cover: it stands in for the video, and a
            // poster that fills the box then gives way to a
            // letterboxed picture is a visible jump on every open.
            CachedNetworkImage(
              imageUrl: _video.thumbnailUrl,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF1C1C1C)),
            )
          else
            const ColoredBox(color: Color(0xFF1C1C1C)),

          if (controller != null && controller.value.isInitialized)
            _picture(controller),

          if (_preparing)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          if (_error != null)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),

          // Tap anywhere to show or hide the controls.
          if (controller != null && _error == null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tapPicture,
              ),
            ),

          // Everything the player needs, over the picture, YouTube
          // fashion. Fades rather than appearing, so it reads as the
          // same surface rather than a new screen.
          if (_error == null)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _overlay(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The embed, and our controls over it.
  ///
  /// ── WHY THIS IS NOT THE STAGE ABOVE ──────────────────────────────
  ///
  /// Two reasons, both about who owns the picture.
  ///
  /// The height. The Cloudflare stage measures the video and sizes
  /// itself to it, so a portrait clip gets height and a wide one has
  /// no empty page underneath. The iframe API never reports a video's
  /// native dimensions, and the aspect ratio has to be declared before
  /// the video loads, so there is nothing to measure. 16:9 it is,
  /// capped the same way, with YouTube fitting the picture inside it.
  ///
  /// The poster frame. The Cloudflare stage draws the thumbnail
  /// underneath the video the whole time, which on a slow connection
  /// is the difference between a poster and a black rectangle. Here it
  /// would be drawn OVER the video: on mobile the WebView lives in an
  /// OverlayPortal and the builder's widgets are rendered into that
  /// same overlay, above it. So there is no poster here - the embed
  /// shows YouTube's own until it starts, which is the same picture.
  Widget _youtubeStage() {
    final controller = _yt;
    final height = _stageHeight(context);

    if (controller == null || _error != null) {
      return Container(
        height: height,
        width: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              )
            : const CircularProgressIndicator(color: Colors.white),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: YoutubePlayer(
        controller: controller,
        // The video's own ratio, not the box's. The SizedBox above
        // caps the height, and on the rare screen where the cap bites
        // the player pillarboxes inside it, which is correct.
        //
        // This is also what the package lays fullscreen out against,
        // so a Short has to declare 9:16 - see _declaredRatio.
        aspectRatio: _declaredRatio,
        // ── NO FULLSCREEN, INCLUDING BY ACCIDENT ─────────────────
        //
        // Both of these default to TRUE, which was a loose end left
        // by taking the fullscreen feature out: a vertical drag on
        // the picture still put the package into ITS fullscreen, and
        // the button that used to come back out of it is gone.
        //
        // autoFullScreen does the same on rotation. The app is locked
        // to portrait so it cannot fire today, which is exactly the
        // kind of thing that stops being true later.
        enableFullScreenOnVerticalDrag: false,
        autoFullScreen: false,
        // Ours, not YouTube's. Supplying this is also what makes the
        // package pass showControls: false and put these widgets in
        // the overlay ABOVE the WebView, which is the only place a
        // Flutter widget reliably draws over a platform view.
        builder: (context, player, _) => Stack(
          fit: StackFit.expand,
          children: [
            // On mobile this stands in for the WebView underneath. It
            // is kept so the desktop and web paths, where it is the
            // real player, lay out from this same code.
            player,

            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tapPicture,
              ),
            ),

            if (_ytState == PlayerState.buffering ||
                _ytState == PlayerState.unStarted)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _overlay(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The controls drawn on top of the video.
  Widget _overlay() {
    final playing = _playing;
    final ready = _ready;

    return Container(
      // A scrim, not a flat wash: the middle of the picture stays
      // visible and the edges darken enough for white icons to read
      // against a bright frame.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.black54],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          // No back button here any more. There is a header above the
          // picture now, with the chevron in it, and two ways to
          // leave a screen four points apart is one too many.

          // Rewind, play, forward - centred, and big enough to hit
          // without looking.
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _overlayButton(
                  Icons.replay_10_rounded,
                  34,
                  ready ? () => _skip(-15) : null,
                ),
                const SizedBox(width: 26),
                _overlayButton(
                  playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  64,
                  ready ? _togglePlay : null,
                ),
                const SizedBox(width: 26),
                _overlayButton(
                  Icons.forward_10_rounded,
                  34,
                  ready ? () => _skip(15) : null,
                ),
              ],
            ),
          ),

          // ── THE WAY IN AND THE WAY OUT ──────────────────────────
          //
          // Top right in fullscreen, so the bottom edge belongs to
          // the scrubber; bottom right inline, where every player
          // puts it and where there is nothing else.
          //
          // Positioned.fill + SafeArea(minimum:) rather than
          // Positioned(right:, bottom:). The first attempt used
          // right: 2, bottom: 0, which put half of a 44-point target
          // off the screen and made the one control that comes BACK
          // out of fullscreen the hardest thing on the screen to hit.
          // The inset is now a floor the notch and the gesture bar
          // can only widen.
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(8),
              child: Align(
                alignment: _fullscreen
                    ? Alignment.topRight
                    : Alignment.bottomRight,
                child: _overlayButton(
                  _fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  30,
                  _toggleFullscreen,
                ),
              ),
            ),
          ),

          // ── THE SCRUBBER COMES ONTO THE PICTURE, BUT ONLY HERE ──
          //
          // Inline it stays below the video: a thin bar over a moving
          // picture is hard to hit, and there is a whole page under
          // the stage to put it on.
          //
          // In fullscreen that page is not on screen, so without this
          // there is no way to see where you are or to move - which
          // would make fullscreen a downgrade for everything except
          // looking at it.
          if (_fullscreen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: _scrubber(onDark: true),
              ),
            ),
        ],
      ),
    );
  }

  /// The Cloudflare picture, with the screen to itself.
  ///
  /// ── A TREE, NOT A ROUTE ────────────────────────────────────────
  ///
  /// This replaces what [build] returns rather than pushing a second
  /// screen. The controller is the same object either way, and
  /// [VideoPlayer] is a texture - so the picture is reparented
  /// without a reload, and there is exactly one copy of the position,
  /// the controls and the scrubber, which cannot drift out of step
  /// with a copy that does not exist.
  Widget _cloudflareFullscreen() {
    final controller = _controller;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light icons, unconditionally. The bars are hidden by
      // immersiveSticky, but a swipe brings them back over a black
      // picture for a few seconds and dark-on-black is invisible.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        // Back comes OUT of fullscreen rather than off the screen.
        // Both Android's back gesture and iOS's swipe would otherwise
        // pop the whole route, which would leave the app in landscape
        // with its bars hidden on a feed that is laid out for
        // portrait.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_toggleFullscreen());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),

              // AspectRatio, not FittedBox - see the note on
              // _picture. This is the case that bug was worst in: the
              // whole screen is loose space for a FittedBox to
              // decline to use, which is exactly how a fullscreen
              // video ended up a small rectangle in the middle of a
              // black screen.
              if (controller != null && controller.value.isInitialized)
                _picture(controller),

              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tapPicture,
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: _overlay(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlayButton(IconData icon, double size, VoidCallback? onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: size,
      color: Colors.white,
      // Shadow rather than a plate behind each button: it keeps the
      // picture visible and still reads against a white frame.
      style: IconButton.styleFrom(shadowColor: Colors.black, elevation: 6),
    );
  }

  /// The bar and the two time labels.
  ///
  /// [onDark] is for the fullscreen copy, which sits on the picture
  /// rather than on the page. The theme colours are chosen to read
  /// against the page and the page is not there - textColor on a
  /// dark frame is a bar you cannot see.
  Widget _scrubber({bool onDark = false}) {
    final theme = Provider.of<ThemeProvider>(context);

    final active = onDark ? Colors.white : theme.textColor;
    final inactive = onDark ? Colors.white30 : theme.dividerColor;
    final label = onDark ? Colors.white70 : theme.subtextColor;

    final total = _total.inSeconds;

    // While dragging the embed, the label follows the finger rather
    // than the player - because the player is not being moved until
    // the finger lifts. See onChanged below.
    final position = _scrubbing && _isYoutube
        ? _scrubTo.round()
        : _position.inSeconds;

    final usable = total > 0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: active,
            inactiveTrackColor: inactive,
            thumbColor: active,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: usable ? position.clamp(0, total).toDouble() : 0,
            max: usable ? total.toDouble() : 1,
            // Dragging must not fight the position listener redrawing
            // underneath it, so ticks stop repainting while scrubbing.
            onChangeStart: usable
                ? (value) => setState(() {
                    _scrubbing = true;
                    _scrubTo = value;
                  })
                : null,
            // ── ONE SEEKS AS YOU DRAG, ONE SEEKS WHEN YOU LET GO ──
            //
            // Seeking on every frame of the drag is right for
            // video_player: the file is local to the decoder and the
            // picture follows the finger.
            //
            // It is wrong for the embed. Each seek is a call across a
            // JavaScript bridge into the iframe player, and firing one
            // per pixel makes it stutter and sometimes drop the last
            // one - which leaves the video somewhere other than where
            // the finger stopped. So the drag only moves the label,
            // and the seek happens once, on release.
            onChanged: usable
                ? (value) => setState(() {
                    _scrubTo = value;

                    if (!_isYoutube) {
                      unawaited(_playerSeek(Duration(seconds: value.round())));
                    }
                  })
                : null,
            onChangeEnd: usable
                ? (value) async {
                    if (_isYoutube) {
                      await _playerSeek(Duration(seconds: value.round()));
                    }

                    if (mounted) setState(() => _scrubbing = false);

                    // Restart the clock, so the controls do not
                    // disappear the instant the finger lifts, and do
                    // not linger forever either.
                    _revealControls();
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LongVideo.formatPosition(position),
                style: TextStyle(color: label, fontSize: 12),
              ),
              Text(
                // Counts down, like every player people already use.
                usable ? '-${LongVideo.formatPosition(total - position)}' : '',
                style: TextStyle(color: label, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Artwork, title and who it is by - the podcast-player row.
  Widget _authorRow() {
    final theme = Provider.of<ThemeProvider>(context);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 46,
            height: 46,
            child: _video.thumbnailUrl.isEmpty
                ? ColoredBox(color: theme.dividerColor)
                : CachedNetworkImage(
                    imageUrl: _video.thumbnailUrl,
                    fit: BoxFit.cover,
                    // Decoded at the size drawn. A full-resolution
                    // poster frame for a 46-point square is megabytes
                    // of memory for nothing.
                    memCacheWidth: 140,
                    errorWidget: (_, __, ___) =>
                        ColoredBox(color: theme.dividerColor),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  _video.authorName.isEmpty ? 'DriveLife' : _video.authorName,
                  // Only once there are any. "0 views" on a video
                  // published an hour ago reads as a verdict on it.
                  if (_video.viewLabel.isNotEmpty) _video.viewLabel,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.subtextColor, fontSize: 13),
              ),
            ],
          ),
        ),
        // ── THE LIKE, BESIDE THE TITLE ──────────────────────────
        //
        // It was in a row of its own under the controls, with a
        // comment icon next to it. The comment icon is gone: it did
        // the same job as "Show all (3)" directly below it, and two
        // controls that open the same sheet is one too many.
        //
        // The like has no such twin, so it moves up here where the
        // thing it applies to is.
        InkWell(
          onTap: _like,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  _video.liked
                      ? 'assets/svgs/heart_full.svg'
                      : 'assets/svgs/heart.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    _video.liked ? Colors.red : theme.textColor,
                    BlendMode.srcIn,
                  ),
                ),
                if (_video.likeCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${_video.likeCount}',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The first few comments, in place, with a way to open the rest.
  ///
  /// ── WHY ANY OF THEM ARE HERE AT ALL ─────────────────────────────
  ///
  /// A comment button with a number on it tells somebody there is a
  /// conversation and makes them tap to find out whether it is worth
  /// reading. Two comments in place answer that question for free,
  /// and they are the reason people open the sheet when it IS worth
  /// reading.
  Widget _commentsSection() {
    final theme = Provider.of<ThemeProvider>(context);

    final total = _comments.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Comments',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (total > 0)
              TextButton(
                onPressed: _openComments,
                child: Text(
                  'Show all ($total)',
                  style: const TextStyle(
                    color: Color(0xFFAE9159),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (_loadingComments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Loading…',
              style: TextStyle(color: theme.subtextColor, fontSize: 13),
            ),
          )
        else if (total == 0)
          // An invitation, not an empty state. "No comments" is a
          // statement; this is a prompt, and on a brand new video the
          // difference is whether anybody starts.
          InkWell(
            onTap: _openComments,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No comments yet. Be the first.',
                style: TextStyle(color: theme.subtextColor, fontSize: 13.5),
              ),
            ),
          )
        else
          // Two, and then the link. Enough to show the tone of the
          // conversation without turning this into the comments
          // screen, which already exists and is better at it.
          //
          // The whole block is the tap target, not just the "Show
          // all" link: somebody who has started reading a comment is
          // already trying to open the thread, and making them find
          // a small word in the corner to do it is a step for
          // nothing.
          InkWell(
            onTap: _openComments,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final comment in _comments.take(2))
                  _commentPreview(comment),
                const SizedBox(height: 10),
              ],
            ),
          ),
      ],
    );
  }

  Widget _commentPreview(dynamic comment) {
    final theme = Provider.of<ThemeProvider>(context);

    if (comment is! Map) return const SizedBox.shrink();

    final name = '${comment['display_name'] ?? comment['user_login'] ?? ''}'
        .trim();
    final text = '${comment['comment'] ?? ''}'.trim();
    final avatar = '${comment['profile_image'] ?? ''}';
    final gif = '${comment['gif_url'] ?? ''}';
    final image = '${comment['image_url'] ?? ''}';
    final when = _timeAgo('${comment['comment_date'] ?? ''}');

    final likes = int.tryParse('${comment['likes_count'] ?? 0}') ?? 0;
    final replies = comment['replies'] is List
        ? (comment['replies'] as List).length
        : 0;

    // A comment can be only a picture. Showing nothing for those made
    // the preview look like it had failed to load rather than like a
    // comment that happens to be a GIF.
    final attachment = gif.isNotEmpty ? gif : image;

    if (text.isEmpty && attachment.isEmpty) return const SizedBox.shrink();

    return Padding(
      // 14, up from 12, and the rows needed it: name, text, and a
      // line of counts is three lines of content in the space two
      // were using.
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: theme.dividerColor,
            backgroundImage: avatar.isEmpty
                ? null
                : CachedNetworkImageProvider(avatar),
            child: avatar.isEmpty
                ? Icon(Icons.person, size: 15, color: theme.subtextColor)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? 'Someone' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        when,
                        style: TextStyle(
                          color: theme.subtextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                if (attachment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  // ── A DEFINITE SIZE, DECIDED BEFORE IT LOADS ──
                  //
                  // It had a height and no width, so before the
                  // image arrived it filled the row and centred,
                  // then snapped to the picture's own width once it
                  // did. Hence the jump from middle to left.
                  //
                  // 240 wide is the comments panel's own cap, so an
                  // attachment is the same size in the preview as it
                  // is in the sheet it opens.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 240,
                        height: 160,
                        child: CachedNetworkImage(
                          imageUrl: attachment,
                          fit: BoxFit.cover,
                          // Decoded small. A preview does not need
                          // the full image, and a list of them would
                          // otherwise be the heaviest thing here.
                          memCacheWidth: 600,
                          placeholder: (_, __) =>
                              ColoredBox(color: theme.dividerColor),
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: theme.dividerColor),
                        ),
                      ),
                    ),
                  ),
                ],
                if (likes > 0 || replies > 0) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (likes > 0) ...[
                        Icon(
                          Icons.favorite_rounded,
                          size: 12,
                          color: theme.subtextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$likes',
                          style: TextStyle(
                            color: theme.subtextColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (replies > 0)
                        Text(
                          replies == 1 ? '1 reply' : '$replies replies',
                          style: TextStyle(
                            color: theme.subtextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "now", "4m", "3h", "2d" - the same shape CommentItem uses, so a
  /// comment reads the same in the preview as it does in the sheet.
  String _timeAgo(String raw) {
    if (raw.isEmpty) return '';

    final date = DateTime.tryParse(raw);

    if (date == null) return '';

    final gap = DateTime.now().difference(date);

    if (gap.inDays > 365) return '${(gap.inDays / 365).floor()}y';
    if (gap.inDays > 30) return '${(gap.inDays / 30).floor()}mo';
    if (gap.inDays > 0) return '${gap.inDays}d';
    if (gap.inHours > 0) return '${gap.inHours}h';
    if (gap.inMinutes > 0) return '${gap.inMinutes}m';

    return 'now';
  }
}

/// Holds the video at the top of the screen while the rest scrolls.
///
/// A fixed extent rather than a collapsing one: the stage is already
/// capped at 62% of the screen, and a video that shrinks as somebody
/// reads is a video they have to stop reading to watch.
class _StageHeader extends SliverPersistentHeaderDelegate {
  const _StageHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Sized explicitly. A pinned header is given its extent, but its
    // CHILD is not, and the stage fits the picture into whatever box
    // it is handed.
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(_StageHeader old) {
    // The height changes once, when a Cloudflare video reports its
    // real shape and the 16:9 guess is replaced. Returning false
    // would leave the header at the guess for good.
    //
    // The child is a new widget on every frame of playback anyway -
    // the scrubber and the overlay live in there - so this is
    // effectively always true. Comparing both keeps the contract
    // honest rather than hard-coding the answer.
    return old.height != height || old.child != child;
  }
}
