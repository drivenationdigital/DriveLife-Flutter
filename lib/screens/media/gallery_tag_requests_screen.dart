import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:flutter/material.dart';

/// Gallery tags waiting on you.
///
/// Someone else's gallery claiming your car — usually because the scan read its
/// plate — is a request until you answer it. Nothing here is visible on the
/// gallery yet, which is the point: accepting is what publishes the link.
class GalleryTagRequestsScreen extends StatefulWidget {
  const GalleryTagRequestsScreen({super.key});

  @override
  State<GalleryTagRequestsScreen> createState() =>
      _GalleryTagRequestsScreenState();
}

class _GalleryTagRequestsScreenState extends State<GalleryTagRequestsScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  List<Map<String, dynamic>> _requests = const [];

  /// Tags currently being answered, so a row cannot be double-tapped into two
  /// conflicting answers.
  final Set<int> _busy = {};

  bool _loading = true;
  String? _error;

  /// Whether anything was accepted or declined, so the caller can refresh.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final requests = await EventsAPI.fetchPendingGalleryTags();
      if (!mounted) return;

      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _respond(Map<String, dynamic> request, bool accept) async {
    final tagId = int.tryParse('${request['tag_id']}') ?? 0;
    if (tagId <= 0 || _busy.contains(tagId)) return;

    setState(() => _busy.add(tagId));

    try {
      await EventsAPI.respondToGalleryTag(tagId: tagId, accept: accept);
      if (!mounted) return;

      setState(() {
        // Answered either way, the request is done with — the row goes.
        _requests = _requests
            .where((r) => int.tryParse('${r['tag_id']}') != tagId)
            .toList();
        _busy.remove(tagId);
        _changed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Tag accepted' : 'Tag declined'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _busy.remove(tagId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Opens the gallery, so a request can be judged on the photos rather than
  /// on a plate and a name.
  void _preview(Map<String, dynamic> request) {
    final title = '${request['gallery_title'] ?? ''}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryViewScreen(
          galleryId: int.tryParse('${request['gallery_id']}'),
          entityTitle: title,
          galleryName: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          titleSpacing: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: const Text(
            'Tag requests',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.grey.shade200),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 34, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 36,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'Nothing to review',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tags on your vehicles will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: _muted),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final request = _requests[index];
          final tagId = int.tryParse('${request['tag_id']}') ?? 0;
          final busy = _busy.contains(tagId);

          final cover = '${request['cover'] ?? ''}';
          final label = '${request['label'] ?? ''}';
          final gallery = '${request['gallery_title'] ?? ''}';
          final by = request['tagged_by'];
          final byName = by is Map ? '${by['name'] ?? ''}' : '';

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _preview(request),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: cover.isEmpty
                            ? Container(
                                width: 54,
                                height: 54,
                                color: Colors.grey.shade200,
                                child: const Icon(
                                  Icons.photo_outlined,
                                  color: Colors.grey,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: cover,
                                width: 54,
                                height: 54,
                                fit: BoxFit.cover,
                                memCacheWidth: 160,
                                placeholder: (_, __) => Container(
                                  width: 54,
                                  height: 54,
                                  color: Colors.grey.shade200,
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  width: 54,
                                  height: 54,
                                  color: Colors.grey.shade200,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              byName.isEmpty
                                  ? 'Tagged in "$gallery"'
                                  : '@$byName tagged this in "$gallery"',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20, color: _muted),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => _respond(request, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : () => _respond(request, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
