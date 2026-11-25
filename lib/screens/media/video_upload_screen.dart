import 'dart:io';

import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/providers/video_upload_provider.dart';
import 'package:drivelife/screens/media_picker/media_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Choosing a long-form video and naming it. Administrators only.
///
/// ── WHAT THIS SCREEN NO LONGER DOES ─────────────────────────────────
///
/// Upload. It used to own the upload, which meant closing it - even
/// by accident, even to check something - threw away however much had
/// been sent. On a two-gigabyte file over a phone connection that is
/// potentially an hour of work.
///
/// So it now picks a file, takes a title, hands both to
/// [VideoUploadProvider] and leaves. Everything after that - the
/// bytes, Cloudflare's encode, publishing - is reported by the tile
/// at the top of the media tab, which is where somebody would
/// naturally go to look.
class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({super.key});

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  File? _file;
  int _bytes = 0;

  /// Playlists this video will be filed into once it is published.
  ///
  /// Chosen here rather than by viewers later: a playlist is
  /// DriveLife's editorial grouping - a series, a season, one event -
  /// and the person who knows which one a video belongs to is the
  /// person uploading it.
  List<VideoPlaylist> _playlists = const [];
  final Set<int> _chosen = {};
  bool _loadingPlaylists = true;

  @override
  void initState() {
    super.initState();

    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final playlists = await VideoPlaylistsAPI.list();

    if (!mounted) return;

    setState(() {
      _playlists = playlists;
      _loadingPlaylists = false;
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

    // Ticked straight away. Somebody who names a playlist while
    // uploading a video means this video to go in it.
    setState(() {
      _playlists = [created, ..._playlists];
      _chosen.add(created.id);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();

    super.dispose();
  }

  Future<void> _pick() async {
    // The app's own picker rather than a new dependency, so this looks
    // and behaves like every other media choice in DriveLife.
    //
    // maxVideoDuration is deliberately NOT passed: it is the picker's
    // length cap, and this screen exists to upload things longer than
    // anything that cap would allow.
    final picked = await MediaPickerScreen.open(
      context,
      maxSelection: 1,
      confirmLabel: 'Use this',
      title: 'Choose a video',
      allowVideo: true,
    );

    if (picked == null || picked.isEmpty || !mounted) return;

    final file = picked.first.file;
    final size = await file.length();

    if (!mounted) return;

    setState(() {
      _file = file;
      _bytes = size;

      // A sensible starting title rather than an empty box. The
      // filename is usually close and always better than nothing.
      if (_title.text.trim().isEmpty) {
        final name = file.path.split(Platform.pathSeparator).last;
        final dot = name.lastIndexOf('.');

        _title.text = dot > 0 ? name.substring(0, dot) : name;
      }
    });
  }

  void _start() {
    final file = _file;

    if (file == null) return;

    context.read<VideoUploadProvider>().start(
      file: file,
      title: _title.text.trim(),
      description: _description.text.trim(),
      bytes: _bytes,
      // Filed once the upload finishes and the video is published -
      // it has no id to file until then. See VideoUploadProvider.
      playlistIds: _chosen.toList(),
    );

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _file != null && _title.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Upload a video'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _filePanel(),
          const SizedBox(height: 22),
          _field(_title, 'Title', 'What is it called?'),
          const SizedBox(height: 16),
          _field(
            _description,
            'Description',
            'What is in it? Optional.',
            lines: 4,
          ),
          const SizedBox(height: 22),
          _playlistPicker(),
          const SizedBox(height: 22),
          const Text(
            'The upload keeps going while you use the app, and you can '
            'follow it from the media tab. It publishes itself once '
            'Cloudflare has finished processing.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Color(0xFF6B6B6B),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _file == null ? _pick : (ready ? _start : null),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                disabledBackgroundColor: const Color(0xFFE6E6E6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: Text(
                _file == null ? 'Choose a video' : 'Start upload',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filePanel() {
    final file = _file;

    if (file == null) {
      return InkWell(
        onTap: _pick,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD8D8D8)),
            color: const Color(0xFFFAFAFA),
          ),
          child: const Column(
            children: [
              Icon(Icons.video_library_outlined, size: 34, color: Colors.grey),
              SizedBox(height: 10),
              Text(
                'Choose a video',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                'Any length. Large files upload in the background and '
                'resume if interrupted.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E6)),
        color: const Color(0xFFFAFAFA),
      ),
      child: Row(
        children: [
          const Icon(Icons.movie_outlined, size: 22, color: Color(0xFF6B6B6B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.path.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  readableSize(_bytes),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _pick, child: const Text('Change')),
        ],
      ),
    );
  }

  /// Which playlists this video joins.
  Widget _playlistPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Playlists',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: _newPlaylist,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAE9159),
              ),
            ),
          ],
        ),
        if (_loadingPlaylists)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Loading…',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          )
        else if (_playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'None yet. Make one if this video belongs to a series.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
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
                  checkmarkColor: const Color(0xFFAE9159),
                ),
            ],
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int lines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: lines,
      // So the Start button enables the moment there is a title.
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Bytes as somebody reads them.
String readableSize(int bytes) {
  if (bytes <= 0) return '';

  const units = ['B', 'KB', 'MB', 'GB'];

  var value = bytes.toDouble();
  var unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)}'
      '${units[unit]}';
}
