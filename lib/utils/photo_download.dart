import 'package:drivelife/api/events_api.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// Saves a gallery photo to the device's own photo library.
///
/// The file comes back from the server already resized and watermarked — see
/// `dl_gallery_download`. Doing either here would mean fetching the
/// full-resolution original first, which is exactly what the download is meant
/// not to hand over.
///
/// Reports its own outcome, because every caller wants the same three messages
/// and the failure cases are worth naming rather than collapsing into "could
/// not save": being refused access to the photo library is a thing the user
/// can fix, and is nothing like the network being down.
class PhotoDownload {
  PhotoDownload._();

  /// The album saved photos are grouped into, where the platform supports it.
  static const String _album = 'DriveLife';

  /// Fetches and saves one photo. Returns true if it landed.
  static Future<bool> save({
    required BuildContext context,
    required int mediaId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    void say(String message, {bool bad = false, VoidCallback? retry}) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            // Amber rather than red for something that failed and can simply
            // be tried again. Red is for a decision the user has to go and
            // change; a busy server is neither their fault nor their problem
            // to fix, and shouting about it makes the app feel broken.
            backgroundColor: bad ? const Color(0xFF8A6D2F) : null,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: retry != null ? 6 : 3),
            action: retry == null
                ? null
                : SnackBarAction(
                    label: 'Try again',
                    textColor: Colors.white,
                    onPressed: retry,
                  ),
          ),
        );
    }

    try {
      // Asked before the download rather than after, so a refusal does not
      // cost the user a photo's worth of data to find out.
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          say(
            'DriveLife needs permission to save photos. '
            'You can turn it on in Settings.',
            bad: true,
          );
          return false;
        }
      }

      final bytes = await EventsAPI.downloadGalleryPhoto(mediaId: mediaId);

      await Gal.putImageBytes(
        bytes,
        album: _album,
        name: 'drivelife-$mediaId',
      );

      say('Saved to your photos');
      return true;
    } on GalException catch (e) {
      // Nothing to retry: the photo downloaded fine and the device would not
      // take it. Offering "Try again" would fetch it a second time to be
      // refused again.
      say(
        e.type == GalExceptionType.accessDenied
            ? 'DriveLife needs permission to save photos. '
                  'You can turn it on in Settings.'
            : 'Your device would not save that photo.',
        bad: true,
      );
      return false;
    } catch (e) {
      // The API already phrases these for a person and has already had a
      // second go, so this passes the message through rather than wrapping it
      // in another layer of apology.
      say(
        '$e'.replaceFirst('Exception: ', ''),
        bad: true,
        // Guarded: the snackbar outlives the screen it was raised from, and
        // looking up a messenger on a dead context throws.
        retry: () {
          if (context.mounted) save(context: context, mediaId: mediaId);
        },
      );
      return false;
    }
  }
}
