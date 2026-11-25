import 'package:drivelife/providers/video_upload_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The in-progress uploads strip for the media tab.
///
/// Modelled on the post-upload cards on the home feed: the upload
/// leaves the screen that started it and reports from here instead,
/// so nothing has to be watched.
class VideoUploadTiles extends StatelessWidget {
  const VideoUploadTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoUploadProvider>(
      builder: (context, provider, _) {
        final uploads = provider.uploads.values.toList();

        if (uploads.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            for (final upload in uploads)
              _VideoUploadTile(key: ValueKey(upload.id), upload: upload),
          ],
        );
      },
    );
  }
}

class _VideoUploadTile extends StatelessWidget {
  final VideoUpload upload;

  const _VideoUploadTile({super.key, required this.upload});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<VideoUploadProvider>();

    final (String heading, String detail) = switch (upload.stage) {
      VideoUploadStage.starting => ('Preparing', 'Getting things ready…'),
      VideoUploadStage.sending => (
        'Uploading',
        '${(upload.progress * 100).toStringAsFixed(0)}% of '
            '${_size(upload.bytes)}'
            // Only once there is an honest estimate. Nothing is
            // better than a wrong number here - see _estimate.
            '${upload.remaining == null ? '' : ' · ${_left(upload.remaining!)}'}',
      ),
      // Named rather than left as a spinner, because this is the
      // stage people think has hung. It has not, and it does not need
      // the app open.
      VideoUploadStage.processing => (
        upload.processingPct > 0
            ? 'Processing ${upload.processingPct}%'
            : 'Processing',
        'Cloudflare is encoding it. This takes a few minutes and '
            'carries on without the app.',
      ),
      VideoUploadStage.done => ('Published', 'It is on the Videos row now.'),
      VideoUploadStage.failed => (
        'Upload failed',
        upload.error ?? 'Something went wrong.',
      ),
    };

    final failed = upload.stage == VideoUploadStage.failed;
    final done = upload.stage == VideoUploadStage.done;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: failed ? const Color(0xFFFDECEC) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failed ? const Color(0xFFF3C9C9) : const Color(0xFFE6E6E6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _leading(failed, done),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upload.title.isEmpty ? heading : upload.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      upload.title.isEmpty ? detail : '$heading · $detail',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: failed
                            ? const Color(0xFFA03030)
                            : const Color(0xFF6B6B6B),
                      ),
                    ),
                  ],
                ),
              ),
              _trailing(provider, failed, done),
            ],
          ),
          if (upload.stage == VideoUploadStage.sending) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: upload.progress,
                minHeight: 5,
                backgroundColor: const Color(0xFFE6E6E6),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFAE9159)),
              ),
            ),
          ],
          if (upload.stage == VideoUploadStage.processing ||
              upload.stage == VideoUploadStage.starting) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(
                // Determinate once Cloudflare has a number, and
                // indeterminate before it does. A bar stuck at 0 for
                // the first twenty seconds reads as frozen, where a
                // sweeping one reads as working.
                value: upload.processingPct > 0
                    ? upload.processingPct / 100
                    : null,
                minHeight: 5,
                backgroundColor: const Color(0xFFE6E6E6),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFAE9159)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leading(bool failed, bool done) {
    final icon = switch (upload.stage) {
      VideoUploadStage.starting => Icons.hourglass_empty_rounded,
      VideoUploadStage.sending => Icons.cloud_upload_outlined,
      VideoUploadStage.processing => Icons.movie_filter_outlined,
      VideoUploadStage.done => Icons.check_circle_rounded,
      VideoUploadStage.failed => Icons.error_outline_rounded,
    };

    return Icon(
      icon,
      size: 22,
      color: failed
          ? const Color(0xFFA03030)
          : (done ? const Color(0xFF2E7D32) : const Color(0xFF6B6B6B)),
    );
  }

  Widget _trailing(VideoUploadProvider provider, bool failed, bool done) {
    if (failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => provider.retry(upload.id),
            child: const Text('Retry'),
          ),
          IconButton(
            onPressed: () => provider.dismiss(upload.id),
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Dismiss',
          ),
        ],
      );
    }

    if (done) {
      return IconButton(
        onPressed: () => provider.dismiss(upload.id),
        icon: const Icon(Icons.close_rounded, size: 18),
        tooltip: 'Dismiss',
      );
    }

    // Cancelling mid-upload throws away what has been sent, so it asks
    // first rather than being one mis-tap away.
    return IconButton(
      onPressed: () => provider.cancel(upload.id),
      icon: const Icon(Icons.close_rounded, size: 18),
      tooltip: 'Cancel',
    );
  }

  /// Time remaining, rounded to something a person would say.
  ///
  /// No seconds past a minute: "about 4 minutes" is as precise as
  /// this estimate deserves to sound, and "3 minutes 47 seconds"
  /// claims an accuracy it does not have.
  static String _left(Duration remaining) {
    final seconds = remaining.inSeconds;

    if (seconds < 10) return 'almost done';
    if (seconds < 60) return '${(seconds / 10).round() * 10}s left';

    final minutes = remaining.inMinutes;

    if (minutes < 60) return 'about ${minutes + 1} min left';

    final hours = remaining.inHours;

    return 'about $hours hr ${remaining.inMinutes % 60} min left';
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '';

    const units = ['B', 'KB', 'MB', 'GB'];

    var value = bytes.toDouble();
    var unit = 0;

    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }

    return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)}'
        '${units[unit]}';
  }
}
