import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/services/supabase_session.dart';
import 'package:drivelife/screens/chat/inbox_filter.dart';
import 'package:drivelife/screens/chat/ChatScreen.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/chat/models.dart';
import 'package:drivelife/screens/chat/widgets/SearchBar.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ConversationPreview {
  final Conversation conversation;
  final ChatMessage? lastMessage;
  final int unreadCount;

  /// The person on the other end, or null for a group — a group has no
  /// "other user", it has members.
  ///
  /// Nullable on purpose. It used to be a non-nullable String that groups
  /// filled with '', which made every `if (otherUserId == null)` guard
  /// unreachable and sent the empty string to the profile cache to resolve
  /// once per group row.
  final String? otherUserId;

  final bool isGroup;

  ConversationPreview({
    required this.conversation,
    required this.otherUserId,
    this.lastMessage,
    this.unreadCount = 0,
    this.isGroup = false,
  });
}

/// The inbox: every conversation, newest first, with a search that doubles
/// as the way to start a new one.
///
/// A section of Home rather than a screen of its own, so it takes the
/// shell's header and draws it inside its own scroll view. [chrome],
/// [header] and [headerHeight] are optional: pushed on its own as a route
/// it simply has no header to carry.
class InboxScreen extends StatefulWidget {
  final String myUserId;
  final Future<String> Function(String userId)? resolveUserName;

  /// Told which way the user is scrolling, so the shell can take the
  /// bottom bar away and bring it back.
  final ChromeVisibility? chrome;

  /// The shell's header, drawn inside this screen's scroll view rather
  /// than above it. Above, hiding it would mean shrinking the box it sits
  /// in, which resizes the viewport on every frame of the animation.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent up front.
  final double headerHeight;

  const InboxScreen({
    super.key,
    required this.myUserId,
    this.resolveUserName,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<InboxScreen> createState() => InboxScreenState();
}

/// Public so the screen above can hold a GlobalKey to it and call
/// [startNewConversation]. The alternative was a second copy of the
/// people-picker in MessagesScreen, reached by a different route and
/// drifting from this one.
class InboxScreenState extends State<InboxScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  InboxNotifier? _notifier;

  /// Put the cursor in the search field.
  ///
  /// Not "open a search screen": the field is already here, above the
  /// list, and the results replace the list in place. Focusing it is the
  /// whole gesture — the keyboard comes up and the first character
  /// swaps the conversations for people.
  void startNewConversation() {
    _searchFocus.requestFocus();
  }

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  bool _searchActive = false;

  /// Set when there is no usable account, or the Supabase token could not
  /// be fetched. Without it this screen shows a spinner for ever, because
  /// "no notifier yet" and "still loading" look the same from outside.
  String? _setupError;

  final List<UserProfile> _selectedForGroup = [];

  /// Max group size excluding yourself.
  static const _maxGroupMembers = 10;

  /// The search field's height, declared because the floating header has
  /// to know its extent before it is laid out. [_buildSearchBar] boxes
  /// itself to the same number, so the two cannot drift.
  static const double _searchBarHeight = 62;

  /// The pill row under it. Declared, because the sliver header
  /// has to know its extent before it is laid out.
  static const double _filterBarHeight = 56;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final account = Provider.of<AccountManager>(
      context,
      listen: false,
    ).activeAccount;

    if (account == null || account.token.isEmpty) {
      if (mounted) {
        setState(() => _setupError = 'Sign in to see your messages.');
      }
      return;
    }

    try {
      // SupabaseSession handles both halves — initialise, then apply
      // this account's token — and is idempotent, so this is a check
      // rather than a second exchange when the shell has already done
      // it.
      //
      // This screen used to be the ONLY thing that applied the token,
      // which was invisible while the inbox was a Home section built at
      // launch. It is a pushed screen now, so the shell establishes the
      // session and this confirms it.
      final ready = await SupabaseSession.ensure(
        Provider.of<AccountManager>(context, listen: false),
      );

      if (!ready) {
        throw Exception('could not sign in to messaging');
      }
    } catch (e, stack) {
      // Logged as well as shown. The banner has to stay short enough to
      // read, and the thing that actually tells you what broke -- a type
      // error inside the token exchange, say -- only fits in the console.
      debugPrint('[Inbox] token exchange failed: $e');
      debugPrintStack(stackTrace: stack, label: '[Inbox]');

      if (mounted) {
        setState(() => _setupError = 'Could not connect to messaging.\n$e');
      }
      return;
    }

    // The await above is the gap this used to fall through: leave the tab
    // while the token is in flight and dispose() runs first, so without
    // this the notifier is built against a dead State and never released.
    if (!mounted) return;

    final notifier =
        InboxNotifier(
          myUserId: widget.myUserId,
          unreadCountProvider: Provider.of<UnreadCountProvider>(
            context,
            listen: false,
          ),
        )..addListener(() {
          if (mounted) setState(() {});
        });

    setState(() {
      _notifier = notifier;
      _setupError = null;
    });

    notifier.initialize();
  }

