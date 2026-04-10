import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:flutter/material.dart';

class _ConversationTile extends StatefulWidget {
  final ConversationPreview preview;
  final String myUserId;
  final Future<String> Function(String userId)? resolveUserName;
  final VoidCallback onTap; // ← added

  const _ConversationTile({
    required this.preview,
    required this.myUserId,
    required this.onTap,
    this.resolveUserName,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final name = widget.resolveUserName != null
        ? await widget.resolveUserName!(widget.preview.otherUserId)
        : 'User ${widget.preview.otherUserId}';
    if (mounted) setState(() => _displayName = name);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final lastMsg = preview.lastMessage;
    final hasUnread = preview.unreadCount > 0;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: scheme.primaryContainer,
        child: Text(
          _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(
        _displayName.isEmpty ? '...' : _displayName,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: lastMsg != null
          ? Text(
              lastMsg.senderId == widget.myUserId
                  ? 'You: ${lastMsg.content}'
                  : lastMsg.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            )
          : const Text(
              'No messages yet',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMsg != null)
            Text(
              _formatTime(lastMsg.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: hasUnread ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                preview.unreadCount > 99 ? '99+' : '${preview.unreadCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: widget.onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }
}
