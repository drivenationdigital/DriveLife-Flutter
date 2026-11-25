import 'dart:async';
import 'dart:io';

import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/services/video_uploader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What stage one video upload is at.
enum VideoUploadStage {
  /// Asking the server for a one-time Cloudflare URL.
  starting,

  /// Bytes on the wire. The only stage with honest progress.
  sending,

  /// Cloudflare transcoding. No progress worth showing, and it
  /// continues whether the app is running or not.
  processing,

  /// Encoded and published.
  done,

  failed,
}

/// One upload in flight.
class VideoUpload {
  final String id;
  final File file;
  final String title;
  final String description;
  final int bytes;

  /// Playlists to file it into, once there is something to file.
  final List<int> playlistIds;

  final VideoUploadStage stage;

  /// 0..1 while [stage] is sending.
  final double progress;

  /// Roughly how much longer the bytes will take. Null until there is
  /// enough of a sample to say anything honest.
  final Duration? remaining;

  /// Cloudflare's own encode progress, 0..100, while processing.
  final int processingPct;

  /// The post, once the server has made one.
  final int? postId;

  /// Why it stopped, when it did.
  final String? error;

  const VideoUpload({
    required this.id,
    required this.file,
    required this.title,
    required this.description,
    required this.bytes,
    this.playlistIds = const [],
    this.stage = VideoUploadStage.starting,
    this.progress = 0,
    this.remaining,
    this.processingPct = 0,
    this.postId,
    this.error,
  });

  bool get isBusy =>
      stage == VideoUploadStage.starting ||
      stage == VideoUploadStage.sending ||
      stage == VideoUploadStage.processing;

  VideoUpload copyWith({
    VideoUploadStage? stage,
    double? progress,
    Duration? remaining,
    int? processingPct,
    int? postId,
    String? error,
  }) {
    return VideoUpload(
      id: id,
      file: file,
      title: title,
      description: description,
      bytes: bytes,
      playlistIds: playlistIds,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      remaining: remaining ?? this.remaining,
      processingPct: processingPct ?? this.processingPct,
      postId: postId ?? this.postId,
      error: error,
    );
  }
}

/// Uploads long-form videos, outliving the screen that started them.
///
/// ── WHY THIS IS A PROVIDER AND NOT PART OF THE SCREEN ───────────────
///
/// Because the upload used to live on the upload screen, and the
/// screen's dispose cancelled it. Leaving the screen - even by
/// accident, even to check something - threw away however much had
/// been sent. For a two-gigabyte video on a phone connection that is
/// potentially an hour of work.
///
/// Registered above the navigator in main.dart, like
/// [GalleryUploadProvider] and for the same reason, so an upload
/// survives navigation, tab changes and the screen being closed.
///
/// ── WHAT "BACKGROUND" HONESTLY MEANS HERE ───────────────────────────
///
/// It keeps going while the app is RUNNING, on any screen. When iOS
/// suspends the app it stops, because continuing would need a
/// URLSession background transfer and `package:http` is not one.
/// `beginBackgroundTask` buys roughly thirty seconds of grace, which
/// is enough to finish a chunk rather than abandon one mid-flight.
///
/// Then tus earns its keep: reopening the app resumes from whatever
/// Cloudflare actually received, rather than starting again. So a
/// long upload across several sessions works, it just is not
/// unattended.
class VideoUploadProvider with ChangeNotifier {
  static const MethodChannel _background = MethodChannel(
    'com.drivelife/background_task',
  );

  final Map<String, VideoUpload> _uploads = {};
  final Map<String, VideoUploader> _workers = {};

  /// When each upload's bytes started moving, for the estimate.
  final Map<String, DateTime> _startedAt = {};

  /// A smoothed bytes-per-second, per upload.
  ///
  /// ── WHY SMOOTHED AND NOT MEASURED ───────────────────────────────
  ///
  /// Progress arrives one 16MB chunk at a time, so the instantaneous
  /// rate is 16MB divided by however long that one request took -
  /// which swings wildly with signal. Reported raw, the estimate
  /// reads "4 minutes left", then "40 seconds", then "6 minutes",
  /// and stops being believed.
  ///
  /// An exponential moving average follows a real change in
  /// conditions within a few chunks while ignoring the noise between
  /// them.
  final Map<String, double> _rate = {};
  final Map<String, Timer> _polls = {};

  Map<String, VideoUpload> get uploads => Map.unmodifiable(_uploads);

  bool get hasActive => _uploads.values.any((u) => u.isBusy);

