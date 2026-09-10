import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:drivelife/screens/media/gallery_arrange_screen.dart';
import 'package:drivelife/screens/media/gallery_tagging_screen.dart';
import 'package:drivelife/screens/media/gallery_upload_progress_screen.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:drivelife/services/user_service.dart';
import 'package:drivelife/widgets/events/event_community_gallery_tab.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/utils/gallery_photo_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Who put a gallery together.
///
/// A gallery is one person's named batch of photos attached to an event or a
/// venue, which is why this is a single uploader rather than a list — the
/// community pool for an entity is the sum of its galleries.
class GalleryOwner {
  final int userId;
  final String name;
  final String handle;
  final String avatarUrl;

  const GalleryOwner({
    required this.userId,
    this.name = '',
    this.handle = '',
    this.avatarUrl = '',
  });

  /// "@apex.media", falling back to the display name when there is no handle.
  String get displayHandle {
    if (handle.isNotEmpty) return handle.startsWith('@') ? handle : '@$handle';
    return name.isEmpty ? '' : name;
  }
}

/// Full-screen view of one gallery: cover, then everything else.
///
/// The cover is whatever the entity's owner chose (see the set-cover endpoint);
/// with none chosen the first photo stands in, so the layout never collapses.
class GalleryViewScreen extends StatefulWidget {
  /// One specific gallery. The only way to open a gallery that is tagged to
  /// nothing; when set it takes precedence over [entityId].
  final int? galleryId;

  /// Event or venue id the gallery hangs off, or '' for a standalone gallery.
  final String entityId;

  /// 'event' or 'venue'.
  final String entityType;

  /// Name the uploader gave it, e.g. "Supercar Sunday". Falls back to the
  /// entity's own title when the batch was never named.
  final String? galleryName;

  /// Entity title, used as the heading when there is no gallery name.
  final String entityTitle;

  /// Shown in the date line. The entity's date for an event; a venue has none.
  final DateTime? date;

  /// Pre-formatted date, as the gallery cards already carry ("24/05/2026").
  /// Preferred over [date] so a card does not have to parse and reformat.
  final String? dateLabel;

  /// Known up front from the card that opened this; otherwise taken from the
  /// photos once they load.
  final GalleryOwner? owner;

  /// Public URL, for the share sheet.
  final String? shareUrl;

  /// A photo to open the viewer on once the gallery loads.
  ///
  /// Set by a shared link. The gallery loads underneath first, so closing the
  /// viewer lands there rather than on whatever the recipient had open.
  final int? initialPhotoId;

  /// Called as soon as something here changes what a list showing this gallery
  /// would render — a new cover, a reorder, a delete.
  ///
  /// A callback rather than a pop result because the iOS back-swipe pops with
  /// no result of its own, and blocking the pop to supply one is what stopped
  /// that swipe from working at all.
  final VoidCallback? onChanged;

  const GalleryViewScreen({
    super.key,
    this.galleryId,
    this.entityId = '',
    required this.entityTitle,
    this.entityType = 'event',
    this.galleryName,
    this.date,
    this.dateLabel,
    this.owner,
    this.shareUrl,
    this.initialPhotoId,
    this.onChanged,
  });

  @override
  State<GalleryViewScreen> createState() => _GalleryViewScreenState();
}

