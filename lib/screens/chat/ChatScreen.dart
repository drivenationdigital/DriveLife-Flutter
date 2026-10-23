import 'dart:async';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/chat/widgets/GroupInfo.dart';
import 'package:drivelife/screens/chat/message_grouping.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ConversationPreview used to be declared here as well as in
// ChatList.dart. Nothing in this file referenced it, and two different
// types of the same name in one import graph is a trap worth closing: the
// tile in ChatProfileCache takes the other one, and an accidental use of
// this would have failed with a message about ConversationPreview not
// being assignable to ConversationPreview.

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

  /// Everyone in the group, me included, as the conversations row has it.
  ///
  /// The one list. Seeded from the widget so the title bar has something
  /// to draw on the first frame, and replaced by [_refreshGroup] from
  /// then on.
  late List<String> _participants = List.of(widget.participantIds);

  /// Same reasoning for the name, which the info screen can also change.
  late String _groupName = widget.groupName ?? 'Group';

  /// Everyone but me — the avatar stack, and who needs a profile.
  List<String> get _others =>
      _participants.where((id) => id != widget.myUserId).toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String convId = widget.conversationId ?? '';
    print(
      convId.isEmpty
          ? 'No conversation ID provided, will attempt to find or create based on otherUserId'
          : 'Conversation ID provided: $convId',
    );

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
      _groupProfiles = await UserProfileCache.instance.resolve(_others);
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      // A hairline instead of a shadow. The thread is white and the bar is
      // white; a drop shadow between them is the only thing that would say
      // otherwise, and it reads as heavier than it is.
      shape: const Border(bottom: BorderSide(color: Color(0xFFEFEFEF))),
      foregroundColor: const Color(0xFF111111),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: widget.isGroup ? _buildGroupAppBarTitle() : _buildDmAppBarTitle(),
    );
  }

  // 1-to-1 title: avatar + name
  Widget _buildDmAppBarTitle() {
    final name = otherProfile?.bestName ?? widget.otherUserName;
    final imageUrl = otherProfile?.imageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFEFEFEF),
          backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
          child: hasImage
              ? null
              : Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Group title: stacked avatars + group name + member count
  Widget _buildGroupAppBarTitle() {
    final others = _others.take(3).toList();

    return GestureDetector(
      onTap: () async {
        await Navigator.push<List<String>>(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoScreen(
              conversationId: widget.conversationId!,
              myUserId: widget.myUserId,
              groupName: _groupName,
              participantIds: _participants,
              // Fires on each change while the screen is open, so the bar
              // behind it is already right by the time it is popped.
              onChanged: (_, __) => _refreshGroup(),
            ),
          ),
        );

        // And again on the way out, in case the last change landed after
        // the callback -- and because somebody else may have edited the
        // group while that screen was open.
        await _refreshGroup();
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
                  _groupName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_participants.length} members · tap for info',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Re-reads the group from the server and rebuilds what depends on it.
  ///
  /// Whole-list, not a patch. Profiles are REPLACED rather than added to,
  /// which is what finally drops a removed member out of the avatar stack
  /// — the old code only ever called addAll, so leaving a group was
  /// invisible here.
  Future<void> _refreshGroup() async {
    if (!widget.isGroup || widget.conversationId == null) return;

    try {
      final conv = await ChatRepository().getConversation(
        widget.conversationId!,
      );

      final profiles = await UserProfileCache.instance.resolve(
        conv.participantIds.where((id) => id != widget.myUserId).toList(),
      );

      if (!mounted) return;

      setState(() {
        _participants = conv.participantIds;
        _groupName = conv.groupName ?? _groupName;
        _groupProfiles = profiles;
      });
    } catch (e) {
      debugPrint('[Chat] could not refresh group: $e');
    }
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

  /// One message, drawn as part of a run rather than on its own.
  ///
  /// [startsRun] is the first message of a block from one sender and gets
  /// the name, in a group. [endsRun] is the last and gets the avatar and
  /// the squared-off corner. The ones between get neither, which is what
  /// makes a block read as one turn in a conversation rather than six
  /// separate announcements.
  ///
  /// No timestamp anywhere: the day separator carries the time, the way
  /// Instagram does it.
  Widget _buildBubble(
    ChatMessage msg,
    ThemeProvider theme, {
    required bool startsRun,
    required bool endsRun,
  }) {
    final isMe = msg.senderId == widget.myUserId;
    final showAvatar = widget.isGroup && !isMe;

    const round = Radius.circular(20);
    const tail = Radius.circular(5);

    return Padding(
      padding: EdgeInsets.only(top: startsRun ? 10 : 2),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar) ...[
            // The slot is held whether or not the avatar is drawn, so the
            // bubbles in a block line up instead of stepping sideways.
            SizedBox(
              width: 26,
              height: 26,
              child: endsRun
                  ? _buildSenderAvatar(msg.senderId)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: ConstrainedBox(
              // A share of the width rather than a fixed inset, so a
              // bubble is the same proportion of the screen on any phone.
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (widget.isGroup && !isMe && startsRun)
                    Padding(
                      padding: const EdgeInsets.only(left: 14, bottom: 4),
                      child: Text(
                        _groupProfiles[msg.senderId]?.bestName ??
                            'User ${msg.senderId}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                    decoration: BoxDecoration(
                      color: isMe
                          ? theme.primaryColor
                          : const Color(0xFFEFEFEF),
                      borderRadius: BorderRadius.only(
                        topLeft: round,
                        topRight: round,
                        // Only the corner nearest the sender squares off,
                        // and only on the last of a block.
                        bottomLeft: !isMe && endsRun ? tail : round,
                        bottomRight: isMe && endsRun ? tail : round,
                      ),
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: isMe ? Colors.white : const Color(0xFF111111),
                      ),
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
      radius: 13,
      backgroundColor: const Color(0xFFEFEFEF),
      backgroundImage: imageUrl != null && imageUrl.isNotEmpty
          ? NetworkImage(imageUrl)
          : null,
      child: imageUrl == null || imageUrl.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // Still connecting. The cached messages are shown meanwhile, and the
    // composer is there but not yet usable — one screen either way, rather
    // than a second copy of it that quietly differs.
    final connecting = _notifier == null;

    final messages = connecting ? _cachedMessages : _notifier!.messages;
    final loading = connecting ? _cachedMessages.isEmpty : _notifier!.loading;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(theme) as PreferredSizeWidget,
      body: Column(
        children: [
          if (!connecting && _notifier!.error != null) _errorBanner(theme),

          Expanded(child: _messageList(theme, messages, loading)),

          if (!connecting && _notifier!.refreshing) _refreshingStrip(theme),

          _composer(theme, enabled: !connecting),
        ],
      ),
    );
  }

  Widget _errorBanner(ThemeProvider theme) {
    return MaterialBanner(
      content: Text(_notifier!.error!),
      actions: [
        TextButton(
          // Was `() => ()`, which is a function returning an empty record:
          // valid Dart, does nothing, so the banner could not be dismissed.
          onPressed: () => setState(() => _notifier!.clearError()),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _refreshingStrip(ThemeProvider theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5),
      color: theme.primaryColor.withValues(alpha: 0.06),
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
            'Loading new messages…',
            style: TextStyle(fontSize: 11, color: theme.primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _messageList(
    ThemeProvider theme,
    List<ChatMessage> messages,
    bool loading,
  ) {
    if (loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.waving_hand_outlined,
                size: 40,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 12),
              Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Say hello.',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      // Newest first: index 0 is the bottom of the screen, so "the message
      // above this one" is i + 1 and "below" is i - 1. Everything about
      // runs and day separators below reads in those terms.
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final msg = messages[i];

        final at = runPositionAt<ChatMessage>(
          messages,
          i,
          senderOf: (m) => m.senderId,
          timeOf: (m) => m.createdAt,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // First child is the top of the item, and the list is
            // reversed, so this lands above the message it labels.
            if (at.startsDay) _daySeparator(msg.createdAt),
            _buildBubble(
              msg,
              theme,
              startsRun: at.startsRun,
              endsRun: at.endsRun,
            ),
          ],
        );
      },
    );
  }

  /// The date, and the time of the first message under it.
  ///
  /// This is the only clock in the thread. Instagram puts it here and
  /// nowhere else, and it is right: a timestamp on every message turns a
  /// conversation into a log, and the one thing anybody actually wants to
  /// know is roughly when a run of messages happened.
  Widget _daySeparator(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final String day;
    if (days == 0) {
      day = 'Today';
    } else if (days == 1) {
      day = 'Yesterday';
    } else if (days < 7) {
      const names = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      day = names[dt.weekday - 1];
    } else if (dt.year == now.year) {
      day = '${dt.day} ${months[dt.month - 1]}';
    } else {
      day = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Center(
        child: Text(
          '$day  ${_formatTime(dt)}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  /// The one input bar.
  ///
  /// [enabled] is false while the socket is still connecting — the field
  /// greys out, rather than the whole composer being a different widget
  /// that happens to look similar. It used to be exactly that, and the two
  /// had drifted: the loading one had no send button at all, so the bar
  /// changed shape the moment the connection landed.
  Widget _composer(ThemeProvider theme, {required bool enabled}) {
    final sending = _notifier?.sending ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEFEFEF))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 14.5, height: 1.35),
                  // Rebuilds on every keystroke so the send button can
                  // appear the moment there is something to send.
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: enabled ? 'Message…' : 'Connecting…',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    // A bordered pill rather than a filled box: against a
                    // white thread the fill read as another bubble.
                    filled: false,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: Color(0xFFDBDBDB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: theme.primaryColor),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: Color(0xFFEFEFEF)),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                  ),
                  onSubmitted: (_) => enabled ? _send() : null,
                ),
              ),

              // Only once there is something to send. An always-on send
              // button on an empty field is a button that does nothing.
              if (sending)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 4, 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (enabled && _inputController.text.trim().isNotEmpty)
                TextButton(
                  onPressed: _send,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: theme.primaryColor,
                  ),
                  child: const Text(
                    'Send',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
