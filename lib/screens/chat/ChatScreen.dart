import 'dart:async';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/chat/models.dart';
import 'package:drivelife/screens/chat/widgets/GroupInfo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ConversationPreview {
  final Conversation conversation;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final String? otherUserId; // null for group chats

  ConversationPreview({
    required this.conversation,
    this.otherUserId,
    this.lastMessage,
    this.unreadCount = 0,
  });

  bool get isGroup => conversation.isGroup;
}

class GroupNameDialog extends StatefulWidget {
  final List<UserProfile> members;

  const GroupNameDialog({super.key, required this.members});

  @override
  State<GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<GroupNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Auto-suggest group name from member names
    final names = widget.members.map((m) => m.bestName.split(' ').first);
    _controller = TextEditingController(text: names.join(', '));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Member preview
          Row(
            children: widget.members.map((m) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundImage: m.imageUrl != null
                          ? NetworkImage(m.imageUrl!)
                          : null,
                      child: m.imageUrl == null
                          ? Text(m.bestName[0].toUpperCase())
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.bestName.split(' ').first,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Group name',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String myUserId;
  final String? otherUserId;
  final String otherUserName;
  final bool isGroup; // ← NEW
  final String? groupName; // ← NEW
  final List<String> participantIds; // ← NEW

  const ChatScreen({
    super.key,
    this.conversationId,
    required this.myUserId,
    this.otherUserId,
    required this.otherUserName,
    this.isGroup = false,
    this.groupName,
    this.participantIds = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatNotifier? _notifier;
  List<ChatMessage> _cachedMessages = [];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  UserProfile? otherProfile; // 1-to-1 only
  Map<String, UserProfile> _groupProfiles = {}; // group only
  List<String> _resolvedParticipants = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String convId = widget.conversationId ?? '';
    print(convId.isEmpty
        ? 'No conversation ID provided, will attempt to find or create based on otherUserId'
        : 'Conversation ID provided: $convId');

     // ── Show cached messages INSTANTLY before any async work ──
    if (convId.isNotEmpty) {
      final cached = MessageCache.instance.get(convId);
      print('Cached conversation messages for $convId: ${cached?.length ?? 0}');
      if (cached != null && cached.isNotEmpty) {
        setState(() => _cachedMessages = cached.reversed.toList());
      }
    }

    if (convId.isEmpty && widget.otherUserId != null) {
      final conv = await ChatRepository().getOrCreateConversation(
        myUserId: widget.myUserId,
        otherUserId: widget.otherUserId!,
      );
      convId = conv.id;
    }

    // Resolve profiles
    if (widget.isGroup) {
      final ids = widget.participantIds
          .where((id) => id != widget.myUserId)
          .toList();
      _resolvedParticipants = ids;
      final profiles = await UserProfileCache.instance.resolve(ids);
      print('Resolved group profiles: ${profiles.length} for IDs: $ids');
      _groupProfiles = profiles;
    } else {
      otherProfile = UserProfileCache.instance.getCached(
        widget.otherUserId ?? '',
      );
    }

    await ChatRepository().markAsRead(convId, widget.myUserId);

    if (!mounted) return;

    setState(() {
      _notifier =
          ChatNotifier(conversationId: convId, myUserId: widget.myUserId)
            ..addListener(_onStateChange)
            ..initialize();
    });
  }

  void _onStateChange() {
    if (mounted && _notifier != null) {
      setState(() {});
      if (_scrollController.hasClients &&
          _scrollController.position.pixels < 200) {
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text;
    _inputController.clear();
    await _notifier?.sendMessage(text);
  }

  @override
  void dispose() {
    _notifier?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── AppBar ──────────────────────────────────────────────────

  Widget _buildAppBar(ThemeProvider theme) {
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: widget.isGroup ? _buildGroupAppBarTitle() : _buildDmAppBarTitle(),
    );
  }

  // 1-to-1 title: avatar + name
  Widget _buildDmAppBarTitle() {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundImage: otherProfile?.imageUrl != null
              ? NetworkImage(otherProfile!.imageUrl!)
              : null,
          child: otherProfile?.imageUrl == null
              ? Text(
                  (otherProfile?.bestName ?? widget.otherUserName).isNotEmpty
                      ? (otherProfile?.bestName ?? widget.otherUserName)[0]
                            .toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 14),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            otherProfile?.bestName ?? widget.otherUserName,
            style: const TextStyle(fontSize: 17),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Group title: stacked avatars + group name + member count
  Widget _buildGroupAppBarTitle() {
    final others = _resolvedParticipants.take(3).toList();

    return GestureDetector(
      onTap: () async {
        // Navigate to group info, get back updated participant list
        final updatedIds = await Navigator.push<List<String>>(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoScreen(
              conversationId: widget.conversationId!,
              myUserId: widget.myUserId,
              groupName: widget.groupName ?? 'Group',
              participantIds: widget.participantIds,
              onChanged: (updatedIds, updatedName) {
                setState(() {
                  _resolvedParticipants = updatedIds
                      .where((id) => id != widget.myUserId)
                      .toList();
                  // Optionally update group name display if you store it in state
                });
              },
            ),
          ),
        );

        // If members were added, refresh profiles
        if (updatedIds != null && mounted) {
          final newIds = updatedIds
              .where((id) => !_resolvedParticipants.contains(id))
              .toList();
          if (newIds.isNotEmpty) {
            final profiles = await UserProfileCache.instance.resolve(newIds);
            setState(() {
              _groupProfiles.addAll(profiles);
              _resolvedParticipants = updatedIds
                  .where((id) => id != widget.myUserId)
                  .toList();
            });
          }
        }
      },
      child: Row(
        children: [
          // Stacked avatars
          SizedBox(
            width: 46,
            height: 36,
            child: Stack(
              children: [
                for (int i = 0; i < others.length && i < 3; i++)
                  Positioned(
                    left: i * 12.0,
                    child: _buildStackedAvatar(others[i], i),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.groupName ?? 'Group',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.participantIds.length} members · tap for info',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedAvatar(String userId, int index) {
    final profile = _groupProfiles[userId];
    final imageUrl = profile?.imageUrl;
    final initial = profile?.bestName.isNotEmpty == true
        ? profile!.bestName[0].toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? Text(initial, style: const TextStyle(fontSize: 12))
            : null,
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, ThemeProvider theme) {
    final isMe = msg.senderId == widget.myUserId;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sender avatar — group chats only, other people's messages
          if (widget.isGroup && !isMe) ...[
            _buildSenderAvatar(msg.senderId),
            const SizedBox(width: 6),
          ],

          Flexible(
            child: Container(
              margin: EdgeInsets.only(
                top: 3,
                bottom: 3,
                left: isMe ? 60 : 0,
                right: isMe ? 0 : 60,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? theme.primaryColor
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Sender name — group chats only
                  if (widget.isGroup && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        _groupProfiles[msg.senderId]?.bestName ??
                            'User ${msg.senderId}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),

                  Text(
                    msg.content,
                    style: TextStyle(
                      color: isMe ? scheme.onPrimary : scheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatTime(msg.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: (isMe ? scheme.onPrimary : scheme.onSurface)
                          .withOpacity(0.6),
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

  Widget _buildSenderAvatar(String senderId) {
    final profile = _groupProfiles[senderId];
    final imageUrl = profile?.imageUrl;
    final initial = profile?.bestName.isNotEmpty == true
        ? profile!.bestName[0].toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 14,
      backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
      child: imageUrl == null
          ? Text(initial, style: const TextStyle(fontSize: 11))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: _buildAppBar(theme) as PreferredSizeWidget,
      body: _notifier == null
          ?   Column(
              children: [
                Expanded(
                  child: _cachedMessages.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(
                            color: theme.primaryColor,
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          itemCount: _cachedMessages.length,
                          itemBuilder: (context, i) =>
                              _buildBubble(_cachedMessages[i], theme),
                        ),
                ),
                // Disabled input while initializing
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            enabled: false,
                            decoration: InputDecoration(
                              hintText: 'Loading...',
                              filled: true,
                              fillColor: Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                if (_notifier?.error != null)
                  MaterialBanner(
                    content: Text(_notifier!.error!),
                    actions: [
                      TextButton(
                        onPressed: () => (),
                        // onPressed: () =>
                        //     setState(() => _notifier!._error = null),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),

                Expanded(
                  child: _notifier!.loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: theme.primaryColor,
                          ),
                        )
                      : _notifier!.messages.isEmpty
                      ? const Center(
                          child: Text('No messages yet. Say hello! 👋'),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          itemCount: _notifier!.messages.length,
                          itemBuilder: (context, i) =>
                              _buildBubble(_notifier!.messages[i], theme),
                        ),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _notifier!.refreshing
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          color: theme.primaryColor.withOpacity(0.06),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Loading new messages...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // Input bar
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Message...',
                              filled: true,
                              fillColor: Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _notifier!.sending
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.primaryColor,
                                  ),
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _send,
                                style: ElevatedButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(12),
                                  backgroundColor: theme.primaryColor,
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
