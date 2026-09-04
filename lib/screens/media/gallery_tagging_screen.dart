import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/screens/media/gallery_photo_tagging_screen.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:flutter/material.dart';

/// Step 2 — say who and what is in the gallery, then publish.
///
/// Two levels of tagging, and the split is the point:
///
///  * **Here** you tag the gallery. Those tags apply to every photo in it
///    automatically, which is what you want straight after an upload — nobody
///    is going to work through sixty photos one at a time, and the people at a
///    meet are in most of the shots anyway.
///  * **Tag more users** opens the grid for the exceptions: the two or three
///    photos one person is actually in.
///
/// Both write to the same table; a gallery-wide tag is stored with media_id 0
/// and a per-photo one with the photo's row id.
class GalleryTaggingScreen extends StatefulWidget {
  /// The gallery these tags belong to. Null when the upload never registered,
  /// in which case there is nothing to tag and publishing just exits.
  final int? galleryId;

  final String galleryName;

  const GalleryTaggingScreen({
    super.key,
    required this.galleryId,
    required this.galleryName,
  });

  @override
  State<GalleryTaggingScreen> createState() => _GalleryTaggingScreenState();
}

class _GalleryTaggingScreenState extends State<GalleryTaggingScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);

  /// Tags for the whole gallery.
  List<GalleryTag> _tags = [];

  bool _publishing = false;
  bool _openingPhotos = false;

  // ── Scan ───────────────────────────────────────────────────────────────
  //
  // The scan runs a few photos per request (each one is a model round trip),
  // so this screen drives it in a loop and shows progress as it goes rather
  // than blocking on the whole gallery.

  /// What the scan found, one per plate.
  List<Map<String, dynamic>> _suggestions = const [];

  /// Suggestions dismissed with the X, so they stay gone for this session.
  final Set<String> _dismissed = {};

  bool _scanning = false;

  /// False once the server says it has no AI library — the section is then
  /// hidden entirely rather than showing an empty "found nothing".
  bool _scanAvailable = true;

  int _scanned = 0;
  int _scanTotal = 0;

  /// Why the scan could not run. Shown rather than swallowed: a silent failure
  /// made "the endpoint is missing" and "no cars found" look the same, which
  /// is exactly how a missing deployment went unnoticed.
  String? _scanError;

  /// Stops the loop if the screen goes away mid-scan.
  bool _disposed = false;

  bool get _hasGallery => (widget.galleryId ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (_hasGallery) _runScan();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Drives the scan to completion, a few photos at a time.
  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });

    try {
      var done = false;

      // Bounded so a server that never reports done cannot spin forever.
      for (var pass = 0; pass < 200 && !done; pass++) {
        final result = await EventsAPI.scanGallery(
          galleryId: widget.galleryId!,
        );

        if (_disposed || !mounted) return;

        if (result['available'] == false) {
          setState(() {
            _scanAvailable = false;
            _scanning = false;
          });
          return;
        }

        done = result['done'] == true;

        final found = (result['suggestions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        setState(() {
          _scanned = int.tryParse('${result['scanned']}') ?? _scanned;
          _scanTotal = int.tryParse('${result['total']}') ?? _scanTotal;
          _suggestions = found;
          _autoTag(found);
        });
      }
    } catch (e) {
      // A failed scan is not a failed upload — the photos are live and manual
      // tagging still works — so this is reported in place rather than as an
      // error dialog. But it IS reported.
      if (!_disposed && mounted) {
        setState(() => _scanError = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (!_disposed && mounted) setState(() => _scanning = false);
    }
  }

  /// Everything the scan found that has not been removed.
  ///
  /// These are all TAGGED — the section lists what will be saved, not what is
  /// on offer.
  List<Map<String, dynamic>> get _openSuggestions => _suggestions
      .where((s) => !_dismissed.contains('${s['registration'] ?? ''}'))
      .toList();

  /// Tags everything the scan found, without being asked.
  ///
  /// A read plate is strong evidence the car was there, and confirming each one
  /// by hand was pure friction on a gallery with a dozen cars in it. Removing a
  /// wrong one is a single tap; adding twelve right ones was twelve.
  ///
  /// Called inside the caller's setState.
  void _autoTag(List<Map<String, dynamic>> suggestions) {
    for (final suggestion in suggestions) {
      final plate = '${suggestion['registration'] ?? ''}';
      if (plate.isEmpty || _dismissed.contains(plate)) continue;

      final tag = GalleryTag(
        kind: TagKind.vehicle,
        label: plate,
        subtitle: '${suggestion['subtitle'] ?? ''}',
        avatarUrl: '${suggestion['image'] ?? ''}',
        entityId: int.tryParse('${suggestion['entity_id']}') ?? 0,
        registration: plate,
      );

      // The scan is polled repeatedly and returns everything found so far, so
      // without this every pass would re-add the same cars.
      if (_tags.any((t) => t.matches(tag))) continue;

      _tags = [..._tags, tag];
    }
  }

  /// Removes a detected vehicle, and remembers not to re-add it on the next
  /// poll of the same scan.
  void _removeSuggestion(Map<String, dynamic> suggestion) {
    final plate = '${suggestion['registration'] ?? ''}';
    final entityId = int.tryParse('${suggestion['entity_id']}') ?? 0;

    setState(() {
      _dismissed.add(plate);
      _tags = _tags
          .where(
            (t) =>
                t.kind != TagKind.vehicle ||
                (entityId > 0
                    ? t.entityId != entityId
                    : t.label.toUpperCase() != plate.toUpperCase()),
          )
          .toList();
    });
  }

  /// Writes the gallery-wide tags. Saving replaces the set, so calling this
  /// more than once is harmless.
  Future<void> _saveGalleryTags() async {
    if (!_hasGallery) return;

    await EventsAPI.saveGalleryTags(
      galleryId: widget.galleryId!,
      tags: _tags.map((t) => t.toJson()).toList(),
    );
  }

  /// Opens per-photo tagging.
  ///
  /// The gallery-wide tags are saved first, so the grid can show them as the
  /// baseline and nothing is lost if the user leaves from there.
  Future<void> _tagMore() async {
    if (!_hasGallery) return;

    setState(() => _openingPhotos = true);

    try {
      await _saveGalleryTags();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GalleryPhotoTaggingScreen(
            galleryId: widget.galleryId!,
            galleryTags: _tags,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _complain(e);
    } finally {
      if (mounted) setState(() => _openingPhotos = false);
    }
  }

  Future<void> _publish() async {
    if (!_hasGallery) {
      _finish();
      return;
    }

    setState(() => _publishing = true);

    try {
      await _saveGalleryTags();
      if (!mounted) return;
      _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _complain(e);
    }
  }

  /// Back: leave without saving.
  ///
  /// The photos are already live, so this is not destructive — but detected
  /// cars are tagged by default now, so leaving DOES throw work away. Worth one
  /// question when there is something to lose, and silence when there is not.
  Future<void> _leave() async {
    if (_tags.isEmpty) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave without tagging?'),
        content: Text(
          '${_tags.length} tag${_tags.length == 1 ? '' : 's'} will not be '
          'saved. Your photos stay published either way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep tagging'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _complain(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$error'.replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Out of the upload flow entirely — the photos are already live, so there is
  /// nothing behind this screen worth going back to.
  void _finish() {
    final count = _tags.length;
    final messenger = ScaffoldMessenger.of(context);

    Navigator.of(context).popUntil((route) => route.isFirst);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? '${widget.galleryName} published'
              : '${widget.galleryName} published with $count '
                    'tag${count == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        // Same leading + unpadded title as step 1, so the two headings sit on
        // the same line as you move between them.
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: _leave,
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tag users & vehicles',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Step 2 of 2',
              style: TextStyle(color: _muted, fontSize: 13.5),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              onPressed: _publishing ? null : _publish,
              child: _publishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  // Tagging is optional, and "Skip" is honest about that —
                  // "Publish" on an empty list implies work is still pending.
                  : Text(_tags.isEmpty ? 'Skip' : 'Publish'),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          const Text(
            'Who is in this gallery?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Confirm what we spotted. Anything tagged here applies to every '
            'photo in this gallery.',
            style: TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
          ),
          const SizedBox(height: 20),

          if (_hasGallery && _scanAvailable) ...[
            _ScanSection(
              scanning: _scanning,
              scanned: _scanned,
              total: _scanTotal,
              error: _scanError,
              onRetry: _runScan,
              suggestions: _openSuggestions,
              onRemove: _removeSuggestion,
            ),
            const SizedBox(height: 24),
          ],

          if (_hasGallery) ...[
            const SizedBox(height: 28),
            Container(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 20),
            const Text(
              'Only in some photos?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Search for people and vehicles, and tag them photo by photo.',
              style: TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openingPhotos ? null : _tagMore,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: Colors.grey.shade400),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: _openingPhotos
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text(
                  'Tag more users',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The "Auto-detected" block: what the scan found, offered for confirmation.
///
/// Suggestions are offered, not applied. The model reads plates well and
/// guesses make and model less well, and a wrong tag is worse than a missing
/// one — it puts a stranger's name on someone's photos. So a detected car is a
/// row with a Tag button, not a fait accompli.
class _ScanSection extends StatelessWidget {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  final bool scanning;
  final int scanned;
  final int total;

  /// Set when the scan could not run at all.
  final String? error;

  final VoidCallback onRetry;

  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onRemove;

  const _ScanSection({
    required this.scanning,
    required this.scanned,
    required this.total,
    required this.error,
    required this.onRetry,
    required this.suggestions,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing running, nothing found and nothing wrong: stay out of the way.
    if (!scanning && suggestions.isEmpty && error == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 17, color: _gold),
              const SizedBox(width: 7),
              const Text(
                'Auto-detected',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              if (suggestions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${suggestions.length} tagged',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A6D2F),
                    ),
                  ),
                ),
              const Spacer(),
              if (scanning)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            error != null
                ? error!
                : scanning
                ? 'Looking for number plates… $scanned of $total photos'
                : 'Tagged automatically. Remove any that are wrong — owners '
                      'are notified when their car is tagged.',
            style: TextStyle(
              fontSize: 12.5,
              color: error != null ? Colors.red.shade700 : _muted,
              height: 1.4,
            ),
          ),

          if (error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          for (final suggestion in suggestions)
            _SuggestionRow(
              suggestion: suggestion,
              onRemove: () => onRemove(suggestion),
            ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  final Map<String, dynamic> suggestion;
  final VoidCallback onRemove;

  const _SuggestionRow({required this.suggestion, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final plate = '${suggestion['registration'] ?? ''}';
    final image = '${suggestion['image'] ?? ''}';
    final count = int.tryParse('${suggestion['photo_count']}') ?? 0;
    final owner = suggestion['owner'];
    final ownerHandle = owner is Map ? '${owner['label'] ?? ''}' : '';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          if (image.isEmpty)
            const GalleryPlateBadge(size: 40)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: image,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                memCacheWidth: 120,
                placeholder: (_, __) => const GalleryPlateBadge(size: 40),
                errorWidget: (_, __, ___) => const GalleryPlateBadge(size: 40),
              ),
            ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        plate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 7),
                      Text(
                        '$count photo${count == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 11.5, color: _muted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${suggestion['subtitle'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
                // Its own line, not appended to the model: a long model name
                // and a long handle together would ellipsis away exactly the
                // part that says whose car it is.
                if (ownerHandle.isNotEmpty)
                  Text(
                    'Owned by @$ownerHandle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: 'Not in these photos',
          ),
        ],
      ),
    );
  }
}
