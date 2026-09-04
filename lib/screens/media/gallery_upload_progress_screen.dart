import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:drivelife/screens/media/gallery_tagging_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Step 1.5 — the wait between picking photos and tagging them.
///
/// The upload itself already runs in [GalleryUploadProvider], outside any
/// screen, so this page does not perform the work: it watches it. That matters
/// for two reasons.
///
/// First, tagging is per-photo, and a photo has no id until its bytes are in
/// Cloudflare and the row is registered — so step 2 genuinely cannot start
/// until the upload finishes.
///
/// Second, because the provider owns the work, leaving this page does not
/// cancel anything. Someone who backs out still gets their photos; they just
/// skip tagging.
class GalleryUploadProgressScreen extends StatefulWidget {
  /// Batch to watch, as returned by [GalleryUploadProvider.startUpload].
  final String batchId;

  /// Shown on the tagging step and in the heading.
  final String galleryName;

  const GalleryUploadProgressScreen({
    super.key,
    required this.batchId,
    required this.galleryName,
  });

  @override
  State<GalleryUploadProgressScreen> createState() =>
      _GalleryUploadProgressScreenState();
}

class _GalleryUploadProgressScreenState
    extends State<GalleryUploadProgressScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);

  GalleryUploadProvider? _uploads;

  /// Guards the hand-off to step 2, which must happen exactly once. The
  /// provider notifies many times a second while bytes move.
  bool _advanced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final provider = context.read<GalleryUploadProvider>();
    if (identical(provider, _uploads)) return;

    _uploads?.removeListener(_onChanged);
    _uploads = provider..addListener(_onChanged);

    // The batch may already have finished — a handful of small photos on wifi
    // can beat this screen's first frame.
    _onChanged();
  }

  @override
  void dispose() {
    _uploads?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (_advanced || !mounted) return;

    final batch = _uploads?.batch(widget.batchId);
    if (batch == null || !batch.isFinished) return;

    // Nothing landed at all: there is nothing to tag, so say so here rather
    // than opening an empty step 2.
    if (batch.uploaded == 0) {
      setState(() {}); // Repaint into the failed state below.
      return;
    }

    _advanced = true;

    // Out of the notification callback — this runs during the provider's
    // notifyListeners, and navigating inside that is asking for trouble.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          // The gallery id comes back from the first register chunk, so it is
          // known by the time the batch finishes — which is what step 2 needs
          // to attach tags to.
          builder: (_) => GalleryTaggingScreen(
            galleryId: batch.galleryId,
            galleryName: widget.galleryName,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryUploadProvider>(
      builder: (context, provider, _) {
        final batch = provider.batch(widget.batchId);

        final total = batch?.total ?? 0;
        final done = batch?.uploaded ?? 0;
        final failed = batch?.failed ?? 0;
        final progress = batch?.progress ?? 0;
        final allFailed = batch != null && batch.isFinished && done == 0;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Uploading images',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Step 1 of 2',
                  style: TextStyle(color: _muted, fontSize: 13.5),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: Colors.grey.shade200),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allFailed ? 'Upload failed' : 'Uploading your photos',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  allFailed
                      ? 'None of your photos could be uploaded. Check your '
                            'connection and try again.'
                      : 'Keep this open and we will take you to tagging as '
                            'soon as they are in. Leaving is fine too — the '
                            'upload carries on without this screen.',
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: _muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 32),

                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: allFailed ? 0 : progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    color: allFailed ? Colors.red.shade400 : _ink,
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Text(
                      total == 0 ? 'Preparing…' : '$done of $total uploaded',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${((allFailed ? 0 : progress) * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ],
                ),

                // Partial failures are worth naming here, not silently at the
                // end: the tagging step will only cover what actually landed.
                if (failed > 0 && !allFailed) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$failed photo${failed == 1 ? '' : 's'} did not '
                            'upload. You can retry from the gallery after '
                            'publishing.',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                if (allFailed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: () => provider.retryFailed(widget.batchId),
                      child: const Text(
                        'Try again',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
