import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:flutter/material.dart';

/// The last step of a gallery upload.
///
/// It used to be the tagging screen, which held the upload open while every
/// photo was read — minutes for a large gallery, and long enough that the
/// requests behind it timed out. The reading now happens on the server after
/// this screen has been and gone, so all this has to do is start it and say
/// what is happening.
class GalleryProcessingScreen extends StatefulWidget {
  final int galleryId;
  final String galleryName;

  /// Whether to clear the upload steps before opening the gallery.
  ///
  /// A new gallery is reached through the compose screen, which must not be
  /// what a back-press from the gallery lands on.
  final bool returnToRoot;

  const GalleryProcessingScreen({
    super.key,
    required this.galleryId,
    required this.galleryName,
    this.returnToRoot = true,
  });

  @override
  State<GalleryProcessingScreen> createState() =>
      _GalleryProcessingScreenState();
}

class _GalleryProcessingScreenState extends State<GalleryProcessingScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  @override
  void initState() {
    super.initState();

    // Started here rather than on the gallery screen, so processing is under
    // way before the user has decided whether to wait around for it.
    EventsAPI.processGallery(galleryId: widget.galleryId);
  }

  /// Opens the gallery, leaving nothing behind from the upload.
  ///
  /// The compose and progress screens are finished with; backing out of the
  /// gallery into a progress bar for an upload that already landed, or into a
  /// half-filled compose form, is worse than landing where you started.
  void _continue() {
    final navigator = Navigator.of(context);

    if (widget.returnToRoot) {
      navigator.popUntil((route) => route.isFirst);
      navigator.push(MaterialPageRoute(builder: (_) => _gallery()));
      return;
    }

    navigator.pushReplacement(MaterialPageRoute(builder: (_) => _gallery()));
  }

  Widget _gallery() => GalleryViewScreen(
    galleryId: widget.galleryId,
    entityTitle: widget.galleryName,
    galleryName: widget.galleryName,
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back would land on the upload progress screen for an upload that has
      // already finished. Continue is the only way on from here.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                const Spacer(),

                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 34,
                    color: _gold,
                  ),
                ),
                const SizedBox(height: 22),

                const Text(
                  'Gallery Processing',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  'Almost done! We’re analysing your images to identify users '
                  'and vehicle registrations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: _ink, height: 1.5),
                ),
                const SizedBox(height: 12),

                const Text(
                  'If we find a registration belonging to a DriveLife user, '
                  'we’ll automatically tag and notify them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: _ink, height: 1.5),
                ),
                const SizedBox(height: 12),

                const Text(
                  'You can leave this screen while the gallery is processed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _continue,
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
