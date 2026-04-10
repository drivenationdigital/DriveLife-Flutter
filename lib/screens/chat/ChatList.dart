// ============================================================
// INBOX SCREEN — Lists all conversations for the current user
// Drop this into your project and navigate to InboxScreen
// after login.
// ============================================================

import 'dart:async';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/ChatScreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Re-use your existing config + models ─────────────────────
// Make sure these are imported from your supabase_chat.dart:
//   SupabaseConfig, ChatRepository, Conversation, ChatMessage
// ─────────────────────────────────────────────────────────────

// ── Inbox Data Model ─────────────────────────────────────────
// Extends Conversation with the last message preview

class ConversationPreview {
  final Conversation conversation;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final String otherUserId;

  ConversationPreview({
    required this.conversation,
    required this.otherUserId,
    this.lastMessage,
    this.unreadCount = 0,
  });
}

// ── Inbox Repository ─────────────────────────────────────────

class InboxRepository {
  final _db = SupabaseConfig.client;

  /// Fetch all conversations with last message + unread count.
  Future<List<ConversationPreview>> getInbox(String myUserId) async {
    final data = await _db.rpc('get_inbox', params: {'p_user_id': myUserId});

    return (data as List).map((row) {
      final conv = Conversation(
        id: row['conv_id'] as String,
        participantIds: List<String>.from(row['participant_ids']),
        updatedAt: DateTime.parse(row['updated_at']),
      );

      final otherUserId = conv.participantIds.firstWhere(
        (id) => id != myUserId,
      );

      final hasLastMsg = row['last_message_content'] != null;

      return ConversationPreview(
        conversation: conv,
        otherUserId: otherUserId,
        unreadCount: (row['unread_count'] as num).toInt(),
        lastMessage: hasLastMsg
            ? ChatMessage(
                id: '',
                conversationId: conv.id,
                senderId: row['last_message_sender'] as String,
                content: row['last_message_content'] as String,
                createdAt: DateTime.parse(row['last_message_at']),
                isRead: true,
              )
            : null,
      );
    }).toList();
  }

  Future<ConversationPreview> _buildPreview(
    Conversation conv,
    String myUserId,
  ) async {
    // Last message
    final msgData = await _db
        .from('messages')
        .select()
        .eq('conversation_id', conv.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    // Unread count — messages not sent by me and not yet read
    final unreadData = await _db
        .from('messages')
        .select()
        .eq('conversation_id', conv.id)
        .neq('sender_id', myUserId)
        .isFilter('read_at', null);

    final otherUserId = conv.participantIds.firstWhere((id) => id != myUserId);

    return ConversationPreview(
      conversation: conv,
      otherUserId: otherUserId,
      lastMessage: msgData != null ? ChatMessage.fromMap(msgData) : null,
      unreadCount: (unreadData as List).length,
    );
  }

  /// Real-time stream that fires whenever any conversation updates.
  Stream<void> conversationUpdates(String myUserId) {
    final controller = StreamController<void>.broadcast();

    final channel = _db.channel('inbox:$myUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => controller.add(null),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'conversations',
        callback: (_) => controller.add(null),
      )
      ..subscribe();

    controller.onCancel = () {
      _db.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }
}

// ── Inbox Notifier ───────────────────────────────────────────

class InboxNotifier extends ChangeNotifier {
  final String myUserId;
  final _repo = InboxRepository();

  List<ConversationPreview> _previews = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;

  List<ConversationPreview> get previews => _previews;
  bool get loading => _loading;
  String? get error => _error;

  InboxNotifier({required this.myUserId});

  Future<void> initialize() async {
    await _loadInbox();

    // Refresh inbox whenever any message is sent or conversation updates
    _sub = _repo.conversationUpdates(myUserId).listen((_) {
      _loadInbox();
    });
  }

  Future<void> _loadInbox() async {
    try {
      _previews = await _repo.getInbox(myUserId);

      final ids = _previews.map((p) => p.otherUserId).toList();
      await UserProfileCache.instance.refresh(ids);

      _loading = false;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _loading = false;
    }
    notifyListeners();
  }

  Future<void> refresh() => _loadInbox();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class InboxScreen extends StatefulWidget {
  final String myUserId;
  final Future<String> Function(String userId)? resolveUserName;

  const InboxScreen({super.key, required this.myUserId, this.resolveUserName});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final InboxNotifier _notifier;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchActive = false;

  final List<UserProfile> _selectedForGroup = [];

  // Max group size excluding yourself = 3 others
  static const _maxGroupMembers = 3;

  @override
  void initState() {
    super.initState();
    _notifier = InboxNotifier(myUserId: widget.myUserId)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..initialize();
  }

  @override
  void dispose() {
    _notifier.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openChat(String otherUserId, String otherUserName) async {
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
          conversationId: null, // null = still loading
          myUserId: widget.myUserId,
          otherUserId: otherUserId, // ← add this
          otherUserName: otherUserName,
        ),
      ),
    ).then((_) => _notifier.refresh());
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

  void _startGroupChat() {
    if (_selectedForGroup.length < 2) return;

    // TODO next step: create group conversation with all selected IDs
    final ids = _selectedForGroup.map((p) => p.id).toList();
    final names = _selectedForGroup.map((p) => p.bestName).toList();

    debugPrint('[Group] Starting group with: $ids');

    setState(() {
      _searchActive = false;
      _selectedForGroup.clear();
    });
    _searchController.clear();
    _searchFocus.unfocus();

    // We'll wire this up in the next step
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
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
                                    ? NetworkImage(profile.imageUrl!)
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
                ? _NewChatSearchResults(
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

    if (_notifier.loading) {
      return Center(child: CircularProgressIndicator(color: theme.primaryColor,));
    }

    if (_notifier.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: ${_notifier.error}'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _notifier.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_notifier.previews.isEmpty) {
      return const Center(child: Text('No conversations yet.'));
    }

    return RefreshIndicator(
      onRefresh: _notifier.refresh,
      color: theme.primaryColor,
      child: ListView.separated(
        itemCount: _notifier.previews.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final preview = _notifier.previews[i];
          return CachedConversationTile(
            preview: preview,
            myUserId: widget.myUserId,
            onTap: () async {
              final profile = UserProfileCache.instance.getCached(
                preview.otherUserId,
              );
              final name = profile?.bestName ?? 'User ${preview.otherUserId}';
              _openChat(preview.otherUserId, name);
            },
          );
        },
      ),
    );
  }
}

// ── Search Results Widget ────────────────────────────────────

class _NewChatSearchResults extends StatefulWidget {
  final String query;
  final String myUserId;
  final void Function(String userId, String userName) onDirectMessage;
  final void Function(UserProfile profile) onAddToGroup;
  final List<String> selectedIds; // already picked
  final int maxReached;

  const _NewChatSearchResults({
    required this.query,
    required this.myUserId,
    required this.onDirectMessage,
    required this.onAddToGroup,
    required this.selectedIds,
    required this.maxReached,
  });

  @override
  State<_NewChatSearchResults> createState() => _NewChatSearchResultsState();
}

class _NewChatSearchResultsState extends State<_NewChatSearchResults> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _onQueryChanged(widget.query);
  }

