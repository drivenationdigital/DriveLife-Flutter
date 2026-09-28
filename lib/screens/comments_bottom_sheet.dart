import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/post_poll.dart';
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

  /// The post's poll, if it has one. Null for almost every post, and the
  /// sheet then renders exactly what it rendered before polls existed.
  PostPoll? _poll;
  bool _voting = false;
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

  bool _enableGifs = true;
  bool _enableImages = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _getCurrentUserId();
    _loadPoll();
  }

  /// Fetched alongside the comments rather than carried on the post, so the
  /// feed is untouched by any of this. A failure leaves _poll null, which is
  /// the same as a post without one — a poll that will not load is not worth
  /// breaking the comments over.
  Future<void> _loadPoll() async {
    final postId = int.tryParse(widget.postId) ?? 0;
    if (postId <= 0) return;

    final poll = await PostsAPI.fetchPostPoll(postId);
    if (!mounted || poll == null) return;

    setState(() => _poll = poll);
  }

  /// Records a vote and redraws from the server's answer.
  ///
  /// A vote cannot be changed, so the server's copy is what shows — if one was
  /// already cast, this reveals that one rather than pretending the tap
  /// counted.
  Future<void> _vote(int optionId) async {
    if (_voting || _poll == null || _poll!.hasVoted) return;

    setState(() => _voting = true);

    try {
      final poll = await PostsAPI.votePostPoll(
        postId: _poll!.postId,
        optionId: optionId,
      );

      if (!mounted) return;
      setState(() => _poll = poll);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_enableImages && _selectedImageFile != null) {
      setState(() {
        _selectedImageFile = null;
        _selectedImageUrl = null;
      });
    }

    if (!_enableGifs && _selectedGifUrl != null) {
      setState(() {
        _selectedGifUrl = null;
        _selectedGifPreviewUrl = null;
      });
    }
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
    final response = await InteractionsAPI.fetchComments(widget.postId);
    if (mounted) {
      setState(() {
        comments = response.comments;
        _enableGifs = response.enableGifs;
        _enableImages = response.enableImages;
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

    // Set the file as selected; do NOT upload yet — that happens on send.
    setState(() {
      _selectedImageFile = File(picked.path);
      _selectedImageUrl =
          null; // unused now; kept for backwards compat if you want
      _uploadingImage = false;

      // Clear any GIF — only one media item per comment
      _selectedGifUrl = null;
      _selectedGifPreviewUrl = null;
    });
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
    final hasGif = _selectedGifUrl != null && _enableGifs;
    final hasImage = _selectedImageFile != null && _enableImages;

    if (!hasText && !hasGif && !hasImage) return;
    if (addingComment) return;

    setState(() => addingComment = true);

    // If a photo is attached, upload it to Cloudflare first
    String? uploadedImageId;
    if (hasImage) {
      setState(() => _uploadingImage = true);

      uploadedImageId = await InteractionsAPI.uploadCommentImage(
        _selectedImageFile!,
      );

      if (!mounted) return;
      setState(() => _uploadingImage = false);

      if (uploadedImageId == null) {
        setState(() => addingComment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not upload photo. Try again.')),
        );
        return;
      }
    }

    await InteractionsAPI.addComment(
      widget.postId,
      _controller.formattedText,
      parentId: _replyingToCommentId != null
          ? int.tryParse(_replyingToCommentId!)
          : null,
      gifUrl: _selectedGifUrl,
      imageUrl:
          uploadedImageId, // stored in DB; backend resolves to CDN URL on read
    );

    _controller.clear();

    if (!mounted) return;
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

            // The poll, above the comments and always in view: it is the
            // thing the author asked, and scrolling it away with the comments
            // would bury the question under the answers to it.
            if (_poll != null)
              _PollCard(
                poll: _poll!,
                busy: _voting,
                primaryColor: theme.primaryColor,
                onVote: _vote,
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
                          // Photo button — hidden if images are disabled
                          if (_enableImages)
                            GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                width: 44,
                                height: 40,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.photo_camera_outlined,
                                  size: 20,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          // GIF button — hidden if GIFs are disabled
                          if (_enableGifs)
                            GestureDetector(
                              onTap: _pickGif,
                              child: Container(
                                width: 44,
                                height: 40,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'GIF',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
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
                                      _selectedImageFile != null) &&
                                  !addingComment;
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
  static const String _apiKey =
      '7UrnPvKjU6BCzy0guMtedUGtouNAHnbQvbjjou1S6ckPTVjvIJcF2UmLwhCVADvN';

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

    final gifs = results
        .map((item) {
          final m = item as Map<String, dynamic>;
          final file = m['file'] as Map<String, dynamic>? ?? {};

          // Try to pull the largest gif URL for sending, smallest for preview
          String? extractUrl(String size) {
            final sized = file[size] as Map<String, dynamic>?;
            if (sized == null) return null;
            // KLIPY returns format-keyed map: { gif: {url}, mp4: {url}, webp: {url} }
            return sized['gif']?['url']?.toString();
          }

          final fullUrl =
              extractUrl('lg') ??
              extractUrl('md') ??
              extractUrl('sm') ??
              extractUrl('xs') ??
              '';
          final previewUrl =
              extractUrl('sm') ??
              extractUrl('xs') ??
              extractUrl('md') ??
              fullUrl;

          return _TenorGif(
            id: m['slug']?.toString() ?? m['id']?.toString() ?? '',
            url: fullUrl,
            previewUrl: previewUrl,
          );
        })
        .where((g) => g.url.isNotEmpty)
        .toList();

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
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFAE9159),
                        ),
                      )
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
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
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
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A post's poll, as it appears in the comments sheet.
///
/// Three states, and which shows is decided by the poll rather than by taps:
///
///  * open and unanswered — the options are buttons;
///  * open and answered — results, because a vote is final and there is
///    nothing left to press;
///  * closed — results for everyone, answered or not, with the winner called.
class _PollCard extends StatelessWidget {
  final PostPoll poll;
  final bool busy;
  final Color primaryColor;
  final ValueChanged<int> onVote;

  const _PollCard({
    required this.poll,
    required this.busy,
    required this.primaryColor,
    required this.onVote,
  });

  /// What the line under the options says.
  String _footer() {
    final votes = poll.totalVotes;
    final plural = votes == 1 ? 'vote' : 'votes';

    if (poll.isClosed) {
      final winners = poll.winners;

      if (winners.isEmpty) return 'Poll closed · nobody voted';

      if (winners.length > 1) {
        return 'Tied · $votes $plural';
      }

      return 'Winner: ${winners.first.label} · $votes $plural';
    }

    final left = poll.timeLeftLabel;
    final base = votes == 0
        ? 'Be the first to vote'
        : '$votes $plural so far';

    return left == null ? base : '$base · $left';
  }

  @override
  Widget build(BuildContext context) {
    // Closed shows everyone the result, whether they answered or not: there
    // is nothing left to protect once voting is over.
    final showResults = poll.isClosed || poll.hasVoted;
    final winners = poll.isClosed ? poll.winners : const <PollOption>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                poll.isClosed ? Icons.how_to_vote_outlined : Icons.poll_outlined,
                size: 16,
                color: poll.isClosed ? Colors.grey.shade600 : primaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                poll.isClosed ? 'POLL CLOSED' : 'POLL',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: poll.isClosed ? Colors.grey.shade600 : primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            poll.question,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),

          for (final option in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: showResults
                  ? _Result(
                      option: option,
                      percent: poll.percentFor(option),
                      mine: option.id == poll.myOptionId,
                      won: winners.any((w) => w.id == option.id),
                      primaryColor: primaryColor,
                    )
                  : _Choice(
                      label: option.label,
                      busy: busy,
                      onTap: () => onVote(option.id),
                    ),
            ),

          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  _footer(),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),

              // Only the author, and only once somebody has voted — an empty
              // list is not worth a button. The endpoint checks again.
              if (poll.isAuthor && poll.totalVotes > 0)
                GestureDetector(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    useSafeArea: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    builder: (_) => _PollVotersSheet(
                      poll: poll,
                      primaryColor: primaryColor,
                    ),
                  ),
                  child: Text(
                    'See who voted',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One option, before voting.
class _Choice extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// One option, once the results are showing: a bar behind the label.
class _Result extends StatelessWidget {
  final PollOption option;
  final int percent;
  final bool mine;

  /// Took the most votes in a closed poll. More than one option can win.
  final bool won;
  final Color primaryColor;

  const _Result({
    required this.option,
    required this.percent,
    required this.mine,
    required this.won,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    // The winner is filled more strongly than a bar you merely picked: after
    // a poll closes the result is the point, not who you were.
    final fill = won
        ? primaryColor.withValues(alpha: 0.38)
        : mine
        ? primaryColor.withValues(alpha: 0.22)
        : Colors.grey.shade300;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(height: 44, width: double.infinity, color: Colors.white),
          LayoutBuilder(
            builder: (context, constraints) => Container(
              height: 44,
              width: constraints.maxWidth * (percent / 100),
              color: fill,
            ),
          ),
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (won) ...[
                    const Icon(Icons.emoji_events, size: 15),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: (mine || won)
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (mine) ...[
                    Icon(Icons.check_circle, size: 15, color: primaryColor),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who voted for what — the author's view only.
///
/// People answering a poll can see that the person who asked will know what
/// they picked; nobody else gets this, and the endpoint refuses anyone else
/// regardless of what the app offers.
class _PollVotersSheet extends StatefulWidget {
  final PostPoll poll;
  final Color primaryColor;

  const _PollVotersSheet({required this.poll, required this.primaryColor});

  @override
  State<_PollVotersSheet> createState() => _PollVotersSheetState();
}

class _PollVotersSheetState extends State<_PollVotersSheet> {
  List<PollVoter>? _voters;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);

    try {
      final voters = await PostsAPI.fetchPollVoters(widget.poll.postId);
      if (!mounted) return;
      setState(() => _voters = voters);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
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
            'Who voted',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          Expanded(child: _buildBody(controller)),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
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
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final voters = _voters;

    if (voters == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final option in widget.poll.options) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${option.votes}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: widget.primaryColor,
                  ),
                ),
              ],
            ),
          ),

          ...(() {
            final picked =
                voters.where((v) => v.optionId == option.id).toList();

            if (picked.isEmpty) {
              return [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'No votes yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ];
            }

            return picked.map(
              (voter) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: voter.avatar != null
                          ? NetworkImage(voter.avatar!)
                          : null,
                      child: voter.avatar == null
                          ? Text(
                              voter.displayName.isEmpty
                                  ? '?'
                                  : voter.displayName
                                        .substring(0, 1)
                                        .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        voter.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            );
          })(),

          const Divider(height: 18),
        ],
      ],
    );
  }
}
