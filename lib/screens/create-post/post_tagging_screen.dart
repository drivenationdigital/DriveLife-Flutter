import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/screens/create-post/post_tag_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Step 2 of posting — the upload, and nothing else.
///
/// ── WHY THERE IS NO WAY OUT ─────────────────────────────────────────
///
/// There used to be. Leaving meant the post still published, because the
/// upload runs in a provider rather than on this screen — but everything
/// that happens AFTER it was reached from here, so people left and their
/// tags were silently never found.
///
/// So this cannot be dismissed until the post exists. The back gesture
/// is blocked, there is no leading button, and Done only appears once
/// there is something to be done with.
///
/// ── AND WHY IT ENDS HERE ────────────────────────────────────────────
///
/// It used to go on to the tagging screen. It does not any more: reading
/// photos for vehicles takes several seconds each, and holding somebody
/// on a spinner for that is worse than telling them it is in hand.
///
/// Tags are applied without asking where they are safe — a venue, an
/// event — and anything naming somebody else's car is offered for review
/// in a notification. PostTagScreen is reached from that, and from Edit
/// tags on the post itself.
class PostTaggingScreen extends StatefulWidget {
  /// The background upload to follow, as passed to [UploadPostProvider].
  final String uploadId;

  const PostTaggingScreen({super.key, required this.uploadId});

  @override
  State<PostTaggingScreen> createState() => _PostTaggingScreenState();
}

class _PostTaggingScreenState extends State<PostTaggingScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);
  static const Color _goldPale = Color(0xFFEDE3D0);
  static const Color _line = Color(0xFFEDEDED);

  /// Set once the hand-off has been scheduled, so a rebuild cannot
  /// queue a second one. This screen rebuilds on every progress tick.
  bool _movingOn = false;

  /// On to tagging, once there is a post to tag.
  ///
  /// ── WHY IT PAUSES FIRST ─────────────────────────────────────────
  ///
  /// POST ADDED is the confirmation that the thing you just did worked.
  /// Advancing the instant the upload finishes means it flashes past
  /// unread, and the next screen says "checking for tags" — which does
  /// not tell you the post landed.
  ///
  /// So it is shown, briefly, and then moves on by itself. Done is there
  /// for anybody who does not want to wait out the beat.
  void _onPostReady(int postId) {
    if (_movingOn || postId <= 0) return;

    _movingOn = true;

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) _openTags(postId);
    });
  }

  void _openTags(int postId) {
    // pushReplacement: the upload this screen was reporting on is over,
    // so there is nothing to come back to.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PostTagScreen(postId: postId)),
    );
  }

  void _leave() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    // Watched rather than read: this whole screen is the upload's state.
    final upload = context.watch<UploadPostProvider>().getUpload(
      widget.uploadId,
    );

    final failed = upload?.status == UploadStatus.failed;

    // A record that has vanished from the provider is finished — it is
    // cleared on completion — so a missing one counts as done rather
    // than trapping somebody on a screen with no way forward.
    final finished =
        failed || upload == null || upload.status == UploadStatus.completed;

    final postId = int.tryParse('${upload?.result?['post_id']}') ?? 0;

    // Scheduled from build because that is where the upload's state
    // arrives — there is no callback for "finished", only a rebuild
    // with a different status. Guarded against firing twice.
    if (finished && !failed && postId > 0) {
      _onPostReady(postId);
    }

    return PopScope(
      // Leaving early is what used to lose people their tags.
      canPop: finished,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: _line)),
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: const Text(
            'New post',
            style: TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            // Only once there is a post. While it uploads there is
            // nothing to be done, and a button that does nothing is
            // worse than no button.
            if (finished)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 14, 8),
                child: FilledButton(
                  // The same place the pause leads, so tapping it skips
                  // the beat rather than taking a different route. Only
                  // a failed upload has nothing to tag, and that is the
                  // one case where Done means leave.
                  onPressed: (!failed && postId > 0)
                      ? () => _openTags(postId)
                      : _leave,
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: failed
                  ? _failedBody()
                  : finished
                  ? _addedBody()
                  : _uploadingBody(upload),
            ),
          ),
        ),
      ),
    );
  }

  /// A black disc inside a thin ring.
  ///
  /// The ring is pale while the work is going and gold once it is done,
  /// which is the whole of the difference between the two states.
  Widget _mark({required IconData icon, required bool complete}) {
    return SizedBox(
      width: 164,
      height: 164,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: complete ? _gold : _goldPale, width: 2),
            ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: const BoxDecoration(
              color: _ink,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _gold, size: 46),
          ),
        ],
      ),
    );
  }

  List<Widget> _uploadingBody(UploadPostProgress upload) {
    final total = upload.totalItems;
    final current = upload.currentItem;

    final percent = (upload.progress * 100).clamp(0, 100).round();

    return [
      _mark(icon: Icons.arrow_upward, complete: false),
      const SizedBox(height: 38),
      const DlHeading('Uploading post', fontSize: 30, color: _ink),
      const SizedBox(height: 10),
      const Text(
        'Keep the app open while we upload your photos.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 15.5, height: 1.4),
      ),
      const SizedBox(height: 34),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          // Indeterminate until there is something to report, so the bar
          // moves while the first photo is being compressed rather than
          // sitting at zero looking stuck.
          value: upload.progress <= 0 ? null : upload.progress,
          minHeight: 8,
          backgroundColor: const Color(0xFFEDEDED),
          valueColor: const AlwaysStoppedAnimation(_gold),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            // The provider counts past the last photo while the post row
            // is created, and "Photo 5 of 4" is a worse lie than a bar
            // that sits near the end for a second.
            total > 0
                ? 'Photo ${current > total ? total : current} of $total'
                : 'Preparing…',
            style: const TextStyle(
              color: _ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$percent%',
            style: const TextStyle(
              color: _ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _addedBody() {
    return [
      _mark(icon: Icons.check, complete: true),
      const SizedBox(height: 38),
      const DlHeading('Post added', fontSize: 30, color: _ink),
      const SizedBox(height: 10),
      const Text(
        "If we detect any other locations, events or vehicles in your "
        "post, we'll send you a notification to approve them.",
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 15.5, height: 1.4),
      ),
    ];
  }

  List<Widget> _failedBody() {
    return [
      _mark(icon: Icons.close, complete: false),
      const SizedBox(height: 38),
      const DlHeading('Upload failed', fontSize: 30, color: _ink),
      const SizedBox(height: 10),
      const Text(
        'Your photos did not finish uploading, so nothing was posted. '
        'You can try again from the feed.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 15.5, height: 1.4),
      ),
    ];
  }
}
