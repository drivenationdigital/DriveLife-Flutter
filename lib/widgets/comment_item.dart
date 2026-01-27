import 'package:drivelife/widgets/formatted_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/interactions_api.dart';

class CommentItem extends StatefulWidget {
  final Map<String, dynamic> comment;
  final bool isReply;
  final bool isOwner;
  final VoidCallback? onReplyTap;
  final VoidCallback? onDeleteTap;

  const CommentItem({
    super.key,
    required this.comment,
    this.isReply = false,
    this.isOwner = false,
    this.onReplyTap,
    this.onDeleteTap,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  late bool liked;
  late int likeCount;
  bool _isExpanded = false;

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

  String _getTimeAgo(String? dateString) {
    if (dateString == null) return '';

    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 365) {
        final years = (difference.inDays / 365).floor();
        return '${years}y';
      } else if (difference.inDays > 30) {
        final months = (difference.inDays / 30).floor();
        return '${months}mo';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  void _handleDelete() {
    HapticFeedback.mediumImpact();
    widget.onDeleteTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final username = c['display_name'] ?? c['user_login'] ?? 'user';
    final timeAgo = _getTimeAgo(c['date']);
    final commentText = c['comment'] ?? "";

    return GestureDetector(
      onLongPress: widget.onDeleteTap != null ? _handleDelete : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.isReply ? 56 : 16,
          right: 16,
          top: 12,
          bottom: 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile picture
            CircleAvatar(
              radius: widget.isReply ? 14 : 18,
              backgroundColor: Colors.grey.shade300,
              backgroundImage:
                  (c['profile_image'] != null &&
                      c['profile_image'].toString().isNotEmpty)
                  ? NetworkImage(c['profile_image'])
                  : null,
              child:
                  (c['profile_image'] == null ||
                      c['profile_image'].toString().isEmpty)
                  ? Icon(
                      Icons.person,
                      size: widget.isReply ? 14 : 18,
                      color: Colors.grey.shade600,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username
                  Text(
                    username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      fontSize: 14,
                    ),
                  ),

                  // Comment text with FormattedText
                  if (commentText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    FormattedText(
                      text: commentText,
                      showAllText: _isExpanded,
                      maxTextLength: 100,
                      onSuffixPressed: () {
                        setState(() => _isExpanded = !_isExpanded);
                      },
                      suffix: _isExpanded ? 'less' : 'more',
                      onUserTagPressed: (userId) {
                        Navigator.pushNamed(
                          context,
                          '/view-profile',
                          arguments: {'userId': userId},
                        );
                      },
                      // style: const TextStyle(
                      //   color: Colors.black87,
                      //   fontSize: 14,
                      //   height: 1.4,
                      // ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Actions row
                  Row(
                    children: [
                      // Time ago
                      if (timeAgo.isNotEmpty) ...[
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Like count
                      if (likeCount > 0) ...[
                        Text(
                          likeCount == 1 ? '1 like' : '$likeCount likes',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Reply button
                      GestureDetector(
                        onTap: widget.onReplyTap,
                        child: Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Like button
            GestureDetector(
              onTap: _toggleLike,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: liked ? Colors.red : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
