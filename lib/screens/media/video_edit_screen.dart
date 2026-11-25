import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/cloudflare_images.dart';
import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/screens/media_picker/media_picker_screen.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const Color _gold = Color(0xFFAE9159);

/// Editing a published video. Administrators only.
///
/// ── THREE THINGS, AND NOT THE FOURTH ────────────────────────────────
///
/// Title, description, playlists. Not the file: replacing the video
/// behind a published post would change what everybody who has
/// already commented was commenting on, and keep the likes. That is a
/// new upload, and deleting the old one, which this screen
/// deliberately does not pretend to offer.
class VideoEditScreen extends StatefulWidget {
  final LongVideo video;

  const VideoEditScreen({super.key, required this.video});

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;

  List<VideoPlaylist> _playlists = const [];

  /// What it is in now, and what it was in when this opened. The
  /// difference is what gets sent - so a save does not re-add a
  /// video to every playlist it was already in.
  final Set<int> _chosen = {};
  Set<int> _original = {};

  bool _loading = true;
  bool _saving = false;

  /// A newly picked thumbnail, not yet saved.
  ///
  /// Three states, and they are all different:
  ///   null  - untouched, leave whatever is there
  ///   ''    - cleared, fall back to Cloudflare's own frame
  ///   a url - this one
  String? _newThumbnail;

  bool _uploadingThumbnail = false;

  @override
  void initState() {
    super.initState();

    _title = TextEditingController(text: widget.video.title);
    _description = TextEditingController(text: widget.video.description);

    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();

    super.dispose();
  }

  Future<void> _load() async {
    final playlists = await VideoPlaylistsAPI.list(
      forVideo: widget.video.postId,
    );

    if (!mounted) return;

    setState(() {
      _playlists = playlists;
      _chosen
        ..clear()
        ..addAll(playlists.where((p) => p.contains).map((p) => p.id));
      _original = Set<int>.from(_chosen);
      _loading = false;
    });
  }

  Future<void> _newPlaylist() async {
    final controller = TextEditingController();

    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Series, season, event…',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (title == null || title.isEmpty || !mounted) return;

    final created = await VideoPlaylistsAPI.create(title);

    if (!mounted) return;

    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create that playlist.')),
      );

      return;
    }

    setState(() {
      _playlists = [created, ..._playlists];
      _chosen.add(created.id);
    });
  }

  Future<void> _pickThumbnail() async {
    final picked = await MediaPickerScreen.open(
      context,
      maxSelection: 1,
      confirmLabel: 'Use this',
      title: 'Choose a thumbnail',
      allowVideo: false,
    );

    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() => _uploadingThumbnail = true);

    final file = picked.first.file;

    // Straight to Cloudflare Images, like every other picture in the
    // app. The video itself is on Stream; a still is not a video and
    // has no business there.
    final url = await CloudflareImages.uploadAndGetUrl(
      bytes: await file.readAsBytes(),
      fileName: file.path.split(Platform.pathSeparator).last,
      variant: 'public',
    );

    if (!mounted) return;

    setState(() => _uploadingThumbnail = false);

    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload that image.')),
      );

      return;
    }

    setState(() => _newThumbnail = url);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;

    setState(() => _saving = true);

    final saved = await VideosAPI.update(
      postId: int.tryParse(widget.video.postId) ?? 0,
      title: _title.text.trim(),
      description: _description.text.trim(),
      thumbnailUrl: _newThumbnail,
    );

    // Only what actually changed. Re-sending every membership would
    // work, but it would also mean a save on a video in six
    // playlists is six writes that change nothing.
    final added = _chosen.difference(_original);
    final removed = _original.difference(_chosen);

    for (final id in added) {
      await VideoPlaylistsAPI.setMembership(
        playlistId: id,
        videoId: widget.video.postId,
        inPlaylist: true,
      );
    }

    for (final id in removed) {
      await VideoPlaylistsAPI.setMembership(
        playlistId: id,
        videoId: widget.video.postId,
        inPlaylist: false,
      );
    }

    if (!mounted) return;

    setState(() => _saving = false);

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save those changes.')),
      );

      return;
    }

    Navigator.of(context).pop(true);
  }

  /// An optional poster frame of your own.
  ///
  /// ── WHY IT IS WORTH HAVING ──────────────────────────────────────
  ///
  /// Cloudflare takes its thumbnail from a fixed point in the video,
  /// which for a lot of footage is a blurred pan or the back of
  /// somebody's head. A still chosen by hand is the difference
  /// between a card people tap and one they scroll past.
  Widget _thumbnailPicker(ThemeProvider theme) {
    // What would be shown if Save were pressed now.
    final showing = _newThumbnail ?? widget.video.thumbnailUrl;
    final custom = _newThumbnail != null
        ? _newThumbnail!.isNotEmpty
        : widget.video.hasCustomThumbnail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Thumbnail',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.textColor,
                ),
              ),
            ),
            if (custom)
              TextButton(
                // Back to Cloudflare's frame rather than to nothing -
                // a video with no picture at all is not an option
                // this offers.
                onPressed: () => setState(() => _newThumbnail = ''),
                child: const Text('Use the video frame'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _uploadingThumbnail ? null : _pickThumbnail,
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (showing.isEmpty)
                    ColoredBox(color: theme.dividerColor)
                  else
                    CachedNetworkImage(
                      imageUrl: showing,
                      fit: BoxFit.cover,
                      memCacheWidth: 900,
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: theme.dividerColor),
                    ),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
                  Center(
                    child: _uploadingThumbnail
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Colors.white,
                                size: 30,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                custom
                                    ? 'Change thumbnail'
                                    : 'Add a thumbnail',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Optional. Without one, the frame Cloudflare picked is used.',
          style: TextStyle(fontSize: 12.5, color: theme.subtextColor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        surfaceTintColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        title: const Text('Edit video'),
        actions: [
          TextButton(
            onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          TextField(
            controller: _title,
            maxLines: null,
            style: TextStyle(color: theme.textColor),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            maxLines: 5,
            style: TextStyle(color: theme.textColor),
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Optional.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _thumbnailPicker(theme),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Playlists',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.textColor,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _newPlaylist,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New'),
                style: TextButton.styleFrom(foregroundColor: _gold),
              ),
            ],
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Loading…',
                style: TextStyle(fontSize: 12.5, color: theme.subtextColor),
              ),
            )
          else if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'None yet. Make one if this video belongs to a series.',
                style: TextStyle(fontSize: 12.5, color: theme.subtextColor),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final playlist in _playlists)
                  FilterChip(
                    selected: _chosen.contains(playlist.id),
                    onSelected: (on) => setState(() {
                      on
                          ? _chosen.add(playlist.id)
                          : _chosen.remove(playlist.id);
                    }),
                    label: Text(playlist.title),
                    selectedColor: const Color(0xFFF4F1EA),
                    checkmarkColor: _gold,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
