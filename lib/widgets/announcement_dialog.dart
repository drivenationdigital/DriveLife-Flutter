import 'package:drivelife/api/announcement_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

/// A one-time notice, shown over whatever the app opened on.
///
/// Dismissal is recorded on the SERVER, not the device — see
/// [AnnouncementApi] for why. The write is not awaited before closing: a
/// lost one costs this person one extra showing, and making them watch a
/// spinner to acknowledge a notice would be worse than that.
///
/// Not barrier-dismissible and no close cross. There is one button and it
/// is the acknowledgement, because a notice somebody can tap past without
/// registering it has been shown is a notice that gets shown once and read
/// never.
class AnnouncementDialog extends StatelessWidget {
  const AnnouncementDialog({super.key, required this.announcement});

  final Announcement announcement;

  /// Show it, and mark it seen when it closes.
  ///
  /// Returns once the dialog is gone. Safe to call with a context that may
  /// have been unmounted in between — the caller checks, and so does this.
  static Future<void> present(
    BuildContext context,
    Announcement announcement,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(announcement: announcement),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The flag, not a Material glyph. This notice is the app
            // introducing itself after a long absence, and a generic icon
            // would be the one thing on screen that did not look like
            // DriveLife.
            SvgPicture.asset('assets/logo-flag-black.svg', height: 30),
            const SizedBox(height: 18),

            Text(
              announcement.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Color(0xFF111111),
                height: 1.25,
              ),
            ),

            if (announcement.intro != null) ...[
              const SizedBox(height: 8),
              Text(
                announcement.intro!,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),
            ],

            if (announcement.body.isNotEmpty ||
                announcement.outro != null) ...[
              const SizedBox(height: 16),
              // Flexible, so a long notice scrolls inside the dialog
              // rather than overflowing it on a short screen.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Paragraphs, not bullets. The copy is written as
                      // prose and bulleting it would turn an update into
                      // a changelog.
                      for (final paragraph in announcement.body)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            paragraph,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Color(0xFF3A3A3A),
                            ),
                          ),
                        ),

                      if (announcement.outro != null)
                        Text(
                          announcement.outro!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                            color: theme.primaryColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Unawaited on purpose — see the class comment.
                  AnnouncementApi.markSeen(announcement.key);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  announcement.cta,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
