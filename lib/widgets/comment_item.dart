import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/interactions_api.dart';

class CommentItem extends StatefulWidget {
  final Map<String, dynamic> comment;
  final bool isReply;
  final VoidCallback? onReplyTap;

  const CommentItem({
    super.key,
    required this.comment,
    this.isReply = false,
    this.onReplyTap,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  late bool liked;
  late int likeCount;

  @override
  void initState() {
    super.initState();
    liked = widget.comment['liked'] ?? false;
    likeCount = widget.comment['likes_count'] ?? 0;
  }

  Future<void> _toggleLike() async {
    HapticFeedback.lightImpact();

    setState(() {
      liked = !liked;
      likeCount += liked ? 1 : -1;
    });

    final res = await InteractionsAPI.maybeLikeComment(
      widget.comment['id'],
      widget.comment['user_id'],
    );

    if (res == null) {
      // rollback UI
      setState(() {
        liked = !liked;
        likeCount += liked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final username = c['display_name'] ?? c['user_login'] ?? 'user';

    return Padding(
      padding: EdgeInsets.only(
        left: widget.isReply ? 48 : 16,
        right: 16,
        top: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(c['profile_image'] ?? ''),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const TextSpan(text: " "),
                      TextSpan(
                        text: c['comment'] ?? "",
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      "${likeCount} likes",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: widget.onReplyTap,
                      child: const Text(
                        "Reply",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _toggleLike,
            child: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: liked ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
