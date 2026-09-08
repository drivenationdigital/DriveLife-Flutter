import 'dart:io';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:drivelife/screens/media/gallery_upload_progress_screen.dart';
import 'package:drivelife/utils/gallery_photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// What kind of thing a gallery hangs off.
enum TaggedEntityType { event, venue, location }

/// An event or venue the gallery is tagged to.
///
/// Tagging is the point of this screen: the photos are attached to that
/// entity's community gallery, so the tag decides where they end up rather
/// than being decoration.
class TaggedEvent {
  final String id;
  final String name;
  final String location;
  final DateTime? date;
  final String thumbnail;
  final TaggedEntityType type;

  /// Google's id for a place. Empty for an event or venue, which are posts.
  final String placeId;

  final double? lat;
  final double? lng;

  const TaggedEvent({
    required this.id,
    required this.name,
    this.location = '',
    this.date,
    this.thumbnail = '',
    this.type = TaggedEntityType.event,
    this.placeId = '',
    this.lat,
    this.lng,
  });

  /// Wire value for `entity_type`.
  String get entityType => switch (type) {
    TaggedEntityType.venue => 'venue',
    TaggedEntityType.location => 'location',
    TaggedEntityType.event => 'event',
  };

  /// A place has no post id, so it is linked by name and coordinates instead.
  bool get isPlace => type == TaggedEntityType.location;

  factory TaggedEvent.fromSearchResult(
    Map<String, dynamic> json, {
    TaggedEntityType type = TaggedEntityType.event,
  }) {
    return TaggedEvent(
      type: type,
      id: json['id']?.toString() ?? '',
      name: (json['name']?.toString() ?? '').replaceAll('&amp;', '&'),
      // Events call it `location`, venues `venue_location`.
      location: (json['location'] ?? json['venue_location'])?.toString() ?? '',
      date: _parseSearchDate(json['start_date']),
      thumbnail: json['thumbnail']?.toString() ?? '',
    );
  }

  /// Discover-search returns `MM/dd/yyyy HH:mm` — US order, not ISO.
  ///
  /// `DateTime.tryParse` returns null on it, which silently dropped the date
  /// from the tag card. Parsed explicitly, with tryParse kept as a fallback in
  /// case another caller feeds this an ISO string.
  static DateTime? _parseSearchDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    for (final pattern in const ['MM/dd/yyyy HH:mm', 'MM/dd/yyyy']) {
      try {
        return DateFormat(pattern).parseStrict(raw);
      } catch (_) {
        // Try the next shape.
      }
    }

    return DateTime.tryParse(raw);
  }

  /// "Event · Goodwood · 24/05/2026" — parts only when we have them, so a
  /// location-less entity doesn't render a trailing separator.
  String get subtitle {
    final parts = <String>[
      switch (type) {
        TaggedEntityType.venue => 'Venue',
        TaggedEntityType.location => 'Location',
        TaggedEntityType.event => 'Event',
      },
    ];
    if (location.isNotEmpty) parts.add(location);
    if (date != null) parts.add(DateFormat('dd/MM/yyyy').format(date!));
    return parts.join(' · ');
  }
}

/// Compose a new gallery: name it, tag the event it belongs to, pick photos.
///
/// Reached from "Add a gallery" on the media tab. Pressing Next hands the
/// photos to [GalleryUploadProvider], the same background uploader the event
/// community gallery uses — per-photo retry, incremental registration, and the
/// user free to leave the screen while it runs.
class NewGalleryScreen extends StatefulWidget {
  const NewGalleryScreen({super.key});

  @override
  State<NewGalleryScreen> createState() => _NewGalleryScreenState();
}

class _NewGalleryScreenState extends State<NewGalleryScreen> {
  static const Color _gold = Color(0xFFC4A062);
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const double _hPadding = 20;

  final _nameController = TextEditingController();

  TaggedEvent? _taggedEvent;
  final List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    // The Next button's enabled state follows the name, so it has to rebuild
    // as the user types.
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Next needs a title and at least one photo — the two things every gallery
  /// must have, the first photo being its cover.
  ///
  /// An event or venue is deliberately NOT required: a gallery is its own
  /// entity, and tagging one is optional metadata.
  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty && _photos.isNotEmpty;