  @override
  void didUpdateWidget(_NewChatSearchResults old) {
    super.didUpdateWidget(old);
    if (widget.query != old.query) _onQueryChanged(widget.query);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    // 400ms debounce — won't fire on every keystroke
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Reuses your existing PostsAPI — same as TagEntitiesScreen
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: 'users',
        taggedEntities: [],
      );

      // Filter out the current user from results
      final filtered = results
          .where((u) => u['entity_id'].toString() != widget.myUserId)
          .toList();

      if (mounted)
        setState(() {
          _results = filtered;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.primaryColor,));
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          widget.query.length < 2
              ? 'Type to search users...'
              : 'No users found for "${widget.query}"',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final user = _results[i];
        final profileImage = user['image'] as String?;
        final name = user['name'] as String? ?? 'Unknown';
        final userId = user['entity_id'].toString();
        final alreadySelected = widget.selectedIds.contains(userId);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: CircleAvatar(
            radius: 22,
            backgroundImage: profileImage != null && profileImage != 'search_q'
                ? NetworkImage(profileImage)
                : null,
            backgroundColor: Colors.grey.shade300,
            child: profileImage == null || profileImage == 'search_q'
                ? const Icon(Icons.person, size: 20, color: Colors.black38)
                : null,
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '@${user['name'] ?? ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),

          // ── Two action icons ──
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Direct message
              IconButton(
                tooltip: 'Send message',
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: () => widget.onDirectMessage(userId, name),
              ),

              // Add to group
              alreadySelected
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 22,
                    )
                  : IconButton(
                      tooltip: widget.maxReached > 0
                          ? 'Max members reached'
                          : 'Add to group',
                      icon: Icon(
                        Icons.group_add_rounded,
                        size: 22,
                        color: widget.maxReached > 0 ? Colors.grey : null,
                      ),
                      onPressed: widget.maxReached > 0
                          ? null
                          : () => widget.onAddToGroup(
                              UserProfile(
                                id: userId,
                                username: user['username'] ?? name,
                                displayName: name,
                                firstName: '',
                                lastName: '',
                                imageUrl: profileImage,
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
