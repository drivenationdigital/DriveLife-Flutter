import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "Add to a playlist", from the player.
///
/// ── A SET OF SWITCHES, NOT A LIST TO PICK FROM ──────────────────────
///
/// Because a video can be in several playlists, and because the useful
/// question when this opens is usually "is it already in one" rather
/// than "which shall I put it in". Each row is already ticked or not
/// when the sheet appears, and tapping toggles it.
///
/// That also makes it the remove UI without a second screen: the
/// place somebody looks to take a video out of a playlist is the same
/// place they put it in.
class PlaylistPickerSheet extends StatefulWidget {
  /// The video being filed, as its social id.
  final String videoId;

  const PlaylistPickerSheet({super.key, required this.videoId});

  /// Opens it. Returns true if anything changed, so the caller can
  /// refresh a shelf rather than guessing.
  static Future<bool> show(BuildContext context, String videoId) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaylistPickerSheet(videoId: videoId),
    );

    return changed ?? false;
  }

  @override
  State<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends State<PlaylistPickerSheet> {
  List<VideoPlaylist> _playlists = const [];
  bool _loading = true;
  bool _changed = false;

  /// Which rows are mid-request, so a double tap cannot send two
  /// opposite changes and leave the server holding the second one.
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    final playlists = await VideoPlaylistsAPI.list(forVideo: widget.videoId);

    if (!mounted) return;

    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _toggle(VideoPlaylist playlist) async {
    if (_busy.contains(playlist.id)) return;

    final wanted = !playlist.contains;

    setState(() {
      _busy.add(playlist.id);

      // Optimistic, including the count, so the row reads correctly
      // the instant it is tapped.
      _playlists = [
        for (final p in _playlists)
          if (p.id == playlist.id)
            p.copyWith(
              contains: wanted,
              count: p.count + (wanted ? 1 : -1),
            )
          else
            p,
      ];
    });

    final ok = await VideoPlaylistsAPI.setMembership(
      playlistId: playlist.id,
      videoId: widget.videoId,
      inPlaylist: wanted,
    );

    if (!mounted) return;

    setState(() {
      _busy.remove(playlist.id);

      if (ok) {
        _changed = true;
        return;
      }

      // Put it back. A tick that stays on after a failed request is
      // the app telling somebody their video is somewhere it is not.
      _playlists = [
        for (final p in _playlists)
          if (p.id == playlist.id) playlist else p,
      ];
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update that playlist.')),
      );
    }
  }

  Future<void> _createNew() async {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final controller = TextEditingController();

    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: Text(
          'New playlist',
          style: TextStyle(color: theme.textColor),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.textColor),
          decoration: const InputDecoration(hintText: 'Name it'),
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
      _changed = true;
    });

    // Straight in. Somebody who names a playlist while a video is
    // open wants that video in it - making them tap the row they
    // just created is a step that answers nothing.
    await _toggle(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add to a playlist',
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _createNew,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('New'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFAE9159),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: CircularProgressIndicator(),
              )
            else if (_playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                child: Text(
                  'No playlists yet. Make one and this video goes '
                  'straight into it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.subtextColor,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];

                    return ListTile(
                      onTap: () => _toggle(playlist),
                      leading: Icon(
                        playlist.contains
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: playlist.contains
                            ? const Color(0xFFAE9159)
                            : theme.subtextColor,
                      ),
                      title: Text(
                        playlist.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        // Curated ones say so, because they are not
                        // this person's and behave differently.
                        playlist.isPublic
                            ? 'DriveLife  ·  ${playlist.countLabel}'
                            : playlist.countLabel,
                        style: TextStyle(
                          color: theme.subtextColor,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: _busy.contains(playlist.id)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _changed),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