class _GalleryViewScreenState extends State<GalleryViewScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  final _userService = UserService();

  final List<CommunityPhoto> _photos = [];
  GalleryOwner? _owner;

  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  bool _loading = true;
  bool _loadingMore = false;

  /// Whether this viewer may curate — reorder and choose the cover. Decided
  /// server-side: the gallery's own owner for a standalone gallery, the event
  /// or venue owner for one tagged to an entity.
  bool _canCurate = false;

  /// The linked entity's image, when the gallery has a link and that entity
  /// has one. Null otherwise — the header then shows the name alone rather
  /// than an empty box.
  String? _entityImage;

  /// Where the gallery was taken, when it is linked to a place rather than to
  /// an event or venue.
  String? _placeName;

  /// Tags on the whole gallery. Per-photo tags are not shown here — they
  /// belong to their photo, not to the gallery as a whole.
  List<GalleryTag> _galleryTags = const [];

  /// Tags on individual photos, keyed by photo row id.
  Map<int, List<GalleryTag>> _photoTags = const {};

  /// Tags this gallery's owner has applied that the tagged member has not
  /// answered yet. Owner-only — they are invisible to everyone else, which is
  /// exactly why the owner needs telling they exist.
  int _pendingTagCount = 0;

  /// Tags the owner has made that their subject has yet to accept.
  ///
  /// Held apart from [_galleryTags] and [_photoTags] because they are not part
  /// of the gallery yet — nobody but the owner should see them listed.
  List<GalleryTag> _pendingTags = const [];

  bool _following = false;
  bool _followBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _owner = widget.owner;
    _load();
  }

  /// Set by a rename, which the widget's own fields cannot reflect.
  String? _renamedTitle;

  String get _title {
    if (_renamedTitle != null && _renamedTitle!.isNotEmpty) {
      return _renamedTitle!;
    }
    return (widget.galleryName != null && widget.galleryName!.isNotEmpty)
        ? widget.galleryName!
        : widget.entityTitle;
  }

  /// The owner's chosen cover, else the first photo.
  CommunityPhoto? get _cover {
    if (_photos.isEmpty) return null;
    for (final photo in _photos) {
      if (photo.isCover) return photo;
    }
    return _photos.first;
  }

  /// Everything except the cover, in order.
  List<CommunityPhoto> get _rest {
    final cover = _cover;
    if (cover == null) return const [];
    return _photos.where((p) => p.id != cover.id).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final response = await EventsAPI.fetchCommunityGallery(
      galleryId: widget.galleryId,
      eventId: widget.entityId,
      page: 1,
      entityType: widget.entityType,
    );

    if (!mounted) return;

    if (response == null || response['success'] != true) {
      setState(() {
        _loading = false;
        _error = 'Could not load this gallery';
      });
      return;
    }

    setState(() {
      _photos
        ..clear()
        ..addAll(_parse(response));
      _page = 1;
      _total = int.tryParse('${response['total']}') ?? _photos.length;
      _totalPages = int.tryParse('${response['total_pages']}') ?? 1;
      // Named is_event_owner for the app already reading it; it means "may
      // curate this gallery".
      _canCurate = response['is_event_owner'] == true;
      _entityImage = _firstLinkImage(response);
      _placeName = _firstPlaceName(response);
      _unscannedCount = int.tryParse('${response['unscanned']}') ?? 0;
      _loading = false;

      // No owner passed in — take it from the cover photo's uploader, which
      // for a single-person gallery is the person who made it.
      _owner ??= _ownerFromPhotos();
    });

    // After the photos, not before: tags are supporting detail and should
    // never hold up the gallery itself.
    unawaited(_loadTags());

    _watchProcessing();

    unawaited(_openInitialPhoto());
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;

    setState(() => _loadingMore = true);
    final next = _page + 1;

    final response = await EventsAPI.fetchCommunityGallery(
      galleryId: widget.galleryId,
      eventId: widget.entityId,
      page: next,
      entityType: widget.entityType,
    );

    if (!mounted) return;

    setState(() {
      if (response != null && response['success'] == true) {
        _photos.addAll(_parse(response));
        _page = next;
        _totalPages = int.tryParse('${response['total_pages']}') ?? _totalPages;
      }
      _loadingMore = false;
    });
  }

  /// The linked place's name, if the gallery has one.
  ///
  /// A place is the only kind of link with no page to open, so it is shown as
  /// plain text rather than something tappable.
  String? _firstPlaceName(Map<String, dynamic> response) {
    final links = response['links'] as List<dynamic>? ?? const [];

    for (final link in links.whereType<Map>()) {
      if ('${link['entity_type']}' != 'location') continue;

      final title = '${link['title'] ?? ''}';
      if (title.isNotEmpty) return title;
    }

    return null;
  }

  /// Photos the vehicle scan has not read yet, across the WHOLE gallery.
  ///
  /// Counted server-side rather than from [_photos]: only the first page is
  /// loaded, so counting locally would say "30 photos" on a 60-photo gallery
  /// where all 60 are unread.
  int _unscannedCount = 0;

  /// Runs the scan on this gallery, later.
  ///
  /// Opens the same tagging screen the upload flow uses: it scans, shows
  /// progress, seeds itself from the tags already saved, and saves back. Doing
  /// it here rather than inline means the results land somewhere you can
  /// actually confirm or remove them.
  Future<void> _scanForVehicles() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryTaggingScreen(
          galleryId: galleryId,
          galleryName: _title,
          // Back to the gallery, not out to the feed — this is a detour from
          // here, not the end of an upload.
          returnToRoot: false,
        ),
      ),
    );

    if (!mounted) return;

    _markChanged();
    await _load();
  }

  /// Opens a member's profile.
  void _openProfile(int userId, String handle) {
    if (userId <= 0) return;

    Navigator.pushNamed(
      context,
      AppRoutes.viewProfile,
      arguments: {'userId': userId, if (handle.isNotEmpty) 'username': handle},
    );
  }

  Timer? _pollTimer;

  /// Follows the server's progress through the unread photos.
  ///
  /// Also nudges it: processing is handed off request to request on the
  /// server, and a chain that dies — a fatal in one batch, a host restart —
  /// leaves the rest unread with nothing to restart it. Asking on every visit
  /// makes that self-healing, and costs a wasted call when a run is already
  /// going, since the server ignores a second start.
  void _watchProcessing() {
    final galleryId = widget.galleryId;

    if (!_canCurate || galleryId == null || galleryId <= 0) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    if (_unscannedCount <= 0) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    unawaited(EventsAPI.processGallery(galleryId: galleryId));

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final status = await EventsAPI.galleryScanStatus(galleryId: galleryId);
        if (!mounted) return;

        final remaining =
            (int.tryParse('${status['total']}') ?? 0) -
            (int.tryParse('${status['scanned']}') ?? 0);

        setState(() => _unscannedCount = remaining > 0 ? remaining : 0);

        if (remaining <= 0) {
          timer.cancel();
          _pollTimer = null;

          // The tags the scan produced are only visible once they are read
          // back — without this the strip flips to "0 users tagged".
          unawaited(_loadTags());
          return;
        }

        // The chain stopped without finishing. Start another rather than
        // watching a number that will not move again.
        if (status['running'] == false) {
          unawaited(EventsAPI.processGallery(galleryId: galleryId));
        }
      } catch (_) {
        // A failed poll is not worth reporting: the next one is five seconds
        // away and the strip simply holds its last number.
      }
    });
  }

  /// Opens the viewer on the photo a shared link named, once, after the
  /// gallery has drawn underneath it.
  bool _openedInitial = false;

  Future<void> _openInitialPhoto() async {
    final wanted = widget.initialPhotoId;
    if (_openedInitial || wanted == null || wanted <= 0) return;

    // Claimed up front: paging below is async, and a second load finishing in
    // the meantime must not open the viewer twice.
    _openedInitial = true;

    var photo = _photos.where((p) => p.id == wanted).firstOrNull;

    if (photo == null) {
      // Not on the first page. The Tagged tab links straight at photos deep
      // inside large galleries, so paging forward is the common case here —
      // not an edge one — and giving up would strand most of those links.
      if (!await _loadAllPhotos()) return;
      photo = _photos.where((p) => p.id == wanted).firstOrNull;
    }

    // Genuinely not here: deleted since the link was made. Leaving the gallery
    // open is a better outcome than an error over the rest of it.
    final target = photo;
    if (target == null || !mounted) return;

    // After this frame, so the gallery is on screen behind the viewer and
    // closing it has somewhere to land.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openViewer(target);
    });
  }

  /// Replaces one photo in the grid, in place.
  void _updatePhoto(CommunityPhoto photo) {
    final at = _photos.indexWhere((p) => p.id == photo.id);
    if (at < 0 || !mounted) return;

    setState(() => _photos[at] = photo);
  }

  /// Tag labels to show over one photo: its own, plus the gallery's.
  /// The members over one photo: its own tags, plus the gallery's.
  ///
  /// Registrations are deliberately left out. A plate is not something you can
  /// open, so a chip for one leads nowhere — and where the plate DOES match a
  /// garage, the person it belongs to is the useful thing to show.
  List<GalleryTag> _tagsForPhoto(CommunityPhoto photo) {
    final seenPeople = <int>{};
    final seenPlates = <String>{};
    final shown = <GalleryTag>[];

    for (final tag in [
      ...(_photoTags[photo.id] ?? const <GalleryTag>[]),
      ..._galleryTags,
    ]) {
      if (tag.kind == TagKind.vehicle) {
        // Kept whether or not the plate matches a garage. A car nobody has
        // registered here is still the car in the photo, and dropping those
        // left the picture with no chip at all — or worse, resolved to an
        // owner and captioned somebody else's McLaren with their handle.
        final plate =
            (tag.registration.isNotEmpty ? tag.registration : tag.label)
                .toUpperCase();
        if (plate.isEmpty || !seenPlates.add(plate)) continue;
        shown.add(tag);
        continue;
      }

      if (!tag.hasMember || !seenPeople.add(tag.ownerId)) continue;
      shown.add(tag);
    }

    return shown;
  }

  /// Opens whatever a chip is about.
  void _openTag(GalleryTag tag) {
    if (tag.kind == TagKind.vehicle) {
      // A plate matching no garage has no page to open, so the chip is a
      // label rather than a dead link.
      if (tag.entityId <= 0) return;

      Navigator.pushNamed(
        context,
        AppRoutes.vehicleDetail,
        arguments: {'garageId': '${tag.entityId}'},
      );
      return;
    }

    _openProfile(
      tag.ownerId,
      tag.ownerHandle.isNotEmpty ? tag.ownerHandle : tag.label,
    );
  }

  /// Loads the gallery-wide tags.
  ///
  /// Quiet on failure: a gallery that loads without its tag row is far better
  /// than an error over a gallery that displays perfectly well.
  Future<void> _loadTags() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return;

    try {
      // Pending rows come back only for the owner, and only they can act on
      // this — for anyone else the request is none of their business.
      final tags = await EventsAPI.fetchGalleryTags(
        galleryId: galleryId,
        includePending: _canCurate,
        // Plates matching no garage come back for the owner alone. They are
        // what the strip counts and what the owner removes; to a visitor they
        // are somebody else's registration over a photo, opening nothing.
        includeUnmatched: _canCurate,
      );
      if (!mounted) return;

      final wide = <GalleryTag>[];
      final perPhoto = <int, List<GalleryTag>>{};
      final waiting = <GalleryTag>[];

      for (final raw in tags) {
        final tag = GalleryTag.fromJson(raw);

        // Absent on an older API build, where every tag was live.
        if (raw['approved'] == false) {
          // Not part of the gallery until it is answered, so it stays out of
          // the lists everyone sees — but it is kept, because the owner's own
          // count of who they have tagged should include it.
          waiting.add(tag);
          continue;
        }

        final mediaId = int.tryParse('${raw['media_id']}') ?? 0;

        if (mediaId == 0) {
          wide.add(tag);
        } else {
          perPhoto.putIfAbsent(mediaId, () => []).add(tag);
        }
      }

      setState(() {
        _galleryTags = wide;
        _photoTags = perPhoto;
        _pendingTags = waiting;
        _pendingTagCount = _countSubjects(waiting);
      });
    } catch (_) {
      // Leave the row hidden.
    }
  }

  /// Image of the first linked entity that has one.
  ///
  /// A gallery may link to nothing, or to something with no cover set, so this
  /// is null far more often than not and the header has to cope either way.
  String? _firstLinkImage(Map<String, dynamic> response) {
    final links = response['links'] as List<dynamic>? ?? const [];

    for (final link in links.whereType<Map>()) {
      final image = link['image']?.toString() ?? '';
      if (image.isNotEmpty) return image;
    }

    return null;
  }

  List<CommunityPhoto> _parse(Map<String, dynamic> response) {
    final images = response['images'] as List<dynamic>? ?? const [];
    return images
        .whereType<Map<String, dynamic>>()
        .map(CommunityPhoto.fromJson)
        .where((p) => p.url.isNotEmpty)
        .toList();
  }

  GalleryOwner? _ownerFromPhotos() {
    final cover = _cover;
    if (cover == null) return null;
    return GalleryOwner(
      userId: 0,
      name: cover.uploaderName,
      avatarUrl: cover.uploaderAvatar,
    );
  }

  /// Pulls in every remaining page before arranging.
  ///
  /// Arranging a partial list is a data bug, not just a UI limit: the reorder
  /// endpoint positions the ids it is given and leaves the rest with a null
  /// sort_order, so photos that were never loaded would silently drop behind
  /// the ones that were.
  Future<bool> _loadAllPhotos() async {
    while (_page < _totalPages) {
      final before = _photos.length;
      await _loadMore();

      if (!mounted) return false;

      // Guard against a page that returns nothing: better to arrange what we
      // have than to spin forever.
      if (_photos.length == before) break;
    }

    return mounted;
  }

  /// Opens the arrange screen and reloads only if something actually changed.
  ///
  /// Reloading rather than trusting the local list: the arrange screen may
  /// have saved several moves, and the server's order is the truth.
  Future<void> _openArrange() async {
    // _loadMore owns _loadingMore, which is also what drives the spinner, so
    // this must not set it - _loadMore bails out early while it is set.
    if (_page < _totalPages && !await _loadAllPhotos()) return;

    if (!mounted) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GalleryArrangeScreen(
          galleryId: widget.galleryId,
          entityId: widget.entityId,
          entityType: widget.entityType,
          photos: List<CommunityPhoto>.from(_photos),
          primaryColor: _gold,
        ),
      ),
    );

    if (changed == true && mounted) {
      _markChanged();
      await _load();
    }
  }

  /// Renames the gallery.
  Future<void> _rename() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return;

    final controller = TextEditingController(text: _title);

    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename gallery'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Gallery name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Empty is not a rename: every gallery has a title, and a blank one leaves
    // a card with nothing but its cover.
    if (title == null || title.isEmpty || title == _title || !mounted) return;

    try {
      await EventsAPI.renameGallery(galleryId: galleryId, title: title);
      if (!mounted) return;

      setState(() => _renamedTitle = title);
      _markChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// The owner's menu: everything that edits this gallery, in one place.
  Future<void> _showGalleryMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Add photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: const Text('Edit user tags'),
              // The same screen the "add some more" strip opens. Reachable
              // from the menu too, because that strip only appears once the
              // scan has finished and this is the obvious place to look.
              onTap: () {
                Navigator.pop(sheetContext);
                _scanForVehicles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _rename();
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Arrange photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openArrange();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete gallery',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteGallery();
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// Deletes the whole gallery, after confirming.
  Future<void> _deleteGallery() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this gallery?'),
        content: Text(
          '"$_title" and all ${_photos.length} of its photos will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);

    try {
      await EventsAPI.deleteGallery(galleryId);
      if (!mounted) return;

      _markChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Adds more photos to this gallery.
  ///
  /// The upload runs in [GalleryUploadProvider] exactly as a new gallery's
  /// does, with one difference: the gallery id is seeded, so every registered
  /// photo APPENDS here rather than the first one creating a second gallery.
  ///
  /// Tagging is not re-run — these photos join a gallery that has already been
  /// tagged and published, and gallery-wide tags cover them automatically.
  Future<void> _addPhotos() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return;

    // Capped like a new gallery's pick, and for the same reason: the picker
    // copies every file before it returns, and a few hundred at once is what
    // took the app down.
    final result = await pickGalleryPhotos();
    if (!mounted) return;

    final notice = result.notice;
    if (notice != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    }

    if (result.files.isEmpty) return;

    final batchId = context.read<GalleryUploadProvider>().startUpload(
      files: result.files,
      eventTitle: _title,
      galleryName: _title,
      entityType: 'none',
      // Seeded, so every photo appends here rather than the first one creating
      // a second gallery.
      existingGalleryId: galleryId,
    );

    if (!mounted) return;

    // The same progress → tagging path a new gallery takes, rather than a
    // toast and a listener. A toast showed no progress, said nothing when the
    // upload failed, and — because tagging was pushed from a listener on THIS
    // screen — silently skipped tagging altogether if you navigated away.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryUploadProgressScreen(
          batchId: batchId,
          galleryName: _title,
          isNewGallery: false,
        ),
      ),
    );

    if (!mounted) return;

    _markChanged();
    await _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Otherwise nothing to unhook: the upload lives in the provider and the
    // progress screen owns the waiting.
    super.dispose();
  }

  /// Sets the cover straight from a tile, without a trip through arranging —
  /// the far more common of the two jobs.
  Future<void> _setCover(CommunityPhoto photo) async {
    final previous = List<CommunityPhoto>.from(_photos);

    setState(() {
      for (var i = 0; i < _photos.length; i++) {
        _photos[i] = _photos[i].copyWith(isCover: _photos[i].id == photo.id);
      }
    });

    try {
      await EventsAPI.setCommunityGalleryCover(
        galleryId: widget.galleryId,
        eventId: widget.entityId,
        imageId: photo.id,
        entityType: widget.entityType,
      );

      if (mounted) _markChanged();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _photos
          ..clear()
          ..addAll(previous);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Removes one photo from the gallery.
  ///
  /// Separate from deleting the gallery: a contributor may remove their own
  /// photo without being able to touch anything else, which is the rule the
  /// delete endpoint enforces and `canDelete` mirrors.
  Future<void> _deletePhoto(CommunityPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('It will be removed from the gallery for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final wasCover = photo.isCover;

    try {
      await EventsAPI.deleteCommunityGalleryImages(imageIds: [photo.id]);
      if (!mounted) return;

      setState(() {
        _photos.removeWhere((p) => p.id == photo.id);
        if (_total > 0) _total -= 1;
      });
      _markChanged();

      // Deleting the cover changes what every list shows for this gallery,
      // and the server picks the replacement — so take its answer.
      if (wasCover && mounted) await _load();

      // A gallery with no photos has no cover, so it renders as a blank card
      // that cannot be fixed from a list. Offer to finish the job here, where
      // the user is already deleting.
      if (mounted && _photos.isEmpty) await _offerEmptyGalleryDelete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Offers to delete a gallery whose last photo has just been removed.
  ///
  /// Not automatic: deleting the gallery is a bigger act than deleting a photo,
  /// and doing it silently would surprise someone who meant to clear it out and
  /// upload again.
  Future<void> _offerEmptyGalleryDelete() async {
    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0 || !_canCurate) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gallery is now empty'),
        content: const Text(
          'A gallery with no photos will show as a blank card. Add more '
          'photos, or delete it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'add'),
            child: const Text('Add photos'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == 'add') {
      await _addPhotos();
    } else if (choice == 'delete') {
      try {
        await EventsAPI.deleteGallery(galleryId);
        if (!mounted) return;
        _markChanged();
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Long-press actions on one photo: make it the cover, or remove it.
  ///
  /// Deliberately about THIS photo. Deleting the whole gallery lives on its
  /// tile in the profile grid, where the gallery is the thing being pointed
  /// at — offering both here made it far too easy to wipe a gallery while
  /// meaning to drop one bad shot.
  Future<void> _showCurateActions(CommunityPhoto photo) async {
    // Curators get both actions; a contributor who only uploaded this photo
    // still gets to remove it.
    if (!_canCurate && !photo.canDelete) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            if (_canCurate)
              photo.isCover
                  // Shown disabled rather than hidden, so the sheet does not
                  // change height depending on which photo you held.
                  ? const ListTile(
                      leading: Icon(Icons.star, color: _gold),
                      title: Text('Already the cover'),
                      enabled: false,
                    )
                  : ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: const Text('Use as cover'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _setCover(photo);
                      },
                    ),
            if (photo.canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deletePhoto(photo);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final owner = _owner;
    if (owner == null || owner.userId <= 0 || _followBusy) return;

    final sessionUser = context.read<AccountManager>().activeUser;
    if (sessionUser == null) return;

    // Optimistic — a follow button that waits on the network feels broken.
    final wasFollowing = _following;
    setState(() {
      _following = !wasFollowing;
      _followBusy = true;
    });

    final ok = await _userService.followUser(owner.userId, sessionUser.id);

    if (!mounted) return;
    setState(() {
      if (!ok) _following = wasFollowing;
      _followBusy = false;
    });
  }

  /// The link that opens this gallery in the app.
  ///
  /// Same shape as the post, event and venue links the app already shares —
  /// `/gallery/:id` — which DeepLinkHandler routes back to this screen.
  /// Null for the entity-addressed view, which is a merged pool of several
  /// galleries and has no single thing to link to.
  String? get _shareUrl {
    if (widget.shareUrl != null && widget.shareUrl!.isNotEmpty) {
      return widget.shareUrl;
    }

    final galleryId = widget.galleryId;
    if (galleryId == null || galleryId <= 0) return null;

    return 'https://app.mydrivelife.com/gallery/$galleryId?ref=share';
  }

  /// Shares a single photo.
  ///
  /// The link carries the gallery AND the photo, so opening it shows that
  /// photo with the gallery behind it — closing lands on the gallery rather
  /// than throwing the recipient out to the feed.
  void _sharePhoto(CommunityPhoto photo) {
    final galleryId = widget.galleryId;

    final url = (galleryId == null || galleryId <= 0)
        ? null
        : 'https://app.mydrivelife.com/gallery/$galleryId'
              '?photo=${photo.id}&ref=share';

    SharePlus.instance.share(
      ShareParams(
        text: url == null ? _title : '$_title\n$url',
        subject: _title,
      ),
    );
  }

  void _share() {
    final url = _shareUrl;

    // share_plus 12's API. The rest of the app still calls the deprecated
    // Share.share; this is the current form rather than matching that.
    SharePlus.instance.share(
      ShareParams(
        text: url == null ? _title : '$_title\n$url',
        subject: _title,
      ),
    );
  }

  void _openViewer(CommunityPhoto photo) {
    final index = _photos.indexWhere((p) => p.id == photo.id);
    if (index < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CommunityPhotoViewer(
          photos: List.of(_photos),
          initialIndex: index,
          // Gallery-wide tags apply to every photo, so they show alongside
          // whatever is tagged on this one specifically.
          tagsFor: _tagsForPhoto,
          onTagTap: _openTag,
          onShare: _sharePhoto,
          // A like or comment in the viewer updates the grid behind it, so
          // closing the viewer does not show stale counts.
          onPhotoChanged: _updatePhoto,
        ),
      ),
    );
  }

  /// Tells the caller its cover, order or count is now stale. Fires the moment
  /// the change lands rather than on the way out, so every way of leaving —
  /// the back arrow, the iOS edge swipe, the Android back button — carries it.
  void _markChanged() => widget.onChanged?.call();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      // iOS centres app bar titles by default, which centres this
      // left-aligned block and leaves it looking off.
      centerTitle: false,
      leadingWidth: 40,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          // The linked entity's image, and only when there is one. A gallery
          // need not be linked to anything, and an entity need not have a
          // cover — an initials placeholder in those cases is noise, so the
          // name simply takes the full width instead.
          if (_entityImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: _entityImage!,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                memCacheWidth: 140,
                placeholder: (_, __) => Container(
                  width: 46,
                  height: 46,
                  color: Colors.grey.shade200,
                ),
                // Falling back to a blank box would reintroduce exactly the
                // empty square this replaced, so drop it entirely.
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Share first, then the owner's menu — the menu is the rightmost thing
        // because it is the one only some people see, so its absence does not
        // shuffle the icon everyone uses.
        IconButton(
          icon: const Icon(Icons.ios_share, color: _ink, size: 23),
          tooltip: 'Share',
          onPressed: _share,
        ),
        if (_canCurate && widget.galleryId != null)
          IconButton(
            icon: const Icon(Icons.more_vert, color: _ink, size: 22),
            tooltip: 'Gallery options',
            onPressed: _showGalleryMenu,
          )
        else if (_canCurate)
          // Entity-addressed view: a merged pool, so only ordering applies.
          IconButton(
            icon: const Icon(Icons.swap_vert, color: _ink, size: 23),
            tooltip: 'Arrange photos',
            onPressed: _openArrange,
          ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
    );
  }

  /// "24/05/2026 · 173 photos", dropping the date when there isn't one — a
  /// venue gallery has no date, and a leading separator would look broken.
  String get _subtitle {
    final count = _loading ? null : (_total > 0 ? _total : _photos.length);
    final label = (widget.dateLabel != null && widget.dateLabel!.isNotEmpty)
        ? widget.dateLabel!
        : (widget.date == null
              ? null
              : DateFormat('dd/MM/yyyy').format(widget.date!));

    final parts = <String>[
      if (label != null) label,
      if (count != null) '$count photo${count == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 34, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: _muted)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_photos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No photos in this gallery yet.',
            style: TextStyle(color: _muted),
          ),
        ),
      );
    }

    final cover = _cover!;
    final rest = _rest;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 500) {
          _loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          // Directly under the title, before anything else on the page.
          if (_placeName != null)
            SliverToBoxAdapter(child: _buildPlaceRow(_placeName!)),

          if (_owner != null) SliverToBoxAdapter(child: _buildOwnerRow()),

          // Members only — a gallery of unmatched plates has an empty strip.
          if (_taggedMembers.isNotEmpty)
            SliverToBoxAdapter(child: _buildTagStrip()),

          if (_canCurate && _pendingTagCount > 0)
            SliverToBoxAdapter(child: _buildPendingTagNote()),

          // Owner only, and only while there is something left to read.
          if (_canCurate && !_loading && widget.galleryId != null)
            SliverToBoxAdapter(child: _buildScanPrompt()),

          // Cover runs edge to edge; the grid below is what it introduces.
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () => _openViewer(cover),
              onLongPress: () => _showCurateActions(cover),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: CachedNetworkImage(
                  imageUrl: cover.url,
                  fit: BoxFit.cover,
                  memCacheWidth: 1400,
                  placeholder: (_, __) =>
                      Container(color: Colors.grey.shade200),
                  errorWidget: (_, __, ___) =>
                      Container(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),

          // The same 2px the grid puts between thumbnails, so the cover reads
          // as part of the same set rather than butted against it.
          const SliverToBoxAdapter(child: SizedBox(height: 2)),

          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final photo = rest[index];

              return GestureDetector(
                onTap: () => _openViewer(photo),
                onLongPress: () => _showCurateActions(photo),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: photo.thumb,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.grey.shade200),
                    ),

                    // Only where there is something to say. A "0" on every
                    // tile is noise over the photos themselves.
                    if (photo.likeCount > 0 || photo.commentCount > 0)
                      Positioned(
                        left: 5,
                        bottom: 5,
                        child: _TileCounts(
                          likes: photo.likeCount,
                          comments: photo.commentCount,
                        ),
                      ),
                  ],
                ),
              );
            }, childCount: rest.length),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: _loadingMore ? 64 : 24,
              child: _loadingMore
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Where the gallery was taken.
  ///
  /// Above the cover rather than in the header: the header already carries the
  /// gallery name and the linked entity, and a long place name would push
  /// either of those out.
  Widget _buildPlaceRow(String place) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, size: 16, color: _gold),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              place,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: _muted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Who and what is in this gallery, as a horizontal strip.
  ///
  /// Horizontal rather than wrapped: a gallery from a big meet can carry a
  /// dozen tags, and letting them wrap would push the cover off the screen —
  /// the cover is what the page is for.
  /// The members in this gallery, deduped.
  ///
  /// People, not plates: a car tag is really about its owner, and a plate
  /// matching no garage is about nobody — so it is left out rather than shown
  /// as a chip that leads nowhere. Two of one person's cars make one chip.
  List<GalleryTag> get _taggedMembers {
    final seen = <int>{};
    final members = <GalleryTag>[];

    // Both kinds. A tag made on one photo is still a person in this gallery,
    // and counting only the gallery-wide ones reported "0 users tagged" to
    // someone looking at a tag they had just made by hand.
    for (final tag in [
      ..._galleryTags,
      for (final tags in _photoTags.values) ...tags,
    ]) {
      if (!tag.hasMember || !seen.add(tag.ownerId)) continue;
      members.add(tag);
    }

    return members;
  }

  /// Every tag on this gallery from the OWNER's point of view.
  ///
  /// Waiting ones included, unlike [_taggedMembers], which is what everybody
  /// sees and so holds only accepted tags. This strip is owner-only, and
  /// telling someone "0 tagged" about something they just tagged themselves is
  /// wrong from where they are standing — the note above it is what explains
  /// that some are still to be accepted.
  List<GalleryTag> get _ownerTags => [
    ..._galleryTags,
    for (final tags in _photoTags.values) ...tags,
    ..._pendingTags,
  ];

  /// How many distinct things a set of tags is about.
  ///
  /// A vehicle counts once however many photos its plate was read in, and a
  /// person counts once however many of their cars are in the gallery. Rows
  /// are what the table holds; subjects are what a person is looking at.
  static int _countSubjects(List<GalleryTag> tags) {
    final plates = <String>{};
    final members = <int>{};

    for (final tag in tags) {
      if (tag.kind == TagKind.vehicle) {
        final plate = tag.registration.isNotEmpty ? tag.registration : tag.label;
        if (plate.isNotEmpty) plates.add(plate.toUpperCase());
      } else if (tag.hasMember) {
        members.add(tag.ownerId);
      }
    }

    return plates.length + members.length;
  }

  /// What the strip says has been tagged.
  ///
  /// Counted by REGISTRATION for vehicles, not by owner. A read plate that
  /// matches nobody's garage is still a car this gallery has tagged, and
  /// counting owners reported "0 users tagged" over a plate the scan had
  /// just found — the plate belongs to no account here, so there was no user
  /// to count.
  ///
  /// People are counted separately rather than folded in, because a car tag
  /// already implies its owner and adding them again would double-count one
  /// tag as two things.
  String get _taggedSummary {
    final plates = <String>{};
    final members = <int>{};

    for (final tag in _ownerTags) {
      if (tag.kind == TagKind.vehicle) {
        final plate = tag.registration.isNotEmpty
            ? tag.registration
            : tag.label;
        if (plate.isNotEmpty) plates.add(plate.toUpperCase());
      } else if (tag.hasMember) {
        members.add(tag.ownerId);
      }
    }

    final parts = [
      if (plates.isNotEmpty)
        '${plates.length} vehicle${plates.length == 1 ? '' : 's'}',
      if (members.isNotEmpty)
        '${members.length} user${members.length == 1 ? '' : 's'}',
    ];

    // Nothing yet: still says what this strip is for rather than going blank.
    return parts.isEmpty ? 'No tags yet' : '${parts.join(', ')} tagged';
  }

  /// What the scan is doing, or what it found.
  ///
  /// Two states in one strip, because they are the same thing at two points in
  /// its life. While photos are unread it reports progress and is not a button
  /// — the work is already happening on the server, and offering to start it
  /// invited people to trigger what was under way. Once everything has been
  /// read it becomes the way in to adding more tags by hand.
  Widget _buildScanPrompt() {
    final scanning = _unscannedCount > 0;

    final title = scanning
        ? 'Scanning $_unscannedCount photo'
              '${_unscannedCount == 1 ? '' : 's'}'
        : _taggedSummary;

    final subtitle = scanning
        ? 'Finding number plates and tagging the owners.'
        : 'Click to add some more';

    final strip = Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 19,
            height: 19,
            child: scanning
                // A spinner rather than the old stars: this is work in
                // progress, and a static icon read as a button to press.
                ? const CircularProgressIndicator(strokeWidth: 2, color: _gold)
                : const Icon(
                    Icons.local_offer_outlined,
                    size: 19,
                    color: _gold,
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
              ],
            ),
          ),
          if (!scanning)
            const Icon(Icons.chevron_right, size: 20, color: _gold),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: scanning
          ? strip
          : InkWell(
              onTap: _scanForVehicles,
              borderRadius: BorderRadius.circular(14),
              child: strip,
            ),
    );
  }

  /// Explains why a tag the owner added is not showing.
  ///
  /// Without this the owner tags someone, sees nothing appear, and reasonably
  /// concludes it failed — when it is simply waiting on the other person.
  Widget _buildPendingTagNote() {
    final count = _pendingTagCount;

    // Named rather than counted as bare "tags", so this line and the summary
    // above it are visibly about the same things.
    final plates = <String>{};
    final members = <int>{};

    for (final tag in _pendingTags) {
      if (tag.kind == TagKind.vehicle) {
        final plate = tag.registration.isNotEmpty ? tag.registration : tag.label;
        if (plate.isNotEmpty) plates.add(plate.toUpperCase());
      } else if (tag.hasMember) {
        members.add(tag.ownerId);
      }
    }

    final parts = [
      if (plates.isNotEmpty)
        '${plates.length} vehicle${plates.length == 1 ? '' : 's'}',
      if (members.isNotEmpty)
        '${members.length} user${members.length == 1 ? '' : 's'}',
    ];

    final what = parts.isEmpty
        ? '$count tag${count == 1 ? '' : 's'}'
        : parts.join(' and ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$what waiting to be accepted. '
              '${count == 1 ? 'It' : 'They'} will show here once confirmed.',
              style: const TextStyle(
                fontSize: 12.5,
                color: _muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagStrip() {
    final members = _taggedMembers;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'In this gallery',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tag = members[index];
                final handle = tag.ownerHandle.isNotEmpty
                    ? tag.ownerHandle
                    : tag.label;

                return InkWell(
                  onTap: () => _openProfile(tag.ownerId, handle),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 4,
                      right: 12,
                      top: 4,
                      bottom: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GalleryTagAvatar(
                          imageUrl: tag.ownerAvatar,
                          isVehicle: false,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '@$handle',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerRow() {
    final owner = _owner!;
    final canFollow = owner.userId > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openProfile(owner.userId, owner.handle),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: owner.avatarUrl.isEmpty
                  ? null
                  : CachedNetworkImageProvider(owner.avatarUrl),
              child: owner.avatarUrl.isEmpty
                  ? Icon(Icons.person, color: Colors.grey.shade500)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _openProfile(owner.userId, owner.handle),
              // Transparent, not null: without a colour the empty space beside
              // a short name does not register a tap.
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    owner.displayHandle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    owner.name.isEmpty ? 'Gallery' : 'Gallery by ${owner.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ),
            ),
          ),
          if (canFollow)
            OutlinedButton(
              onPressed: _followBusy ? null : _toggleFollow,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _ink, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              child: Text(
                _following ? 'Following' : 'Follow',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              CircleAvatar(radius: 22, backgroundColor: Colors.grey.shade200),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 130,
                      color: Colors.grey.shade200,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 90,
                      color: Colors.grey.shade200,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(color: Colors.grey.shade200),
        ),
        const SizedBox(height: 2),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => Container(color: Colors.grey.shade200),
        ),
      ],
    );
  }
}

/// Like and comment counts over a grid tile.
class _TileCounts extends StatelessWidget {
  final int likes;
  final int comments;

  const _TileCounts({required this.likes, required this.comments});

  @override
  Widget build(BuildContext context) {
    Widget pill(IconData icon, int count) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        // A scrim, because a white count over a bright photo is unreadable.
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (likes > 0) pill(Icons.favorite, likes),
          if (likes > 0 && comments > 0) const SizedBox(width: 7),
          if (comments > 0) pill(Icons.mode_comment, comments),
        ],
      ),
    );
  }
}
