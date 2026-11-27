import 'dart:async';
import 'dart:io';

import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/long_video.dart';
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
/// Where the video is coming from.
enum VideoSource {
  /// A file on the phone, uploaded to Cloudflare Stream. The original
  /// and still the default: it is DriveLife's own hosting, with no
  /// advertising and no third party deciding what plays before it.
  file,

  /// A link to something already on YouTube.
  ///
  /// ── WHY THIS EXISTS ─────────────────────────────────────────────
  ///
  /// Cloudflare Stream is billed by the minute of stored video, so an
  /// archive of everything DriveLife has ever filmed is a bill that
  /// only goes up. A video that is already public on YouTube does not
  /// need to be stored twice, and nothing about the card, the
  /// playlists, the likes or the comments cares where it plays from.
  ///
  /// It is not a replacement. A YouTube embed shows YouTube's adverts
  /// and cannot be kept behind a membership, so anything editorial or
  /// members-only still belongs in Stream.
  youtube,
}

class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({super.key});

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _link = TextEditingController();
  final TextEditingController _length = TextEditingController();

  VideoSource _source = VideoSource.file;

  File? _file;
  int _bytes = 0;

  /// Set while the YouTube video is being created.
  ///
  /// The file path has nothing like this because it does not wait: it
  /// hands the file to the provider and closes. Adding a link is a
  /// single request that finishes in under a second, and the screen
  /// stays open for it so a bad link can be reported here rather than
  /// as a failed upload tile.
  bool _adding = false;

  String? _linkError;

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
          decoration: const InputDecoration(hintText: 'Series, season, event…'),
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
    _link.dispose();
    _length.dispose();

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
    if (_source == VideoSource.youtube) {
      unawaited(_addLink());

      return;
    }

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

  /// Creates the video from a YouTube link.
  ///
  /// There is no upload, no processing and no progress tile: the
  /// server creates it published and playable in one request, so this
  /// waits for the answer and reports a bad link in place rather than
  /// closing and leaving a failure somewhere else.
  Future<void> _addLink() async {
    setState(() {
      _adding = true;
      _linkError = null;
    });

    final result = await VideosAPI.createYoutube(
      url: _link.text.trim(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      durationSeconds: parseLength(_length.text),
    );

    if (!mounted) return;

    final video = result.video;

    if (video == null) {
      setState(() {
        _adding = false;
        _linkError = result.message ?? 'Could not add that video.';
      });

      return;
    }

    // Filed now rather than later. The upload path has to wait for
    // publishing before a video has an id to file; this one already
    // has both.
    for (final playlistId in _chosen) {
      await VideoPlaylistsAPI.setMembership(
        playlistId: playlistId,
        videoId: video.postId,
        inPlaylist: true,
      );
    }

    if (!mounted) return;

    Navigator.of(context).pop(true);
  }

  /// Keeps the title box useful when a link is pasted.
  ///
  /// A YouTube URL carries no title, and oEmbed would be another
  /// request for something the person adding the video can type in
  /// two seconds. So the only help offered is not leaving the field
  /// empty-looking when there is nothing to prefill - the Add button
  /// stays disabled until there is a title, which is the real prompt.
  void _onLinkChanged(String _) {
    if (_linkError != null) {
      setState(() => _linkError = null);

      return;
    }

    setState(() {});
  }

  /// Whether the button can do anything yet.
  bool get _ready {
    if (_title.text.trim().isEmpty) return false;

    if (_source == VideoSource.youtube) {
      return _youtubeId(_link.text) != null;
    }

    return _file != null;
  }

  /// The same check the server does, done here so a mistyped link is
  /// caught before a request rather than after one.
  ///
  /// Deliberately the same set of shapes as dl_videos_youtube_id: a
  /// bare id, watch, youtu.be, embed, shorts, live and /v/. If these
  /// two ever disagree the server wins - it is the one that matters -
  /// but then the button would be enabled for something the server
  /// refuses, which is a worse experience than this being slightly
  /// strict.
  static String? _youtubeId(String raw) {
    final input = raw.trim();

    if (input.isEmpty) return null;

    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(input)) return input;

    for (final pattern in [
      RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
      RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
      RegExp(r'/(?:embed|shorts|live|v)/([A-Za-z0-9_-]{11})'),
    ]) {
      final match = pattern.firstMatch(input);

      if (match != null) return match.group(1);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final youtube = _source == VideoSource.youtube;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(youtube ? 'Add a video' : 'Upload a video'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _sourceToggle(),
          const SizedBox(height: 20),
          if (youtube) _linkPanel() else _filePanel(),
          const SizedBox(height: 22),
          _field(_title, 'Title', 'What is it called?'),
          const SizedBox(height: 16),
          _field(
            _description,
            'Description',
            'What is in it? Optional.',
            lines: 4,
          ),
          if (youtube) ...[const SizedBox(height: 16), _lengthField()],
          const SizedBox(height: 22),
          _playlistPicker(),
          const SizedBox(height: 22),
          Text(
            youtube
                ? 'The video stays on YouTube and plays inside the app. '
                      'It appears on the media tab straight away, and its '
                      'length fills in the first time somebody watches it.'
                : 'The upload keeps going while you use the app, and you '
                      'can follow it from the media tab. It publishes '
                      'itself once Cloudflare has finished processing.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Color(0xFF6B6B6B),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _adding
                  ? null
                  : youtube
                  ? (_ready ? _start : null)
                  : (_file == null ? _pick : (_ready ? _start : null)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                disabledBackgroundColor: const Color(0xFFE6E6E6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: _adding
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      youtube
                          ? 'Add video'
                          : (_file == null ? 'Choose a video' : 'Start upload'),
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

  /// File or link.
  ///
  /// A segmented control rather than a switch, because neither option
  /// is the "on" state of the other - they are two different jobs that
  /// happen to produce the same kind of post.
  Widget _sourceToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _sourceTab(VideoSource.file, 'Upload a file', Icons.movie_outlined),
          _sourceTab(
            VideoSource.youtube,
            'YouTube link',
            Icons.smart_display_outlined,
          ),
        ],
      ),
    );
  }

  Widget _sourceTab(VideoSource source, String label, IconData icon) {
    final selected = _source == source;

    return Expanded(
      child: GestureDetector(
        onTap: _adding
            ? null
            : () => setState(() {
                _source = source;
                _linkError = null;
              }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? const Color(0xFFAE9159)
                    : const Color(0xFF6B6B6B),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF111111)
                      : const Color(0xFF6B6B6B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// How long the video runs.
  ///
  /// ── WHY THIS IS ASKED FOR AT ALL ────────────────────────────────
  ///
  /// Everything else about a YouTube video comes free: the id is in
  /// the link and the thumbnail is a predictable URL on i.ytimg.com.
  /// The duration is the one thing YouTube will not give up without
  /// the Data API, a key and a daily quota - oEmbed returns the title,
  /// the channel and the thumbnail, and no length.
  ///
  /// It is OPTIONAL because there is already a fallback: the player
  /// reports the real duration the first time somebody presses play
  /// and the server fills it in then (see dl_videos_record_view). All
  /// typing it here buys is that the card is right BEFORE the first
  /// view rather than after it - which matters most on the podcast,
  /// where the length is half of how somebody decides to listen.
  Widget _lengthField() {
    final seconds = parseLength(_length.text);

    return TextField(
      controller: _length,
      keyboardType: TextInputType.datetime,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Length (optional)',
        hintText: '38:14, or 1:02:30',
        helperText: seconds > 0
            ? 'Reads as ${LongVideo.formatPosition(seconds)}'
            : 'Usually not needed - the server reads it from YouTube. '
                  'Failing that, it fills in on the first watch.',
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// Where the YouTube link goes.
  Widget _linkPanel() {
    final id = _youtubeId(_link.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _link,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onChanged: _onLinkChanged,
          decoration: InputDecoration(
            labelText: 'YouTube link',
            hintText: 'youtube.com/watch?v=...',
            border: const OutlineInputBorder(),
            errorText: _linkError,
            suffixIcon: id != null
                ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                : null,
          ),
        ),
        const SizedBox(height: 10),
        // The thumbnail, the moment the link is valid. It is the one
        // thing that can be shown without a request, and it is also
        // proof that the right video was pasted - which a bare id
        // never gives anybody.
        if (id != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                'https://i.ytimg.com/vi/$id/hqdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFF2F2F2),
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Paste a link from YouTube - watch, share, shorts or a '
              'bare video id all work.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _filePanel() {
    final file = _file;

    if (file == null) {
      return InkWell(
        onTap: _pick,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          // Horizontal padding, which it had none of - so the two
          // line caption underneath ran edge to edge and touched the
          // border on both sides.
          //
          // 24 rather than the 20 the page uses, because this text is
          // inside a box that already has its own border: matching
          // the page gutter would have put the words level with the
          // outline and read as cramped even when it was not.
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
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
                    on ? _chosen.add(playlist.id) : _chosen.remove(playlist.id);
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

/// "38:14" or "1:02:30" as seconds; 0 for anything unusable.
///
/// Also accepts a bare number, read as MINUTES - that is how somebody
/// types the length of a podcast, and reading "38" as thirty-eight
/// seconds would be right by the clock and wrong by every expectation.
int parseLength(String raw) {
  final text = raw.trim();

  if (text.isEmpty) return 0;

  final parts = text.split(':');

  if (parts.length == 1) {
    final minutes = int.tryParse(parts.first.trim());

    return minutes == null || minutes < 0 ? 0 : minutes * 60;
  }

  if (parts.length > 3) return 0;

  var total = 0;

  for (final part in parts) {
    final value = int.tryParse(part.trim());

    // A single bad segment makes the whole thing meaningless, rather
    // than silently contributing a zero to a number somebody will
    // then see on a card.
    if (value == null || value < 0) return 0;

    total = total * 60 + value;
  }

  return total;
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
