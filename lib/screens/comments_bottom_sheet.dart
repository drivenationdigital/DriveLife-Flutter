import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/widgets/comment_item.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:fluttertagger/fluttertagger.dart';
import '../api/interactions_api.dart';
import 'package:drivelife/screens/search_user.dart';
import 'package:image_picker/image_picker.dart';

class CommentSearchViewModel extends ChangeNotifier {
  List<Map<String, dynamic>> userResults = [];
  List<Map<String, dynamic>> hashtagResults = [];
  bool isSearching = false;

  void clear() {
    userResults = [];
    hashtagResults = [];
    isSearching = false;
    notifyListeners();
  }
}

class CommentsBottomSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String postId;

  const CommentsBottomSheet({
    super.key,
    required this.scrollController,
    required this.postId,
  });

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final FlutterTaggerController _controller = FlutterTaggerController();
  final FocusNode _focusNode = FocusNode();
  final CommentSearchViewModel _searchViewModel = CommentSearchViewModel();

  List<dynamic> comments = [];
  bool loading = true;
  String? _replyingToUsername;
  String? _replyingToCommentId;

  bool addingComment = false;
  Map<String, bool> _expandedReplies = {};
  String? _currentUserId;

  // Selected GIF (URL of full-size + preview)
  String? _selectedGifUrl;
  String? _selectedGifPreviewUrl;

  File? _selectedImageFile;
  String? _selectedImageUrl; // set after upload completes
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _getCurrentUserId();
  }

  Future<void> _getCurrentUserId() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    setState(() {
      _currentUserId = userProvider.user?.id.toString();
    });
  }

  Future<void> _deleteComment(String commentId, ThemeProvider theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await InteractionsAPI.deleteComment(commentId);
      await _loadComments();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _searchViewModel.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final data = await InteractionsAPI.fetchComments(widget.postId);
    if (mounted) {
      setState(() {
        comments = data;
        loading = false;
      });
    }
  }

  void _handleReply(String username, String commentId, String userId) {
    setState(() {
      _replyingToUsername = username;
      _replyingToCommentId = commentId;
    });
    _focusNode.requestFocus();
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  void _cancelReply() {
    setState(() {
      _replyingToUsername = null;
      _replyingToCommentId = null;
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  Future<void> _pickGif() async {
    _focusNode.unfocus();

    final result = await showModalBottomSheet<_TenorGif>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TenorGifPicker(),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedGifUrl = result.url;
        _selectedGifPreviewUrl = result.previewUrl;
        // Clear any selected image — only one media item per comment
        _selectedImageFile = null;
        _selectedImageUrl = null;
        _uploadingImage = false;
      });
    }
  }

  void _clearSelectedGif() {
    setState(() {
      _selectedGifUrl = null;
      _selectedGifPreviewUrl = null;
    });
  }

  Future<void> _pickImage() async {
    _focusNode.unfocus();

    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);

    setState(() {
      _selectedImageFile = file;
      _uploadingImage = true;
    });

     // Clear any selected GIF — only one media item per comment
    if (_selectedGifUrl != null) {
      setState(() {
        _selectedGifUrl = null;
        _selectedGifPreviewUrl = null;
      });
    }

    try {
      // Replace with your actual upload method — must return a hosted URL.
      // final url = await InteractionsAPI.uploadCommentImage(file);
      final url ='https://i.imgur.com/placeholder.png'; // placeholder until API is ready

      if (!mounted) return;
      if (url == null || url.isEmpty) {
        throw Exception('Upload returned empty URL');
      }

      setState(() {
        _selectedImageUrl = url;
        _uploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedImageFile = null;
        _selectedImageUrl = null;
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not upload photo: $e')));
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageUrl = null;
      _uploadingImage = false;
    });
  }

  Future<void> _addComment() async {
    final hasText = _controller.text.trim().isNotEmpty;
    final hasGif = _selectedGifUrl != null;
    final hasImage = _selectedImageUrl != null;

    if (!hasText && !hasGif && !hasImage) return;
    if (addingComment || _uploadingImage) return; // wait for upload to finish

    setState(() => addingComment = true);

    await InteractionsAPI.addComment(
      widget.postId,
      _controller.formattedText,
      parentId: _replyingToCommentId != null
          ? int.tryParse(_replyingToCommentId!)
          : null,
      gifUrl: _selectedGifUrl,
      imageUrl: _selectedImageUrl,
    );

    _controller.clear();

    setState(() {
      _replyingToUsername = null;
      _replyingToCommentId = null;
      _selectedGifUrl = null;
      _selectedGifPreviewUrl = null;
      _selectedImageFile = null;
      _selectedImageUrl = null;
      addingComment = false;
    });

    _focusNode.unfocus();
    _searchViewModel.clear();
    await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Draggable Header
            Container(
              color: Colors.transparent,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Comments',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
              ),
            ),

            // Comments list
            Expanded(
              child: loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    )
                  : comments.isEmpty
                  ? const Center(child: Text('No comments yet'))
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        final replies = (c['replies'] ?? []) as List<dynamic>;
                        final username =
                            c['display_name'] ?? c['user_login'] ?? 'user';
                        final commentId = c['id'].toString();
                        final isExpanded = _expandedReplies[commentId] ?? false;
                        final isOwner =
                            c['user_id']?.toString() == _currentUserId;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CommentItem(
                              comment: c,
                              isOwner: isOwner,
                              onReplyTap: () => _handleReply(
                                username,
                                commentId,
                                c['user_id'].toString(),
                              ),
                              onDeleteTap: isOwner
                                  ? () => _deleteComment(commentId, theme)
                                  : null,
                            ),
                            if (replies.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 56,
                                  top: 4,
                                  bottom: 8,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _expandedReplies[commentId] = !isExpanded;
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 1,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isExpanded
                                            ? 'Hide replies'
                                            : 'View ${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (isExpanded && replies.isNotEmpty)
                              ...replies.map((r) {
                                final replyUsername =
                                    r['display_name'] ??
                                    r['user_login'] ??
                                    'user';
                                final isReplyOwner =
                                    r['user_id']?.toString() == _currentUserId;
                                return CommentItem(
                                  comment: r,
                                  isReply: true,
                                  isOwner: isReplyOwner,
                                  onReplyTap: () => _handleReply(
                                    replyUsername,
                                    r['id'].toString(),
                                    r['user_id'].toString(),
                                  ),
                                  onDeleteTap: isReplyOwner
                                      ? () => _deleteComment(
                                          r['id'].toString(),
                                          theme,
                                        )
                                      : null,
                                );
                              }),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
            ),

            // Reply indicator
            if (_replyingToUsername != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to @$_replyingToUsername',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

            // Input bar
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: ChangeNotifierProvider.value(
                  value: _searchViewModel,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image preview
                      if (_selectedImageFile != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  _selectedImageFile!,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              // Upload spinner overlay
                              if (_uploadingImage)
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      color: Colors.black54,
                                      alignment: Alignment.center,
                                      child: const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // Remove button
                              if (!_uploadingImage)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: _clearSelectedImage,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Selected GIF preview
                      if (_selectedGifPreviewUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  _selectedGifPreviewUrl!,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: _clearSelectedGif,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                           // Photo button
                          // GestureDetector(
                          //   onTap: _pickImage,
                          //   child: Container(
                          //     width: 44,
                          //     height: 40,
                          //     margin: const EdgeInsets.only(right: 6),
                          //     decoration: BoxDecoration(
                          //       color: Colors.grey.shade100,
                          //       borderRadius: BorderRadius.circular(12),
                          //       border: Border.all(color: Colors.grey.shade300),
                          //     ),
                          //     alignment: Alignment.center,
                          //     child: Icon(
                          //       Icons.photo_camera_outlined,
                          //       size: 20,
                          //       color: Colors.grey.shade700,
                          //     ),
                          //   ),
                          // ),
                          // // GIF picker button
                          // GestureDetector(
                          //   onTap: _pickGif,
                          //   child: Container(
                          //     width: 44,
                          //     height: 40,
                          //     margin: const EdgeInsets.only(right: 8),
                          //     decoration: BoxDecoration(
                          //       color: Colors.grey.shade100,
                          //       borderRadius: BorderRadius.circular(12),
                          //       border: Border.all(color: Colors.grey.shade300),
                          //     ),
                          //     alignment: Alignment.center,
                          //     child: const Text(
                          //       'GIF',
                          //       style: TextStyle(
                          //         fontSize: 11,
                          //         fontWeight: FontWeight.w800,
                          //         color: Colors.black87,
                          //         letterSpacing: 0.5,
                          //       ),
                          //     ),
                          //   ),
                          // ),
                          Expanded(
                            child: FlutterTagger(
                              controller: _controller,
                              onSearch: (query, triggerCharacter) {
                                if (triggerCharacter == "@") {
                                  captionSearchViewModel.searchUser(query);
                                }
                                if (triggerCharacter == "#") {
                                  captionSearchViewModel.searchHashtag(query);
                                }
                              },
                              triggerCharacterAndStyles: {
                                '@': TextStyle(
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                '#': TextStyle(
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              },
                              triggerStrategy: TriggerStrategy.eager,
                              tagTextFormatter: (id, tag, triggerCharacter) =>
                                  '$triggerCharacter$id#$tag#',
                              overlayHeight: 200,
                              overlay: SearchResultOverlay(
                                tagController: _controller,
                                animation: const AlwaysStoppedAnimation(
                                  Offset.zero,
                                ),
                              ),
                              builder: (context, textFieldKey) {
                                return TextField(
                                  key: textFieldKey,
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  maxLines: null,
                                  style: const TextStyle(fontSize: 14),
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: InputDecoration(
                                    hintText: _replyingToUsername != null
                                        ? 'Reply to @$_replyingToUsername...'
                                        : 'Add a comment...',
                                    border: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                      borderSide: BorderSide(
                                        color: Color(0xFFAE9159),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (context, value, child) {
                              final canSend =
                                  (value.text.trim().isNotEmpty ||
                                      _selectedGifUrl != null ||
                                      _selectedImageUrl != null) &&
                                  !addingComment &&
                                  !_uploadingImage;
                              return GestureDetector(
                                onTap: canSend ? _addComment : null,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: canSend
                                        ? theme.primaryColor
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _TenorGif {
  final String id;
  final String url; // full-size for sending
  final String previewUrl; // smaller for thumbnails

  _TenorGif({required this.id, required this.url, required this.previewUrl});
}

class _TenorGifPicker extends StatefulWidget {
  const _TenorGifPicker();

  @override
  State<_TenorGifPicker> createState() => _TenorGifPickerState();
}

class _TenorGifPickerState extends State<_TenorGifPicker> {
  // Paste your KLIPY test key here — get one at https://klipy.com
  static const String _apiKey = '7UrnPvKjU6BCzy0guMtedUGtouNAHnbQvbjjou1S6ckPTVjvIJcF2UmLwhCVADvN';

  // KLIPY uses customer_id to track per-user recents/preferences.
  // For now use a stable anonymous value; later swap for the actual user ID.
  static const String _customerId = 'drivelife-anonymous';

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<_TenorGif> _gifs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://api.klipy.com/api/v1/$_apiKey/gifs/trending'
        '?customer_id=$_customerId&page=1&per_page=24',
      );
      final response = await http.get(uri);
      _handleResponse(response);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load GIFs';
        });
      }
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://api.klipy.com/api/v1/$_apiKey/gifs/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&customer_id=$_customerId&page=1&per_page=24',
      );
      final response = await http.get(uri);
      _handleResponse(response);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Search failed';
        });
      }
    }
  }

  void _handleResponse(http.Response response) {
    if (!mounted) return;

    if (response.statusCode != 200) {
      setState(() {
        _loading = false;
        _error = response.statusCode == 429
            ? 'Hit rate limit — try again in a moment'
            : 'API error (${response.statusCode})';
      });
      return;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;

    // KLIPY shape: { result: true, data: { data: [...], current_page, ... } }
    final outerData = body['data'] as Map<String, dynamic>?;
    final results = (outerData?['data'] as List?) ?? [];

    final gifs = results.map((item) {
      final m = item as Map<String, dynamic>;
      final file = m['file'] as Map<String, dynamic>? ?? {};

      // Try to pull the largest gif URL for sending, smallest for preview
      String? extractUrl(String size) {
        final sized = file[size] as Map<String, dynamic>?;
        if (sized == null) return null;
        // KLIPY returns format-keyed map: { gif: {url}, mp4: {url}, webp: {url} }
        return sized['gif']?['url']?.toString();
      }

      final fullUrl = extractUrl('lg') ??
          extractUrl('md') ??
          extractUrl('sm') ??
          extractUrl('xs') ??
          '';
      final previewUrl = extractUrl('sm') ??
          extractUrl('xs') ??
          extractUrl('md') ??
          fullUrl;

      return _TenorGif(
        id: m['slug']?.toString() ?? m['id']?.toString() ?? '',
        url: fullUrl,
        previewUrl: previewUrl,
      );
    }).where((g) => g.url.isNotEmpty).toList();

    setState(() {
      _gifs = gifs;
      _loading = false;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    // KLIPY's attribution guideline: use "Search KLIPY"
                    hintText: 'Search KLIPY',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _loadTrending();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFFAE9159)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFAE9159)))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                style: TextStyle(color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _gifs.isEmpty
                            ? Center(
                                child: Text(
                                  'No GIFs found',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : GridView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 1,
                                ),
                                itemCount: _gifs.length,
                                itemBuilder: (context, i) {
                                  final gif = _gifs[i];
                                  return GestureDetector(
                                    onTap: () => Navigator.pop(context, gif),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        color: Colors.grey.shade200,
                                        child: Image.network(
                                          gif.previewUrl,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, progress) {
                                            if (progress == null) return child;
                                            return const Center(
                                              child: SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),

              // KLIPY attribution (their TOS requires this)
              Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 4,
                  top: 4,
                ),
                child: Text(
                  'Powered by KLIPY',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}