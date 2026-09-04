import 'dart:async';
import 'dart:io';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/services/media_compressor.dart';
import 'package:drivelife/services/upload_quality_prefs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Where a single photo has got to.
enum GalleryItemStatus { pending, compressing, uploading, uploaded, failed }

/// Overall state of one gallery submission.
enum GalleryBatchStatus { uploading, completed, partial, failed }

/// One photo in a gallery batch.
///
/// Mutable on purpose: a batch of 60 rebuilds its progress many times a second,
/// and rebuilding the whole list per byte would cost more than the upload.
class GalleryUploadItem {
  final String id;
  final File file;

  GalleryItemStatus status;

  /// 0..1 for this photo alone.
  double progress;

  /// Cloudflare image id, set once the bytes have landed.
  String? mediaId;

  /// Attempts spent so far, including the one in flight.
  int attempts;

  String? error;

  GalleryUploadItem({
    required this.id,
    required this.file,
    this.status = GalleryItemStatus.pending,
    this.progress = 0,
    this.mediaId,
    this.attempts = 0,
    this.error,
  });

  bool get isDone => status == GalleryItemStatus.uploaded;
  bool get isFailed => status == GalleryItemStatus.failed;
}

/// One gallery submission — the photos a user picked for a single gallery.
class GalleryUploadBatch {
  final String id;

  /// The event or venue these photos are tagged to, or '' for a standalone
  /// gallery. A gallery is its own thing now; a tag is optional.
  final String eventId;

  final String eventTitle;

  /// What the user called this batch, or null when it came from an event's own
  /// gallery tab (which has no name field) — the server then falls back to the
  /// event's own name, because every gallery must end up with a title.
  final String? galleryName;

  /// 'event', 'venue', 'location', or 'none' for a standalone gallery.
  final String entityType;

  /// Set when the gallery is tagged to a place rather than a post. A place has
  /// no id of ours, so it is carried by name and coordinates.
  final String placeId;
  final String placeLabel;
  final double? lat;
  final double? lng;

  /// Assigned by the server when the first chunk creates the gallery, then
  /// passed back on every later chunk so they all land in the same gallery.
  int? galleryId;

  /// True once photos are tagged to an event or venue.
  bool get hasEntity =>
      eventId.isNotEmpty && entityType != 'none' && entityType != 'location';

  /// True when tagged to a map location instead.
  bool get hasPlace => entityType == 'location' && placeLabel.isNotEmpty;

  final List<GalleryUploadItem> items;

  GalleryBatchStatus status;
  String? error;

  GalleryUploadBatch({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.items,
    this.galleryName,
    this.entityType = 'event',
    this.placeId = '',
    this.placeLabel = '',
    this.lat,
    this.lng,
    this.galleryId,
    this.status = GalleryBatchStatus.uploading,
    this.error,
  });

  int get total => items.length;
  int get uploaded => items.where((i) => i.isDone).length;
  int get failed => items.where((i) => i.isFailed).length;

  /// Mean of per-photo progress, so a part-sent large photo still moves the bar.
  double get progress {
    if (items.isEmpty) return 0;
    final sum = items.fold<double>(0, (acc, i) => acc + i.progress);
    return sum / items.length;
  }

  bool get isFinished => status != GalleryBatchStatus.uploading;
}

/// Runs community-gallery uploads outside the screen that started them.
///
/// Sits above the navigator (see main.dart), so the user can leave the gallery
/// screen, browse the app, and come back — the upload keeps going. It mirrors
/// [UploadPostProvider], which already does this for posts.
///
/// What makes it survive a bad connection, which is the whole point when
/// someone is sending 60 photos from a field:
///
///  * **Per-photo, not per-batch.** Each photo is minted, uploaded and
///    registered on its own. One failure costs one photo, not the gallery.
///  * **Registered as they land.** The old code registered once at the very
///    end, so a drop-out left every uploaded image orphaned in Cloudflare —
///    paid for, attached to nothing, and re-uploaded on the next attempt.
///  * **Retries with backoff**, because a mobile connection fails transiently
///    far more often than permanently.
///  * **Bounded concurrency.** A few in flight covers the latency of minting a
///    URL without shredding a weak connection.
///
/// What it deliberately does NOT do: survive the app being killed or suspended
/// by iOS for a long stretch. That needs an OS-level background task.
class GalleryUploadProvider with ChangeNotifier {
  final Map<String, GalleryUploadBatch> _batches = {};
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  /// Photos in flight at once. Three keeps the pipe busy through the
  /// mint-URL round trip without starving any one upload on a weak connection.
  static const int _maxConcurrent = 3;

