import 'package:drivelife/widgets/comment_item.dart';
import 'package:flutter/material.dart';
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
  List<dynamic> comments = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    final data = await InteractionsAPI.fetchComments(widget.postId);
    setState(() {
      comments = data;
      loading = false;
    });
  }

  Future<void> _addComment() async {
    if (_controller.text.trim().isEmpty) return;
    await InteractionsAPI.addComment(widget.postId, _controller.text.trim());
    _controller.clear();
    await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          // ✅ COLUMN is now the parent of Expanded
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
            const Divider(),

            // ✅ THIS Expanded is now valid
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : comments.isEmpty
                  ? const Center(child: Text('No comments yet'))
                  : ListView.builder(
                      controller: widget.scrollController,
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        final replies = (c['replies'] ?? []) as List<dynamic>;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CommentItem(comment: c),
                            if (replies.isNotEmpty)
                              ...replies.map(
                                (r) => CommentItem(comment: r, isReply: true),
                              ),
                          ],
                        );
                      },
                    ),
            ),

            // Input bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
                    onPressed: _addComment,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