  /// What is still missing, for the hint beside a disabled Next.
  ///
  /// A greyed-out button with photos already picked reads as broken — the one
  /// thing left to do is usually the title, and nothing said so.
  String? get _blocker {
    final needsName = _nameController.text.trim().isEmpty;
    final needsPhotos = _photos.isEmpty;

    if (needsName && needsPhotos) return 'Add a name and at least one photo';
    if (needsName) return 'Add a name to continue';
    if (needsPhotos) return 'Add at least one photo to continue';
    return null;
  }

  /// True while the picker is copying what was chosen.
  ///
  /// image_picker copies every chosen file into the app's cache before it
  /// returns, and gives no per-file callback while it does — so this is the
  /// one honest thing we can show for that stretch. Without it the screen just
  /// looked frozen.
  bool _picking = false;

  bool get _atLimit => _photos.length >= kGalleryPickLimit;

  Future<void> _addPhotos() async {
    if (_picking) return;

    setState(() => _picking = true);

    try {
      final result = await pickGalleryPhotos(alreadyPicked: _photos.length);
      if (!mounted) return;

      setState(() {
        _photos.addAll(result.files);
        _picking = false;
      });

      final notice = result.notice;
      if (notice != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _picking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickEvent() async {
    final event = await showModalBottomSheet<TaggedEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Without this the sheet is free to run under the status bar — with the
      // keyboard up it grows past the notch and the search field sits behind
      // the clock and battery.
      useSafeArea: true,
      builder: (_) => const _EventSearchSheet(),
    );

    if (event != null && mounted) setState(() => _taggedEvent = event);
  }

  /// Starts the upload and moves to the progress step.
  ///
  /// Tagging needs photo ids, and a photo has none until it is uploaded and
  /// registered — so step 2 cannot come straight after this. The progress page
  /// covers that gap and hands over when the batch lands. The upload itself
  /// runs in the provider, so backing out of either step does not cancel it.
  void _submit() {
    if (!_canContinue) return;

    final event = _taggedEvent;
    final name = _nameController.text.trim();

    final batchId = context.read<GalleryUploadProvider>().startUpload(
      // Empty for an untagged gallery, which stands on its own, and for a
      // place — which has no id of ours.
      eventId: event?.id ?? '',
      eventTitle: event?.name ?? name,
      files: List<File>.from(_photos),
      galleryName: name,
      entityType: event?.entityType ?? 'none',
      placeId: event?.placeId ?? '',
      placeLabel: (event != null && event.isPlace) ? event.name : '',
      lat: event?.lat,
      lng: event?.lng,
    );

    // pushReplacement: going "back" from progress should return to the media
    // tab, not to a picker whose photos are already uploading.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            GalleryUploadProgressScreen(batchId: batchId, galleryName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        // iOS centres app bar titles by default, which centres this
        // left-aligned block and leaves it looking off.
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _ink, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New gallery',
          style: TextStyle(
            color: _ink,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
            child: _NextButton(enabled: _canContinue, onPressed: _submit),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(_hPadding, 22, _hPadding, 0),
            sliver: SliverList.list(
              children: [
                const _FieldLabel('Gallery name'),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'e.g. Sunday Scramble, May 2026',
                    hintStyle: const TextStyle(color: _muted, fontSize: 16),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _brandGold,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),

                if (_blocker != null) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 15,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _blocker!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 26),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const _FieldLabel('Event or venue'),
                    const SizedBox(width: 8),
                    // Said plainly, because the field looked mandatory before and
                    // people would hunt for something to put in it.
                    Text(
                      'Optional',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_taggedEvent == null)
                  _EventPickerButton(onTap: _pickEvent)
                else
                  _TaggedEventCard(
                    event: _taggedEvent!,
                    onClear: () => setState(() => _taggedEvent = null),
                  ),

                const SizedBox(height: 26),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const _FieldLabel('Photos'),
                    const Spacer(),
                    if (_picking)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Preparing photos…',
                            style: TextStyle(fontSize: 15, color: _muted),
                          ),
                        ],
                      )
                    else
                      Text(
                        _atLimit
                            ? '$kGalleryPickLimit photos (max)'
                            : '${_photos.length} photo'
                                  '${_photos.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 15,
                          color: _atLimit ? _brandGold : _muted,
                          fontWeight: _atLimit
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          // Its own sliver, so it stays lazy no matter how many were picked.
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(_hPadding, 0, _hPadding, 40),
            sliver: _PhotoGrid(
              photos: _photos,
              atLimit: _atLimit,
              onAdd: _addPhotos,
              onRemove: (index) => setState(() => _photos.removeAt(index)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: _NewGalleryScreenState._ink,
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _NextButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _NewGalleryScreenState._ink : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
          child: Text(
            'Next',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: enabled ? Colors.white : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state for the tag field — reads as a field, acts as a button.
class _EventPickerButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EventPickerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Search events and venues',
                style: TextStyle(
                  color: _NewGalleryScreenState._muted,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tagged event, with a dark border so it reads as filled-in rather than
/// as another empty field.
class _TaggedEventCard extends StatelessWidget {
  final TaggedEvent event;
  final VoidCallback onClear;

  const _TaggedEventCard({required this.event, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _NewGalleryScreenState._ink, width: 1.6),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFF6EEE0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              event.type == TaggedEntityType.venue
                  ? Icons.storefront_outlined
                  : Icons.event_outlined,
              size: 21,
              color: _NewGalleryScreenState._gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _NewGalleryScreenState._ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: _NewGalleryScreenState._muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            color: Colors.grey.shade600,
            onPressed: onClear,
            tooltip: 'Remove tag',
          ),
        ],
      ),
    );
  }
}

/// Add-tile first, then the photos. The first photo is the cover, which is
/// worth labelling because it is decided by order rather than by choosing.
class _PhotoGrid extends StatelessWidget {
  final List<File> photos;
  final bool atLimit;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _PhotoGrid({
    required this.photos,
    required this.atLimit,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      // Scrolled-past tiles are let go rather than kept alive, so the bitmaps
      // behind them can be collected. With fifty photos that is the difference
      // between holding a handful of decodes and holding all fifty.
      addAutomaticKeepAlives: false,
      itemCount: photos.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _AddTile(onTap: onAdd, atLimit: atLimit);

        final photoIndex = index - 1;
        return _PhotoTile(
          // Keyed by path, so removing one photo does not leave every tile
          // after it decoding a different file into the same element.
          key: ValueKey(photos[photoIndex].path),
          file: photos[photoIndex],
          isCover: photoIndex == 0,
          onRemove: () => onRemove(photoIndex),
        );
      },
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  final bool atLimit;

  const _AddTile({required this.onTap, this.atLimit = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: atLimit ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: DottedBorderBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              atLimit ? Icons.check_circle_outline : Icons.add,
              size: 30,
              color: atLimit ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                // A greyed-out tile with no reason given reads as broken, so
                // the tile carries the reason.
                atLimit ? '$kGalleryPickLimit max' : 'Add photos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: atLimit ? Colors.grey.shade500 : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed outline without pulling in a package — a short dash pattern painted
/// around a rounded rect.
class DottedBorderBox extends StatelessWidget {
  final Widget child;

  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: Colors.grey.shade400),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    // Walk the outline and draw every other segment.
    const dash = 6.0;
    const gap = 5.0;

    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A grey tile with a spinner, shown while a photo is still being read off
/// disk and decoded.
///
/// The picker hands back files faster than they can be turned into pictures,
/// so without this the grid fills with blank squares and looks broken.
class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _brandGold),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final File file;
  final bool isCover;
  final VoidCallback onRemove;

  const _PhotoTile({
    super.key,
    required this.file,
    required this.isCover,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(
            builder: (context, constraints) => Image.file(
              file,
              fit: BoxFit.cover,
              // Decoded to the width this tile actually got, rather than a
              // guessed 400. A 12MP photo behind a thumbnail costs about a
              // tenth of a megabyte instead of forty-eight — which, times
              // fifty, is the difference between browsing a pick and running
              // out of memory in it.
              cacheWidth: (constraints.maxWidth * ratio).round().clamp(64, 600),
              // Nothing to show until the first frame decodes.
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  (wasSynchronouslyLoaded || frame != null)
                  ? child
                  : const _TileSkeleton(),
              // A file the picker copied but we cannot read is worth showing
              // as broken — silently blank looks like the app lost it.
              errorBuilder: (context, error, stack) => ColoredBox(
                color: Colors.grey.shade200,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
        if (isCover)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'Cover',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Search-and-tag sheet, backed by the existing discover search.
class _EventSearchSheet extends StatefulWidget {
  const _EventSearchSheet();

  @override
  State<_EventSearchSheet> createState() => _EventSearchSheetState();
}

/// Brand gold — matches ThemeProvider.PRIMARY_COLOR_CODE.
const Color _brandGold = Color(0xFFAE9159);

/// A rounded field border in one colour.
///
/// Setting only `border` leaves the focused state to the theme, which paints
/// it with the Material primary — the blue these fields kept showing.
OutlineInputBorder _goldFieldBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );
}

/// Same key the event and club screens use.
const String _googlePlacesKey = 'AIzaSyDqDMSFVfl-tOgqaj4ZqA5I3HnobrIK6jg';

class _EventSearchSheetState extends State<_EventSearchSheet> {
  final _controller = TextEditingController();

  /// Which kind of thing to search.
  ///
  /// Searching both at once did not work: "The Motorist" returns 12 events and
  /// 1 venue, so with events listed first the venue landed at position 13 and
  /// looked missing. A toggle makes the choice explicit rather than making the
  /// user scroll for it.
  TaggedEntityType _searchType = TaggedEntityType.event;

  /// Owned here, and passed to the places field.
  ///
  /// Without a node of our own the field makes one per build, so it lost focus
  /// after every keystroke — which made editing what you had typed almost
  /// impossible.
  final FocusNode _placeFocus = FocusNode();

  List<TaggedEvent> _results = [];
  bool _searching = false;
  String? _error;

  /// Rising counter, so a slow response for an earlier query cannot overwrite
  /// the results of a later one.
  int _requestId = 0;

  @override
  void dispose() {
    _controller.dispose();
    _placeFocus.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _error = null;
      });
      return;
    }

    final id = ++_requestId;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final isVenue = _searchType == TaggedEntityType.venue;

      // Narrower than 'all', which also spends time on users and vehicles the
      // picker has no use for.
      final response = await EventsAPI.discoverSearch(
        search: trimmed,
        type: isVenue ? 'venues' : 'events',
        perPage: 20,
      );

      if (!mounted || id != _requestId) return;

      setState(() {
        _results = _rowsFrom(response, isVenue ? 'venues' : 'events')
            .map((r) => TaggedEvent.fromSearchResult(r, type: _searchType))
            .where((e) => e.id.isNotEmpty)
            .toList();
        _searching = false;
      });
    } catch (e, stack) {
      if (!mounted || id != _requestId) return;

      // The message the user sees stays plain; the detail goes to the log,
      // because a blanket "could not search" with the cause swallowed is what
      // made this hard to place in the first place.
      debugPrint('NewGallery: event search failed: $e\n$stack');

      setState(() {
        _searching = false;
        _error = 'Could not search events';
      });
    }
  }

  /// Pulls rows of one type out of a discover-search response.
  ///
  /// The shape depends on `type`, which is the trap here:
  ///
  ///  * `type: 'events'` puts them at **`events.data`**, and returns
  ///    `top_results` as an empty **List**.
  ///  * `type: 'all'` fills `top_results` as a **Map** keyed by result type.
  ///
  /// Reading `top_results` as a Map therefore threw a TypeError on the very
  /// call this screen makes. Both shapes are handled so neither `type` breaks
  /// it again.
  static List<Map<String, dynamic>> _rowsFrom(
    Map<String, dynamic>? json,
    String key,
  ) {
    if (json == null) return const [];

    final events = json[key];
    if (events is Map<String, dynamic>) {
      final data = events['data'];
      if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    }
    if (events is List)
      return events.whereType<Map<String, dynamic>>().toList();

    final top = json['top_results'];
    if (top is Map<String, dynamic>) {
      final nested = top[key];
      if (nested is List) {
        return nested.whereType<Map<String, dynamic>>().toList();
      }
    }

    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    // Height has to come off what is actually left, not off the whole screen.
    // The bottom padding lifts the sheet clear of the keyboard, so a fixed
    // `size.height * 0.8` kept its full height and pushed the top out past the
    // status bar — the search field ended up behind the clock and battery.
    final available =
        media.size.height - media.padding.top - media.viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        // Never taller than the space left, and never a sliver on a short
        // screen with the keyboard up.
        height: (available * 0.9).clamp(260.0, available),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              // Places come from Google, events and venues from our own API,
              // so this is genuinely a different widget rather than the same
              // field with a different endpoint behind it.
              child: _searchType == TaggedEntityType.location
                  ? GooglePlaceAutoCompleteTextField(
                      textEditingController: _controller,
                      googleAPIKey: _googlePlacesKey,
                      focusNode: _placeFocus,
                      debounceTime: 400,
                      // ── 3. UK and US only ──────────────────────────────
                      // The app covers two blogs, so a place in neither is
                      // something no gallery can usefully sit at.
                      countries: const ['uk', 'us'],
                      isLatLngRequired: true,
                      isCrossBtnShown: true,
                      inputDecoration: InputDecoration(
                        hintText: 'Search for a place',
                        prefixIcon: const Icon(Icons.place_outlined),
                        border: _goldFieldBorder(Colors.grey.shade300),
                        enabledBorder: _goldFieldBorder(Colors.grey.shade300),
                        focusedBorder: _goldFieldBorder(_brandGold, width: 1.6),
                      ),
                      getPlaceDetailWithLatLng: (Prediction prediction) {
                        // Fires after the coordinates come back, which is the
                        // only point a place is complete enough to return.
                        final name = prediction.description ?? '';
                        if (name.isEmpty) return;

                        Navigator.pop(
                          context,
                          TaggedEvent(
                            type: TaggedEntityType.location,
                            // No post id — a place is identified by Google's
                            // place_id, carried separately.
                            id: '',
                            name: name,
                            placeId: prediction.placeId ?? '',
                            lat: double.tryParse(prediction.lat ?? ''),
                            lng: double.tryParse(prediction.lng ?? ''),
                          ),
                        );
                      },
                      itemClick: (Prediction prediction) {
                        _controller.text = prediction.description ?? '';
                        _controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: _controller.text.length),
                        );
                      },
                    )
                  : TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      onChanged: (value) {
                        // Search on submit or once there is enough to be worth
                        // a request — a per-keystroke search on two letters
                        // returns noise and burns requests.
                        if (value.trim().length >= 3) _search(value);
                      },
                      decoration: InputDecoration(
                        hintText: _searchType == TaggedEntityType.venue
                            ? 'Search venues'
                            : 'Search events',
                        prefixIcon: const Icon(Icons.search),
                        border: _goldFieldBorder(Colors.grey.shade300),
                        enabledBorder: _goldFieldBorder(Colors.grey.shade300),
                        focusedBorder: _goldFieldBorder(_brandGold, width: 1.6),
                      ),
                    ),
            ),
            // Toggle sits under the field, so switching re-runs whatever has
            // already been typed rather than making the user retype it.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<TaggedEntityType>(
                  segments: const [
                    ButtonSegment(
                      value: TaggedEntityType.event,
                      icon: Icon(Icons.event_outlined, size: 16),
                      label: Text('Event'),
                    ),
                    ButtonSegment(
                      value: TaggedEntityType.venue,
                      icon: Icon(Icons.storefront_outlined, size: 16),
                      label: Text('Venue'),
                    ),
                    ButtonSegment(
                      value: TaggedEntityType.location,
                      icon: Icon(Icons.place_outlined, size: 16),
                      label: Text('Location'),
                    ),
                  ],
                  selected: {_searchType},
                  showSelectedIcon: false,
                  // Brand gold on ink, rather than the default lilac the
                  // Material scheme picks — three segments make an unbranded
                  // control much more noticeable than two did.
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _NewGalleryScreenState._muted,
                    selectedBackgroundColor: _brandGold,
                    selectedForegroundColor: Colors.white,
                    side: const BorderSide(color: _brandGold, width: 1.2),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  onSelectionChanged: (selection) {
                    setState(() {
                      _searchType = selection.first;
                      _results = [];
                      // Google's field keeps its own overlay of predictions,
                      // so stale text from the other mode would sit there
                      // looking like a result.
                      _controller.clear();
                    });
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    // Google draws its own prediction list under the field, so this pane would
    // only ever be an empty state competing with it.
    if (_searchType == TaggedEntityType.location) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Start typing to find a place.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8A8A8A)),
          ),
        ),
      );
    }

    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Search for the event these photos are from.\nTagging it adds them '
            'to that event’s gallery.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _NewGalleryScreenState._muted,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searchType == TaggedEntityType.venue
              ? 'No venues found'
              : 'No events found',
          style: const TextStyle(color: _NewGalleryScreenState._muted),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final event = _results[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 6,
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFF6EEE0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              event.type == TaggedEntityType.venue
                  ? Icons.storefront_outlined
                  : Icons.event_outlined,
              size: 21,
              color: _NewGalleryScreenState._gold,
            ),
          ),
          title: Text(
            event.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            event.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.pop(context, event),
        );
      },
    );
  }
}
