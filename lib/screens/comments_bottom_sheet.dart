import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/widgets/comment_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/interactions_api.dart';

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
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<dynamic> comments = [];
  bool loading = true;
  String? _replyingToUsername;
  String? _replyingToCommentId;

  // Add to state variables
  Map<String, bool> _expandedReplies =
      {}; // Track which comments have replies expanded
  String? _currentUserId; // Store current user ID

  @override
  void initState() {
    super.initState();
    _loadComments();
    _getCurrentUserId(); // ADD THIS
  }

  // Add method to get current user ID
  Future<void> _getCurrentUserId() async {
    // Get from your auth/user provider
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    setState(() {
      _currentUserId = userProvider.user?['id']?.toString();
    });
  }

  // Add delete method
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

  void _handleReply(String username, String commentId) {
    setState(() {
      _replyingToUsername = username;
      _replyingToCommentId = commentId;
      _controller.text = '@$username ';
    });
    _focusNode.requestFocus();
    // Move cursor to end
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

  Future<void> _addComment() async {
    if (_controller.text.trim().isEmpty) return;

    await InteractionsAPI.addComment(
      widget.postId,
      _controller.text.trim(),
      parentId: _replyingToCommentId != null
          ? int.tryParse(_replyingToCommentId!)
          : null,
    );
    _controller.clear();
    setState(() {
      _replyingToUsername = null;
      _replyingToCommentId = null;
    });
    _focusNode.unfocus();
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
            GestureDetector(
              onVerticalDragUpdate: (details) {
                // Allow dragging the sheet by the header
                if (details.primaryDelta! > 0) {
                  // Dragging down - you can implement custom behavior here
                }
              },
              child: Container(
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
            ),

            // Comments List
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
                      // Update ListView.builder itemBuilder
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        final replies = (c['replies'] ?? []) as List<dynamic>;
                        final username =
                            c['display_name'] ?? c['user_login'] ?? 'user';
                        final commentId = c['id'].toString();
                        final isExpanded = _expandedReplies[commentId] ?? false;
                        final isOwner =
                            c['user_id']?.toString() ==
                            _currentUserId; // ADD THIS

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CommentItem(
                              comment: c,
                              isOwner: isOwner, // PASS THIS
                              onReplyTap: () =>
                                  _handleReply(username, commentId),
                              onDeleteTap: isOwner
                                  ? () => _deleteComment(commentId, theme)
                                  : null, // ADD THIS
                            ),

                            // View/Hide replies button
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

                            // Show replies if expanded
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
                                  isOwner: isReplyOwner, // PASS THIS
                                  onReplyTap: () => _handleReply(
                                    replyUsername,
                                    r['id'].toString(),
                                  ),
                                  onDeleteTap: isReplyOwner
                                      ? () => _deleteComment(
                                          r['id'].toString(),
                                          theme,
                                        )
                                      : null, // ADD THIS
                                );
                              }),

                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
            ),

            // Reply indicator bar
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

            // Input bar - with proper keyboard handling
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
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        style: const TextStyle(fontSize: 14),
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _replyingToUsername != null
                              ? 'Reply to @$_replyingToUsername...'
                              : 'Add a comment...',
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(12),
                            ),
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
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _addComment,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _controller.text.trim().isNotEmpty
                              ? theme.primaryColor
                              : Colors.grey.shade300,
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
