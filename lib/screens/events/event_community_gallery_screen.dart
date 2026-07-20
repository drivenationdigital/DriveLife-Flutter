import 'dart:convert';
import 'dart:io';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/models/event_media.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Community gallery uploader — attendees share their photos from an event.
///
/// Separate from the event owner's gallery: these go to the public
/// community gallery table, keyed on the event.
class EventCommunityGalleryScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;
  final String? eventCoverUrl;

  const EventCommunityGalleryScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.eventCoverUrl,
  });

  @override
  State<EventCommunityGalleryScreen> createState() =>
      _EventCommunityGalleryScreenState();
}

class _EventCommunityGalleryScreenState
    extends State<EventCommunityGalleryScreen> {
  static const _gold = Color(0xFFC4A062);
  static const _ink = Color(0xFF0B0B0B);
  static const _muted = Color(0xFF8A8A8A);

  final ImagePicker _picker = ImagePicker();
  final List<ImageData> _images = [];
  bool _uploading = false;

  // ── Picking ──────────────────────────────────────────────────────────

  Future<ImageData> _fileToImageData(File file) async {
    final bytes = await file.readAsBytes();
    final base64String = base64Encode(bytes);

    final lower = file.path.toLowerCase();
    String mimeType;
    String extension;

    if (lower.endsWith('.png')) {
      mimeType = 'image/png';
      extension = '.png';
    } else if (lower.endsWith('.webp')) {
      mimeType = 'image/webp';
      extension = '.webp';
    } else {
      mimeType = 'image/jpeg';
      extension = '.jpg';
    }

    return ImageData(
      file: file,
      base64: base64String,
      mimeType: mimeType,
      extension: extension,
    );
  }

  Future<void> _pickImages() async {
    final List<XFile> picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    final imageDataList = await Future.wait(
      picked.map((x) => _fileToImageData(File(x.path))),
    );

    if (!mounted) return;
    setState(() => _images.addAll(imageDataList));
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  // ── Upload ───────────────────────────────────────────────────────────

  Future<void> _uploadAll() async {
    final pending = _images.where((i) => !i.isUploaded).toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some photos first')),
      );
      return;
    }

    setState(() => _uploading = true);

    final progressNotifier = ValueNotifier<double>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sharing your photos',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 24),
                  CircularProgressIndicator(
                    value: progress / 100,
                    color: _gold,
                    backgroundColor: Colors.grey.shade200,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${pending.length} photo${pending.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    try {
      // ── API call — community gallery endpoint (separate table) ──────
      final response = await EventsAPI.uploadCommunityGalleryImages(
        eventId: widget.eventId,
        images: pending,
        onProgress: (progress) => progressNotifier.value = progress,
      );

      print('Upload response: $response');

      if (!mounted) return;
      setState(() {
        for (final img in pending) {
          img.isUploaded = true;
        }
      });

      Navigator.of(context).pop(); // close progress dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photos shared — thanks for contributing!'),
          backgroundColor: Colors.green,
        ),
      );

      // Return true so the event screen can refresh its gallery
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      progressNotifier.dispose();
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final pendingCount = _images.where((i) => !i.isUploaded).length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Share your photos',
          style: TextStyle(
            color: _ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: (_uploading || pendingCount == 0) ? null : _uploadAll,
            child: Text(
              'Upload',
              style: TextStyle(
                color: pendingCount == 0 ? Colors.grey.shade400 : _gold,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Event context banner ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF7EE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: widget.eventCoverUrl != null &&
                            widget.eventCoverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.eventCoverUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: _ink,
                            child: const Icon(Icons.event,
                                color: _gold, size: 22),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UPLOADING TO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.eventTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Picker drop zone ──────────────────────────────────────
          GestureDetector(
            onTap: _uploading ? null : _pickImages,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 6),
                  Text(
                    _images.isEmpty
                        ? 'Tap to add photos from the event'
                        : 'Add more photos',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),

          // ── Grid preview ──────────────────────────────────────────
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_images.length} photo${_images.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if (pendingCount > 0)
                  TextButton(
                    onPressed: _uploading
                        ? null
                        : () => setState(() =>
                            _images.removeWhere((i) => !i.isUploaded)),
                    style: TextButton.styleFrom(
                      foregroundColor: _muted,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear pending',
                        style: TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                final imageData = _images[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: imageData.isRemote
                          ? CachedNetworkImage(
                              imageUrl: imageData.remoteUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              memCacheHeight: 300,
                            )
                          : Image.file(
                              imageData.file!,
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                              cacheHeight: 300,
                            ),
                    ),
                    if (imageData.isUploaded)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 11, color: Colors.white),
                              SizedBox(width: 2),
                              Text(
                                'Shared',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap:
                              _uploading ? null : () => _removeImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],

          const SizedBox(height: 20),

          // ── Guidelines note ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      'Community gallery',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Your photos will appear in this event\'s public gallery for '
                  'everyone to enjoy. Only upload photos you took at this event. '
                  'Cars in your photos may be identified so owners can find '
                  'pictures of their vehicles.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