  @override
  void dispose() {
    _notifier?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _exitSearch() {
    setState(() {
      _searchActive = false;
      _selectedForGroup.clear();
    });
    _searchController.clear();
    _searchFocus.unfocus();
  }

  void _openChat(
    String otherUserId,
    String otherUserName,
    String? conversationId,
  ) async {
    _exitSearch();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId, // null = still loading
          myUserId: widget.myUserId,
          otherUserId: otherUserId,
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

    final name = await showDialog<String>(
      context: context,
      builder: (_) => GroupNameDialog(members: _selectedForGroup),
    );

    if (name == null || name.trim().isEmpty || !mounted) return;

    final ids = _selectedForGroup.map((p) => p.id).toList();

    final conv = await ChatRepository().createGroupConversation(
      myUserId: widget.myUserId,
      otherUserIds: ids,
      groupName: name.trim(),
    );

    if (!mounted) return;
    _exitSearch();

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

  // ── layout ───────────────────────────────────────────────────────────

  @override
  /// Kept alive across tab switches.
  ///
  /// A TabBarView is a PageView, and a PageView disposes the page you
  /// scroll away from — so every switch to Notifications and back was
  /// destroying this State and rebuilding it from nothing, spinner and
  /// all. The conversation list is already cached and already refreshes
  /// behind itself; the only thing missing was being allowed to survive.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      // Every scroll reports to the shell through this one listener, which
      // is what takes the bottom bar away and brings it back.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          onRefresh: () async => _notifier?.refresh(),
          color: theme.primaryColor,
          child: CustomScrollView(
            controller: _scrollController,
            // Always scrollable, so a short list still reaches far enough
            // for pull-to-refresh and for the chrome to scroll away.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _floatingChrome(),
              if (_selectedForGroup.isNotEmpty) _selectedPills(theme),
              ..._body(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// The shell's header with the search field under it.
  ///
  /// Floating: gone as you read down the list, back the moment you scroll
  /// up, without having to reach the top.
  Widget _floatingChrome() {
    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        height: widget.headerHeight + _searchBarHeight + _filterBarHeight,
        vsync: this,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.header != null) widget.header!,
            _buildSearchBar(),
            _buildFilterBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      height: _searchBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => _searchActive = v.trim().isNotEmpty),
          decoration: InputDecoration(
            hintText: 'Search people to message',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
            suffixIcon: _searchActive
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: _exitSearch,
                  )
                : null,
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            // Dense, because the box around this is 46 tall and a filled
            // field with a prefix icon asks for 48 unless told otherwise.
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  /// The people picked for a new group, as removable chips.
  Widget _selectedPills(ThemeProvider theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
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
                              ? CachedNetworkImageProvider(profile.imageUrl!)
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
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () =>
                            setState(() => _selectedForGroup.remove(profile)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            if (_selectedForGroup.length >= 2)
              FilledButton.icon(
                onPressed: _startGroupChat,
                icon: const Icon(Icons.group, size: 17),
                label: const Text('Start'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Whatever belongs under the chrome: search results, or the inbox, or
  /// the state it is in instead.
  InboxFilter _filter = InboxFilter.all;

  /// The pills, as drawn: one on, the rest off.
  Widget _buildFilterBar() {
    final theme = Provider.of<ThemeProvider>(context);

    return Container(
      height: _filterBarHeight,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (final f in InboxFilter.values) ...[
            _pill(f, theme),
            if (f != InboxFilter.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _pill(InboxFilter f, ThemeProvider theme) {
    final selected = f == _filter;

    return Material(
      color: selected ? const Color(0xFF111111) : Colors.white,
      shape: StadiumBorder(
        side: selected
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFE2E2E2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (selected) return;
          setState(() => _filter = f);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            f.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF111111),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(ThemeProvider theme) {
    if (_searchActive) {
      return [
        SliverFillRemaining(
          hasScrollBody: true,
          child: NewChatSearchResults(
            query: _searchController.text.trim(),
            myUserId: widget.myUserId,
            onDirectMessage: _openChat,
            onAddToGroup: _addToGroup,
            selectedIds: _selectedForGroup.map((p) => p.id).toList(),
            maxReached: _selectedForGroup.length >= _maxGroupMembers ? 1 : 0,
          ),
        ),
      ];
    }

    if (_setupError != null) {
      return [_message(Icons.lock_outline, _setupError!, onRetry: _connect)];
    }

    if (_notifier == null || _notifier!.loading) {
      return [
        _fill(
          Center(child: CircularProgressIndicator(color: theme.primaryColor)),
        ),
      ];
    }

    if (_notifier!.error != null) {
      return [
        _message(
          Icons.cloud_off,
          'Could not load your messages.',
          onRetry: _notifier!.refresh,
        ),
      ];
    }

    final shown = _notifier!.previews
        .where(
          (p) => matchesInboxFilter(
            _filter,
            isGroup: p.isGroup,
            unreadCount: p.unreadCount,
          ),
        )
        .toList();

    if (shown.isEmpty) {
      return [
        _message(
          Icons.chat_bubble_outline,
          emptyInboxMessage(_filter),
          // Only the unfiltered empty inbox gets the "go and find
          // somebody" line. Under a pill the list is not empty, it is
          // hidden, and the thing to do is tap All.
          detail: _filter == InboxFilter.all
              ? 'Search for someone above to start a conversation.'
              : null,
        ),
      ];
    }

    return [_conversationList(shown)];
  }

  Widget _fill(Widget child) =>
      SliverFillRemaining(hasScrollBody: false, child: child);

  /// A state that is not a list, under the chrome rather than replacing it
  /// — the way out of an empty inbox is the search field above.
  Widget _message(
    IconData icon,
    String title, {
    String? detail,
    VoidCallback? onRetry,
  }) {
    final theme = Provider.of<ThemeProvider>(context);

    return _fill(
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                ),
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conversationList(List<ConversationPreview> previews) {
    return SliverList.builder(
      itemCount: previews.length,
      itemBuilder: (context, i) {
        final preview = previews[i];
        final convId = preview.conversation.id;

        // A hairline between rows, inset past the avatar so it starts
        // under the name. The rows carry enough air to stand apart
        // without one, but the time column on the right now needs an
        // edge to sit against or it floats.
        return Dismissible(
          key: ValueKey(convId),
          direction: DismissDirection.endToStart,
          background: _deleteBackground(),
          confirmDismiss: (_) => _confirmDelete(preview.isGroup),
          onDismissed: (_) => _delete(preview),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CachedConversationTile(
                preview: preview,
                myUserId: widget.myUserId,
                onTap: () => _openPreview(preview),
              ),
              if (i < previews.length - 1)
                const Padding(
                  padding: EdgeInsets.only(left: 84),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F0F0),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openPreview(ConversationPreview preview) {
    if (preview.isGroup) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: preview.conversation.id,
            myUserId: widget.myUserId,
            otherUserName: preview.conversation.groupName ?? 'Group',
            isGroup: true,
            groupName: preview.conversation.groupName,
            participantIds: preview.conversation.participantIds,
          ),
        ),
      ).then((_) => _notifier?.refresh());
      return;
    }

    final otherId = preview.otherUserId;
    if (otherId == null || otherId.isEmpty) return;

    final profile = UserProfileCache.instance.getCached(otherId);
    _openChat(
      otherId,
      profile?.bestName ?? 'User $otherId',
      preview.conversation.id,
    );
  }

  Widget _deleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      color: const Color(0xFFE53935),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 24),
          SizedBox(height: 2),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(bool isGroup) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isGroup ? 'Leave group' : 'Delete conversation'),
        content: Text(
          isGroup
              ? 'You will leave this group and no longer receive its messages.'
              : "This hides the conversation. You'll see it again if they "
                    'message you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            child: Text(isGroup ? 'Leave' : 'Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(ConversationPreview preview) async {
    final convId = preview.conversation.id;

    // Gone from the list straight away; put back if the call fails.
    _notifier?.removePreview(convId);

    try {
      if (preview.isGroup) {
        await SupabaseConfig.client.rpc(
          'leave_group',
          params: {'p_conversation_id': convId, 'p_user_id': widget.myUserId},
        );
      } else {
        await ChatRepository().deleteConversation(convId);
      }

      MessageCache.instance.clear(convId);
    } catch (e) {
      debugPrint('[Inbox] delete failed: $e');
      _notifier?.refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete that conversation.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
