import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// The most photos one pick may add to a gallery.
///
/// This is a memory limit, not a server one. `pickMultiImage` copies every
/// chosen file into the app's cache before it returns, and each tile then
/// decodes a bitmap — so an uncapped pick is how 200 photos took five minutes
/// to appear and then took the app down with them. Fifty is enough for a car
/// meet in one go, and a second pick appends to the same gallery.
const int kGalleryPickLimit = 50;

/// What a pick produced: the files, and anything the user needs telling.
typedef PickedGalleryPhotos = ({List<File> files, String? notice});

/// How many more photos may be picked, given what a screen already holds.
///
/// Never negative: a screen somehow holding more than the cap should offer
/// zero, not a negative budget that reads as "unlimited" further down.
int galleryPickBudget(int alreadyPicked) {
  final remaining = kGalleryPickLimit - alreadyPicked;
  return remaining > 0 ? remaining : 0;
}

/// What to pass the platform picker as its own selection cap, or null to leave
/// it uncapped.
///
/// The platform interface throws on a limit below 2, so the last free slot has
/// to go through uncapped and be trimmed on the way back. Returning null there
/// is not a shortcut — it is the only legal value.
int? galleryPickerLimit(int budget) => budget >= 2 ? budget : null;

/// Picks photos for a gallery, never more than [kGalleryPickLimit] at once.
///
/// [alreadyPicked] is what the screen is holding, so a second pick tops up to
/// the cap rather than starting the count again.
///
/// The cap is applied twice on purpose. [galleryPickerLimit] asks the OS
/// picker to stop the user selecting past it, which is where a limit belongs.
/// iOS honours it as PHPickerViewController's selectionLimit.
///
/// The trim below is what actually guarantees the bound, because that ask is
/// not always honoured. Android's default pick goes through an
/// ACTION_GET_CONTENT intent, which has no notion of a maximum and ignores the
/// limit outright — so there, the trim is the ONLY thing enforcing the cap, and
/// the user finds out after choosing rather than during. The same is true of
/// the last free slot, which cannot be expressed at all (see
/// [galleryPickerLimit]).
Future<PickedGalleryPhotos> pickGalleryPhotos({int alreadyPicked = 0}) async {
  final budget = galleryPickBudget(alreadyPicked);

  if (budget == 0) {
    return (
      files: <File>[],
      notice:
          'You already have $kGalleryPickLimit photos. '
          'Upload these first, then add more.',
    );
  }

  final picked = await ImagePicker().pickMultiImage(
    limit: galleryPickerLimit(budget),
    // requestFullMetadata is deliberately left on: MediaCompressor passes
    // keepExif, and orientation lives in that metadata.
  );

  if (picked.length <= budget) {
    return (files: picked.map((x) => File(x.path)).toList(), notice: null);
  }

  return (
    files: picked.take(budget).map((x) => File(x.path)).toList(),
    notice:
        'Added the first $budget — $kGalleryPickLimit photos is the limit '
        'for one upload.',
  );
}