  /// Starts one, and returns immediately.
  ///
  /// The caller is expected to pop straight back to wherever they
  /// were: everything after this point is reported through the tile,
  /// not through the screen that began it.
  String start({
    required File file,
    required String title,
    String description = '',
    required int bytes,
    List<int> playlistIds = const [],
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    _uploads[id] = VideoUpload(
      id: id,
      file: file,
      title: title,
      description: description,
      bytes: bytes,
      playlistIds: playlistIds,
    );

    notifyListeners();

    unawaited(_run(id));

    return id;
  }

  Future<void> _run(String id) async {
    final upload = _uploads[id];

    if (upload == null) return;

    // Ask iOS for grace time. Released in the finally below, because
    // an unreleased background task is a watchdog kill.
    String? task;

    if (Platform.isIOS) {
      try {
        task = await _background.invokeMethod<String>('beginBackgroundTask');
      } catch (e) {
        debugPrint('[videoUpload] no background task: $e');
      }
    }

    try {
      final started = await VideosAPI.startUpload(
        title: upload.title,
        description: upload.description,
        sizeBytes: upload.bytes,
      );

      if (started == null) {
        _fail(id, 'Could not start the upload.');
        return;
      }

      _set(
        id,
        (u) => u.copyWith(
          stage: VideoUploadStage.sending,
          postId: started.postId,
        ),
      );

      final worker = VideoUploader();
      _workers[id] = worker;

      _startedAt[id] = DateTime.now();

      final sent = await worker.upload(
        file: upload.file,
        uploadUrl: started.uploadUrl,
        onProgress: (value, sentBytes, totalBytes) => _set(
          id,
          (u) => u.copyWith(
            progress: value,
            remaining: _estimate(id, sentBytes, totalBytes),
          ),
        ),
      );

      _workers.remove(id);

      if (!sent) {
        _fail(
          id,
          'The upload stopped. Trying again picks up where it left off.',
        );
        return;
      }

      _set(id, (u) => u.copyWith(stage: VideoUploadStage.processing));

      _watch(id, started.postId);
    } catch (e) {
      debugPrint('[videoUpload] $id failed: $e');

      _fail(id, 'Something went wrong with that upload.');
    } finally {
      if (task != null) {
        try {
          await _background.invokeMethod('endBackgroundTask');
        } catch (_) {}
      }
    }
  }

  /// How much longer, smoothed.
  ///
  /// Returns null rather than a guess until a few seconds have
  /// passed: the first chunk includes connection setup and is not
  /// representative, and "2 hours remaining" flashing up on a file
  /// that takes ninety seconds is worse than showing nothing.
  Duration? _estimate(String id, int sent, int total) {
    final startedAt = _startedAt[id];

    if (startedAt == null || sent <= 0) return null;

    final seconds = DateTime.now().difference(startedAt).inMilliseconds / 1000;

    if (seconds < 3) return null;

    final observed = sent / seconds;

    // 0.3 on the new reading: responsive enough to follow a genuine
    // change in signal within a handful of chunks, damped enough to
    // ignore one slow request.
    final smoothed = _rate.containsKey(id)
        ? (_rate[id]! * 0.7) + (observed * 0.3)
        : observed;

    _rate[id] = smoothed;

    if (smoothed <= 0) return null;

    final left = (total - sent) / smoothed;

    if (left.isNaN || left.isInfinite || left < 0) return null;

    return Duration(seconds: left.round());
  }

  /// Polls Cloudflare, then publishes.
  ///
  /// ── AND PUBLISHES WITHOUT ASKING ────────────────────────────────
  ///
  /// Because the person already decided. They chose the file, gave it
  /// a title and pressed Upload; coming back ten minutes later to
  /// press a second button adds nothing except a way to forget.
  ///
  /// It is reversible - unpublishing is one call - and the server
  /// refuses to publish anything Cloudflare has not finished, so this
  /// cannot put a dead card on the media tab.
  void _watch(String id, int postId) {
    _polls[id]?.cancel();

    _polls[id] = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final status = await VideosAPI.status(postId);

      if (status == null) return;

      if (status.state == 'error') {
        timer.cancel();
        _polls.remove(id);

        _fail(
          id,
          status.error.isEmpty
              ? 'Cloudflare could not process that file.'
              : status.error,
        );

        return;
      }

      // Something moving, rather than an indeterminate bar. Encoding
      // a long video takes minutes and this is the only evidence the
      // app has that anything is happening.
      _set(id, (u) => u.copyWith(processingPct: status.pct));

      if (!status.ready) return;

      timer.cancel();
      _polls.remove(id);

      final published = await VideosAPI.update(postId: postId, publish: true);

      if (!published) {
        _fail(id, 'Encoded, but could not be published. Try publishing it.');
        return;
      }

      // Into its playlists, now that it has an id and is published.
      //
      // After publishing rather than before: a playlist that holds an
      // unpublished video would show a card nobody can open.
      //
      // Failures are swallowed on purpose. The video is up and
      // playable; not being in a playlist is a tidying problem, and
      // reporting the upload as FAILED over it would be a lie.
      final upload = _uploads[id];

      for (final playlistId in upload?.playlistIds ?? const <int>[]) {
        await VideoPlaylistsAPI.setMembership(
          playlistId: playlistId,
          videoId: '$postId',
          inPlaylist: true,
        );
      }

      _set(id, (u) => u.copyWith(stage: VideoUploadStage.done));
    });
  }

  /// Takes a finished or failed upload off the list.
  void dismiss(String id) {
    _polls.remove(id)?.cancel();
    _workers.remove(id)?.cancel();
    _startedAt.remove(id);
    _rate.remove(id);
    _uploads.remove(id);

    notifyListeners();
  }

  /// Stops one that is still running.
  void cancel(String id) {
    _workers[id]?.cancel();

    dismiss(id);
  }

  /// Tries a failed one again.
  ///
  /// A fresh server call, which mints a new upload URL. The bytes
  /// already at Cloudflare under the OLD url are not reused: a failed
  /// start never had one, and a failed send has a post that can be
  /// retried from its own screen. Simpler, and it cannot resume into
  /// the wrong video.
  void retry(String id) {
    final upload = _uploads[id];

    if (upload == null) return;

    _startedAt.remove(id);
    _rate.remove(id);

    _set(
      id,
      (u) => u.copyWith(stage: VideoUploadStage.starting, progress: 0),
    );

    unawaited(_run(id));
  }

  void _set(String id, VideoUpload Function(VideoUpload) change) {
    final current = _uploads[id];

    if (current == null) return;

    _uploads[id] = change(current);

    notifyListeners();
  }

  void _fail(String id, String message) {
    _set(
      id,
      (u) => u.copyWith(stage: VideoUploadStage.failed, error: message),
    );
  }

  @override
  void dispose() {
    for (final timer in _polls.values) {
      timer.cancel();
    }

    for (final worker in _workers.values) {
      worker.cancel();
    }

    super.dispose();
  }
}