  /// Attempts per photo before it is called failed.
  static const int _maxAttempts = 3;

  /// Registration is batched slightly — one call per photo is a lot of round
  /// trips on a 60-photo gallery, and anything still unregistered is flushed
  /// when the batch ends.
  static const int _registerChunk = 5;

  /// Serialises the register calls of a batch, keyed by batch id.
  ///
  /// Uploads run concurrently, so without this two chunks could be in flight
  /// together — and since the FIRST chunk is what creates the gallery, that
  /// would create two galleries and split the photos between them.
  final Map<String, Future<void>> _registerChains = {};

  /// Bumped per batch so two ids cannot collide.
  static int _batchSeq = 0;

  /// Id for a new batch. Visible for testing.
  ///
  /// A timestamp alone is not enough: two batches started in the same
  /// microsecond would collide in [_batches], silently merging them. The
  /// sequence number makes that impossible.
  static String batchIdFor(String eventId) {
    // 'gallery' keeps the id readable for a standalone batch, which has no
    // event id to name itself after.
    final prefix = eventId.isEmpty ? 'gallery' : eventId;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_batchSeq++}';
  }

  Map<String, GalleryUploadBatch> get batches => Map.unmodifiable(_batches);

  GalleryUploadBatch? batch(String id) => _batches[id];

  bool get hasActiveUploads =>
      _batches.values.any((b) => b.status == GalleryBatchStatus.uploading);

  /// The batch to surface in the UI: the running one, else the most recent.
  GalleryUploadBatch? get currentBatch {
    if (_batches.isEmpty) return null;
    return _batches.values.firstWhere(
      (b) => b.status == GalleryBatchStatus.uploading,
      orElse: () => _batches.values.last,
    );
  }

  /// Starts a batch and returns its id immediately — the caller is expected to
  /// leave the screen rather than await this.
  String startUpload({
    String eventId = '',
    String eventTitle = '',
    required List<File> files,
    String? galleryName,
    String entityType = 'event',
    String placeId = '',
    String placeLabel = '',
    double? lat,
    double? lng,
    int? existingGalleryId,
  }) {
    final batchId = batchIdFor(eventId);

    final batch = GalleryUploadBatch(
      id: batchId,
      eventId: eventId,
      eventTitle: eventTitle,
      galleryName: galleryName,
      placeId: placeId,
      placeLabel: placeLabel,
      lat: lat,
      lng: lng,
      // Seeding the id makes every register call APPEND to that gallery
      // instead of the first one creating a new gallery — which is the whole
      // difference between adding photos and starting again.
      galleryId: existingGalleryId,
      entityType: entityType,
      items: [
        for (var i = 0; i < files.length; i++)
          GalleryUploadItem(id: '${batchId}_$i', file: files[i]),
      ],
    );

    _batches[batchId] = batch;
    notifyListeners();

    // Deliberately not awaited: the work outlives the calling screen.
    unawaited(_run(batch));

    return batchId;
  }

  /// Re-queues the failed photos in a finished batch.
  Future<void> retryFailed(String batchId) async {
    final batch = _batches[batchId];
    if (batch == null || batch.status == GalleryBatchStatus.uploading) return;

    final failed = batch.items.where((i) => i.isFailed).toList();
    if (failed.isEmpty) return;

    for (final item in failed) {
      item.status = GalleryItemStatus.pending;
      item.progress = 0;
      item.attempts = 0;
      item.error = null;
    }

    batch.status = GalleryBatchStatus.uploading;
    batch.error = null;
    notifyListeners();

    await _run(batch);
  }

  void dismiss(String batchId) {
    final batch = _batches[batchId];
    if (batch == null || !batch.isFinished) return;
    _batches.remove(batchId);
    _registerChains.remove(batchId);
    notifyListeners();
  }

  Future<void> _run(GalleryUploadBatch batch) async {
    await _initNotifications();

    final quality = await UploadQualityPrefs.current();
    final queue = batch.items.where((i) => !i.isDone).toList();
    final pendingRegistration = <String>[];

    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= queue.length) return;
        final item = queue[cursor++];

        final ok = await _processItem(batch, item, quality);

        if (ok && item.mediaId != null) {
          pendingRegistration.add(item.mediaId!);

          if (pendingRegistration.length >= _registerChunk) {
            final chunk = List<String>.from(pendingRegistration);
            pendingRegistration.clear();
            await _register(batch, chunk);
          }
        }

        _publishProgress(batch);
      }
    }

    await Future.wait([
      for (var i = 0; i < _maxConcurrent && i < queue.length; i++) worker(),
    ]);

    // Flush whatever did not fill a chunk.
    if (pendingRegistration.isNotEmpty) {
      await _register(batch, List<String>.from(pendingRegistration));
    }

    _finish(batch);
  }

  /// Compress (if the tier calls for it), upload, retry on failure.
  Future<bool> _processItem(
    GalleryUploadBatch batch,
    GalleryUploadItem item,
    UploadQuality quality,
  ) async {
    var file = item.file;

    // Same policy as posts: a low or medium quality photo is left alone, a
    // high quality one passes through when the user asked for it, and only an
    // oversized file is re-encoded — and only as far as Cloudflare requires.
    try {
      item.status = GalleryItemStatus.compressing;
      notifyListeners();

      final prepared = await MediaCompressor.compressImage(
        file,
        quality: quality,
      );
      file = prepared.file;
    } catch (e) {
      // A compressor failure is not fatal — the original may well upload.
      debugPrint('GalleryUpload: compress failed for ${item.file.path}: $e');
    }

    while (item.attempts < _maxAttempts) {
      item.attempts++;
      item.status = GalleryItemStatus.uploading;
      item.error = null;
      notifyListeners();

      try {
        final mint = await EventsAPI.createCommunityGalleryUpload();

        await EventsAPI.uploadCommunityGalleryFile(
          uploadUrl: mint.uploadUrl,
          file: file,
          onSent: (sent, total) {
            if (total <= 0) return;
            item.progress = sent / total;
            // Byte callbacks fire far faster than the UI can paint; the
            // periodic notify in the caller is what the list actually rebuilds
            // on. Only push a rebuild on meaningful movement.
            if (item.progress == 1 || (sent ~/ 1024) % 256 == 0) {
              notifyListeners();
            }
          },
        );

        item.mediaId = mint.imageId;
        item.status = GalleryItemStatus.uploaded;
        item.progress = 1;
        notifyListeners();
        return true;
      } catch (e) {
        item.error = e.toString();
        debugPrint(
          'GalleryUpload: attempt ${item.attempts} failed for '
          '${item.file.path}: $e',
        );

        if (item.attempts >= _maxAttempts) break;

        // Back off before retrying — a connection that just dropped is rarely
        // ready again immediately.
        await Future.delayed(Duration(seconds: 2 * item.attempts));
      }
    }

    item.status = GalleryItemStatus.failed;
    item.progress = 0;
    notifyListeners();
    return false;
  }

  /// Queues a chunk for registration behind any chunk already registering.
  ///
  /// Returns the chained future, so the caller still waits for its own chunk.
  Future<void> _register(GalleryUploadBatch batch, List<String> mediaIds) {
    if (mediaIds.isEmpty) return Future.value();

    final chain = (_registerChains[batch.id] ?? Future.value()).then(
      (_) => _registerNow(batch, mediaIds),
    );

    _registerChains[batch.id] = chain;
    return chain;
  }

  Future<void> _registerNow(
    GalleryUploadBatch batch,
    List<String> mediaIds,
  ) async {
    try {
      final result = await EventsAPI.registerCommunityGalleryMedia(
        // Both omitted for a standalone gallery, which is tagged to nothing.
        eventId: batch.hasEntity ? batch.eventId : null,
        entityType: (batch.hasEntity || batch.hasPlace)
            ? batch.entityType
            : null,
        mediaIds: mediaIds,
        galleryName: batch.galleryName,
        galleryId: batch.galleryId,
        placeId: batch.placeId,
        placeLabel: batch.placeLabel,
        lat: batch.lat,
        lng: batch.lng,
      );

      // The first chunk creates the gallery; hold its id for the rest.
      final id = result?['gallery_id'];
      if (batch.galleryId == null && id != null) {
        batch.galleryId = id is int ? id : int.tryParse('$id');
      }
    } catch (e) {
      // The bytes are safely in Cloudflare; only the attach failed. Mark the
      // photos failed so a retry re-runs them rather than reporting a success
      // the user will not see in the gallery.
      debugPrint('GalleryUpload: register failed for $mediaIds: $e');

      for (final item in batch.items) {
        if (item.mediaId != null && mediaIds.contains(item.mediaId)) {
          item.status = GalleryItemStatus.failed;
          item.error = 'Uploaded but could not be added to the gallery';
        }
      }
      notifyListeners();
    }
  }

  void _finish(GalleryUploadBatch batch) {
    // The chain is per-run; a later retry starts a fresh one.
    _registerChains.remove(batch.id);

    final failed = batch.failed;

    if (failed == 0) {
      batch.status = GalleryBatchStatus.completed;
    } else if (failed == batch.total) {
      batch.status = GalleryBatchStatus.failed;
      batch.error = 'No photos could be uploaded';
    } else {
      batch.status = GalleryBatchStatus.partial;
      batch.error = '$failed of ${batch.total} photos could not be uploaded';
    }

    notifyListeners();
    unawaited(_publishResult(batch));
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    if (_notificationsReady) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _notificationsReady = true;
  }

  int _notificationId(GalleryUploadBatch batch) =>
      batch.id.hashCode & 0x7fffffff;

  Future<void> _publishProgress(GalleryUploadBatch batch) async {
    notifyListeners();

    // iOS has no progress notification, and re-posting a banner per photo would
    // be a stream of alerts. Android gets the ongoing progress bar.
    if (!Platform.isAndroid) return;

    final percent = (batch.progress * 100).round().clamp(0, 100);

    final android = AndroidNotificationDetails(
      'gallery_upload_channel',
      'Gallery Uploads',
      channelDescription: 'Shows progress while photos upload to an event',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: percent,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );

    await _notifications.show(
      _notificationId(batch),
      'Sharing photos',
      '${batch.uploaded} of ${batch.total} uploaded',
      NotificationDetails(android: android),
    );
  }

  Future<void> _publishResult(GalleryUploadBatch batch) async {
    await _notifications.cancel(_notificationId(batch));

    final String title;
    final String body;

    switch (batch.status) {
      case GalleryBatchStatus.completed:
        title = 'Photos shared';
        body =
            '${batch.uploaded} photo${batch.uploaded == 1 ? '' : 's'} added to '
            '${batch.eventTitle}';
        break;
      case GalleryBatchStatus.partial:
        title = 'Some photos did not upload';
        body = '${batch.uploaded} of ${batch.total} added — tap to retry';
        break;
      case GalleryBatchStatus.failed:
        title = 'Photos could not be shared';
        body = 'Tap to try again';
        break;
      case GalleryBatchStatus.uploading:
        return;
    }

    await _notifications.show(
      _notificationId(batch) + 1,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gallery_upload_channel',
          'Gallery Uploads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
      ),
    );
  }
}
