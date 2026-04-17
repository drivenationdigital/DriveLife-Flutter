import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/ChatScreen.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/chat/models.dart';
import 'package:drivelife/screens/chat/widgets/SearchBar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ConversationPreview {
  final Conversation conversation;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final String otherUserId;
  final bool isGroup;

  ConversationPreview({
    required this.conversation,
    required this.otherUserId,
    this.lastMessage,
    this.unreadCount = 0,
    this.isGroup = false,
  });
}

class InboxScreen extends StatefulWidget {
  final String myUserId;
  final Future<String> Function(String userId)? resolveUserName;

  const InboxScreen({super.key, required this.myUserId, this.resolveUserName});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  InboxNotifier? _notifier;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchActive = false;

  final List<UserProfile> _selectedForGroup = [];

  // Max group size excluding yourself = 3 others
  static const _maxGroupMembers = 10;

  @override
  void initState() {
    super.initState();

    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final currentAccount = accountManager.activeAccount;

    if (currentAccount != null && currentAccount.token != '') {
      SupabaseTokenManager.fetchAndStore(currentAccount.token).then((token) {
        _notifier =
            InboxNotifier(
                myUserId: widget.myUserId,
                unreadCountProvider: Provider.of<UnreadCountProvider>(
                  context,
                  listen: false,
                ),
              )
              ..addListener(() {
                if (mounted) setState(() {});
              })
              ..initialize();
      });
    }
  }

  @override
  void dispose() {
    _notifier?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openChat(
    String otherUserId,
    String otherUserName,
    String? conversationId,
  ) async {
    setState(() {
      _searchActive = false;
    });
    _searchController.clear();
    _searchFocus.unfocus();

    // Navigate immediately with a loading state
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId, // null = still loading
          myUserId: widget.myUserId,
          otherUserId: otherUserId, // ← add this
          otherUserName: otherUserName,
        ),
      ),
    ).then((_) => _notifier?.refresh());
  }

  void _addToGroup(UserProfile profile) {
    if (_selectedForGroup.any((p) => p.id == profile.id)) return;
    if (_selectedForGroup.length >= _maxGroupMembers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max $_maxGroupMembers people in a group for now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _selectedForGroup.add(profile));
  }

  void _startGroupChat() async {
    if (_selectedForGroup.length < 2) return;

    // Prompt for group name
    final name = await showDialog<String>(
      context: context,
      builder: (_) => GroupNameDialog(members: _selectedForGroup),
    );

    if (name == null || name.trim().isEmpty || !mounted) return;

    final ids = _selectedForGroup.map((p) => p.id).toList();
    final repo = ChatRepository();

    final conv = await repo.createGroupConversation(
      myUserId: widget.myUserId,
      otherUserIds: ids,
      groupName: name.trim(),
    );

    setState(() {
      _searchActive = false;
      _selectedForGroup.clear();
    });
    _searchController.clear();
    _searchFocus.unfocus();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conv.id,
          myUserId: widget.myUserId,
          otherUserName: name.trim(),
          isGroup: true,
          groupName: name.trim(),
          participantIds: [widget.myUserId, ...ids],
        ),
      ),
    );

    _notifier?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: 'Search users to message...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                suffixIcon: _searchActive
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _searchActive = false;
                            _selectedForGroup.clear();
                          });
                          _searchController.clear();
                          _searchFocus.unfocus();
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {
                  _searchActive = v.trim().isNotEmpty;
                });
              },
            ),
          ),

          // ── Selected users pills ──
          if (_selectedForGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  // Scrollable pills
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _selectedForGroup.map((profile) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              avatar: CircleAvatar(
                                backgroundImage: profile.imageUrl != null
                                    ? CachedNetworkImageProvider(
                                        profile.imageUrl!,
                                      )
                                    : null,
                                child: profile.imageUrl == null
                                    ? Text(
                                        profile.bestName[0].toUpperCase(),
                                        style: const TextStyle(fontSize: 11),
                                      )
                                    : null,
                              ),
                              label: Text(
                                profile.username,
                                style: const TextStyle(fontSize: 13),
                              ),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setState(
                                  () => _selectedForGroup.remove(profile),
                                );
                              },
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Start group button — only shown when 2+ selected
                  if (_selectedForGroup.length >= 2)
                    TextButton.icon(
                      onPressed: _startGroupChat,
                      icon: const Icon(Icons.group, size: 18),
                      label: const Text('Start'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Search results OR conversation list ──
          Expanded(
            child: _searchActive
                ? NewChatSearchResults(
                    query: _searchController.text.trim(),
                    myUserId: widget.myUserId,
                    onDirectMessage: _openChat,
                    onAddToGroup: _addToGroup,
                    selectedIds: _selectedForGroup.map((p) => p.id).toList(),
                    maxReached: _selectedForGroup.length >= _maxGroupMembers
                        ? 1
                        : 0,
                  )
                : _buildInbox(),
          ),
        ],
      ),
    );
  }

  Widget _buildInbox() {
    final theme = Provider.of<ThemeProvider>(context);

    if (_notifier?.loading ?? true) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_notifier?.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load chats: ${_notifier?.error}'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _notifier?.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_notifier?.previews.isEmpty ?? true) {
      return const Center(child: Text('No conversations yet.'));
    }

    return RefreshIndicator(
      onRefresh: _notifier?.refresh ?? () async {},
      color: theme.primaryColor,
      child: ListView.separated(
        itemCount: _notifier?.previews.length ?? 0,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final preview = _notifier?.previews[i];
          if (preview == null) return const SizedBox.shrink();
          final isGroup = preview.isGroup;
          final convId = preview.conversation.id;

          return Dismissible(
            key: ValueKey(convId),
            direction: DismissDirection.endToStart, // swipe left
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red.shade400,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, color: Colors.white, size: 26),
                  SizedBox(height: 4),
                  Text(
                    'Delete',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Confirm before completing the dismissal
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete conversation'),
                  content: Text(
                    isGroup
                        ? 'You will leave this group and no longer receive messages.'
                        : 'This will hide the conversation. You\'ll see it again if they message you.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },

            onDismissed: (_) async {
              // Optimistically remove from list
              _notifier!.removePreview(convId);

              try {
                if (isGroup) {
                  await SupabaseConfig.client.rpc(
                    'leave_group',
                    params: {
                      'p_conversation_id': convId,
                      'p_user_id': widget.myUserId,
                    },
                  );
                } else {
                  // Soft delete for 1-to-1
                  await ChatRepository().deleteConversation(convId);
                }

                MessageCache.instance.clear(convId);
              } catch (e) {
                _notifier!.refresh();
                if (mounted) {
                  print('Failed to delete conversation: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },

            child: CachedConversationTile(
              preview: preview,
              myUserId: widget.myUserId,
              onTap: () {
                if (isGroup) {
                  // Group chat — navigate directly with conversation ID
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        conversationId: preview.conversation.id,
                        myUserId: widget.myUserId,
                        otherUserName:
                            preview.conversation.groupName ?? 'Group',
                        isGroup: true,
                        groupName: preview.conversation.groupName,
                        participantIds: preview.conversation.participantIds,
                      ),
                    ),
                  ).then((_) => _notifier?.refresh());
                } else {
                  // 1-to-1 — resolve name from cache
                  final otherId = preview.otherUserId;
                  if (otherId == null) return;
                  final profile = UserProfileCache.instance.getCached(otherId);
                  final name = profile?.bestName ?? 'User $otherId';
                  _openChat(otherId, name, preview.conversation.id);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
