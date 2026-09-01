import 'dart:io';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// An event the gallery is tagged to.
///
/// Tagging is the point of this screen: the photos are attached to the event's
/// community gallery, so the tag decides where they end up rather than being
/// decoration.
class TaggedEvent {
  final String id;
  final String name;
  final String location;
  final DateTime? date;
  final String thumbnail;

  const TaggedEvent({
    required this.id,
    required this.name,
    this.location = '',
    this.date,
    this.thumbnail = '',
  });

  factory TaggedEvent.fromSearchResult(Map<String, dynamic> json) {
    return TaggedEvent(
      id: json['id']?.toString() ?? '',
      name: (json['name']?.toString() ?? '').replaceAll('&amp;', '&'),
      location: json['location']?.toString() ?? '',
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
  /// location-less event doesn't render a trailing separator.
  String get subtitle {
    final parts = <String>['Event'];
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
  final _picker = ImagePicker();

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

  /// Next needs all three: a name to show, an event to attach to, and photos
  /// to send. Without the event there is nowhere for the photos to go.
  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty &&
      _taggedEvent != null &&
      _photos.isNotEmpty;

  Future<void> _addPhotos() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _photos.addAll(picked.map((x) => File(x.path)));
    });
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

  void _submit() {
    final event = _taggedEvent;
    if (!_canContinue || event == null) return;

    context.read<GalleryUploadProvider>().startUpload(
      eventId: event.id,
      eventTitle: event.name,
      files: List<File>.from(_photos),
      galleryName: _nameController.text.trim(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sharing ${_photos.length} photo${_photos.length == 1 ? '' : 's'} to '
          '${event.name} — you can keep using the app',
        ),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.of(context).pop(true);
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
            padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
            child: _NextButton(enabled: _canContinue, onPressed: _submit),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(_hPadding, 22, _hPadding, 40),
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
                borderSide: const BorderSide(color: _ink, width: 1.6),
              ),
            ),
          ),

          const SizedBox(height: 26),
          const _FieldLabel('Location or event'),
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
              Text(
                '${_photos.length} photo${_photos.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 15, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PhotoGrid(
            photos: _photos,
            onAdd: _addPhotos,
            onRemove: (index) => setState(() => _photos.removeAt(index)),
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
      color: enabled
          ? _NewGalleryScreenState._ink
          : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
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
                'Search for an event',
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
            child: const Icon(
              Icons.location_on_outlined,
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
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _PhotoGrid({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: photos.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _AddTile(onTap: onAdd);

        final photoIndex = index - 1;
        return _PhotoTile(
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

  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: DottedBorderBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 30, color: Colors.grey.shade600),
            const SizedBox(height: 6),
            Text(
              'Add photos',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
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

class _PhotoTile extends StatelessWidget {
  final File file;
  final bool isCover;
  final VoidCallback onRemove;

  const _PhotoTile({
    required this.file,
    required this.isCover,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            // Tile-sized decode: a full-resolution photo behind a ~120pt tile
            // is tens of megabytes for nothing, and a gallery has many.
            cacheWidth: 400,
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

class _EventSearchSheetState extends State<_EventSearchSheet> {
  final _controller = TextEditingController();

  List<TaggedEvent> _results = [];
  bool _searching = false;
  String? _error;

  /// Rising counter, so a slow response for an earlier query cannot overwrite
  /// the results of a later one.
  int _requestId = 0;

  @override
  void dispose() {
    _controller.dispose();
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
      final response = await EventsAPI.discoverSearch(
        search: trimmed,
        type: 'events',
        perPage: 20,
      );

      if (!mounted || id != _requestId) return;

      setState(() {
        _results = _eventsFrom(response)
            .map(TaggedEvent.fromSearchResult)
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

  /// Pulls the event rows out of a discover-search response.
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
  static List<Map<String, dynamic>> _eventsFrom(Map<String, dynamic>? json) {
    if (json == null) return const [];

    final events = json['events'];
    if (events is Map<String, dynamic>) {
      final data = events['data'];
      if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    }
    if (events is List) return events.whereType<Map<String, dynamic>>().toList();

    final top = json['top_results'];
    if (top is Map<String, dynamic>) {
      final nested = top['events'];
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
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                onChanged: (value) {
                  // Search on submit or once there is enough to be worth a
                  // request — a per-keystroke search on two letters returns
                  // noise and burns requests.
                  if (value.trim().length >= 3) _search(value);
                },
                decoration: InputDecoration(
                  hintText: 'Search events',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Search for the event these photos are from.\nTagging it adds them '
            'to that event’s gallery.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _NewGalleryScreenState._muted,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No events found',
          style: TextStyle(color: _NewGalleryScreenState._muted),
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
            child: const Icon(
              Icons.location_on_outlined,
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
