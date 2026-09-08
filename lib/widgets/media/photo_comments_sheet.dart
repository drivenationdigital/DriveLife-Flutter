import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/routes.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Comments on one gallery photo.
///
/// A sheet rather than a screen: the photo it is about stays visible behind it,
/// which is the whole context for what people are saying.
///
/// Pops the resulting comment count, so the viewer behind can update its badge
/// without refetching the gallery.
class PhotoCommentsSheet extends StatefulWidget {
  final int imageId;

  /// What the caller already believes the count to be, so the header is right
  /// on the first frame rather than after the fetch.
  final int initialCount;

  const PhotoCommentsSheet({
    super.key,
    required this.imageId,
    this.initialCount = 0,
  });

  @override
  State<PhotoCommentsSheet> createState() => _PhotoCommentsSheetState();
}

class _PhotoCommentsSheetState extends State<PhotoCommentsSheet> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  final _controller = TextEditingController();

  /// The sheet's own scroll controller, captured when the list is built.
  ///
  /// Not one of ours: the list scrolls with the sheet, so a second controller
  /// would never attach to anything — and scrolling to a new comment would
  /// silently do nothing.
  ScrollController? _listScroll;

  List<Map<String, dynamic>> _comments = const [];

  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    // _listScroll belongs to the sheet, which disposes it.
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final comments = await EventsAPI.fetchGalleryPhotoComments(
        widget.imageId,
      );
      if (!mounted) return;

      setState(() {
        _comments = comments;
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

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await EventsAPI.addGalleryPhotoComment(
        imageId: widget.imageId,
        body: body,
      );

      if (!mounted) return;

      _controller.clear();
      await _load();

      if (!mounted) return;
      setState(() => _sending = false);

      // Down to the new comment, which is at the bottom of an oldest-first
      // thread and otherwise off screen the moment there are a few.
      final scroll = _listScroll;
      if (scroll != null && scroll.hasClients) {
        await scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> comment) async {
    final id = int.tryParse('${comment['id']}') ?? 0;
    if (id <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete comment?'),
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

    // Gone from the list first; put back if the server disagrees.
    final previous = _comments;
    setState(() {
      _comments = _comments
          .where((c) => int.tryParse('${c['id']}') != id)
          .toList();
    });

    try {
      await EventsAPI.deleteGalleryPhotoComment(id);
    } catch (e) {
      if (!mounted) return;

      setState(() => _comments = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// "3h", "2d" — a thread is scanned, not read, so short beats exact.
  String _age(String raw) {
    final at = DateTime.tryParse(raw);
    if (at == null) return '';

    final gap = DateTime.now().toUtc().difference(at.toUtc());

    if (gap.inMinutes < 1) return 'now';
    if (gap.inMinutes < 60) return '${gap.inMinutes}m';
    if (gap.inHours < 24) return '${gap.inHours}h';
    if (gap.inDays < 7) return '${gap.inDays}d';

    return DateFormat('d MMM').format(at.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        Navigator.pop(context, _comments.length);
      },
      child: Padding(
        // Lifts the sheet clear of the keyboard while typing.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, controller) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    Text(
                      _comments.isEmpty
                          ? 'Comments'
                          : '${_comments.length} comment'
                                '${_comments.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context, _comments.length),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: Colors.grey.shade200),

              Expanded(child: _buildList(controller)),

              Container(height: 1, color: Colors.grey.shade200),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Add a comment…',
                            hintStyle: const TextStyle(
                              color: _muted,
                              fontSize: 15,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: const BorderSide(
                                color: _gold,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, color: _gold),
                        onPressed: _sending ? null : _send,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ScrollController sheetController) {
    _listScroll = sheetController;

    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No comments yet. Say something.',
            style: TextStyle(color: _muted),
          ),
        ),
      );
    }

    return ListView.separated(
      // The sheet's own controller, so dragging the list also drags the sheet.
      controller: sheetController,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final comment = _comments[index];
        final author = comment['author'];
        final hasAuthor = author is Map;

        final handle = hasAuthor ? '${author['name'] ?? ''}' : '';
        final avatar = hasAuthor ? '${author['avatar'] ?? ''}' : '';
        final userId = hasAuthor
            ? (int.tryParse('${author['user_id']}') ?? 0)
            : 0;

        void openAuthor() {
          if (userId <= 0) return;
          Navigator.pushNamed(
            context,
            AppRoutes.viewProfile,
            arguments: {'userId': userId, 'username': handle},
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: openAuthor,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: avatar.isEmpty
                    ? null
                    : CachedNetworkImageProvider(avatar),
                child: avatar.isEmpty
                    ? Icon(Icons.person, size: 18, color: Colors.grey.shade500)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: openAuthor,
                          child: Text(
                            '@$handle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _age('${comment['created_at'] ?? ''}'),
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${comment['body'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
            if (comment['can_delete'] == true)
              IconButton(
                icon: const Icon(Icons.more_horiz, size: 18),
                color: _muted,
                onPressed: () => _delete(comment),
                tooltip: 'Delete comment',
              ),
          ],
        );
      },
    );
  }
}
