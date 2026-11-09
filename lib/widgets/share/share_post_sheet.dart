import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// One person the post can be sent to.
///
/// Comes from two places that have nothing in common — the inbox, which
/// is Supabase, and the user search, which is WordPress — so this is the
/// shape they are both flattened into before the list draws anything.
class _Recipient {
  final String userId;
  final String name;
  final String? avatar;

  /// An existing conversation, when there is one. Null means the first
  /// message will create it.
  final String? conversationId;

  /// Groups can be sent to as well, and they have no single other user.
  final bool isGroup;

  const _Recipient({
    required this.userId,
    required this.name,
    this.avatar,
    this.conversationId,
    this.isGroup = false,
  });

  /// Identity for selection. A group has no user id, so the conversation
  /// is what makes it distinct.
  String get key => isGroup ? 'c:$conversationId' : 'u:$userId';
}

/// "Send to…" for a post — the DriveLife equivalent of Instagram's share
/// sheet.
///
/// Recent chats first, because sharing is overwhelmingly to somebody you
/// already talk to, then a search for everyone else, then the operating
/// system's own share sheet at the bottom for anything outside the app.
///
/// ── THE OS SHARE IS KEPT, NOT REPLACED ───────────────────────────────
///
/// It used to be the whole of this button. Removing it in favour of
/// in-app sending would take away the only way to put a post in
/// WhatsApp, which is where a lot of this actually goes.
class SharePostSheet extends StatefulWidget {
  /// The URL being shared. Built by the caller, because a post and an
  /// event have different ones.
  final String url;

  /// What the OS share sheet sends. Includes the URL.
  final String shareText;

  /// For the OS sheet's subject line.
  final String? subject;

  /// Called once, after at least one message has gone, so the caller can
  /// record the share.
  final VoidCallback? onSent;

  const SharePostSheet({
    super.key,
    required this.url,
    required this.shareText,
    this.subject,
    this.onSent,
  });

  /// Opens the sheet. Returns when it closes.
  static Future<void> show(
    BuildContext context, {
    required String url,
    required String shareText,
    String? subject,
    VoidCallback? onSent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SharePostSheet(
        url: url,
        shareText: shareText,
        subject: subject,
        onSent: onSent,
      ),
    );
  }

  @override
  State<SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<SharePostSheet> {
  final ChatRepository _chat = ChatRepository();
  final InboxRepository _inbox = InboxRepository();

  final TextEditingController _search = TextEditingController();
  final TextEditingController _note = TextEditingController();

  Timer? _debounce;

  String? _myUserId;

  List<_Recipient> _recents = const [];
  List<_Recipient> _results = const [];

  /// Keyed by [_Recipient.key], so a person found in both the recents and
  /// the search is one selection rather than two.
  final Map<String, _Recipient> _selected = {};

  /// Who has already been sent to in this sheet. Instagram keeps the
  /// sheet open and marks them "Sent", which is the behaviour that makes
  /// sending to three people in a row bearable.
  final Set<String> _sent = {};

  bool _loading = true;
  bool _searching = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final myId = await SupabaseTokenManager.currentUserId;

      if (myId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final inbox = await _inbox.getInbox(myId);

      // The ids to put names and faces to. Groups are skipped — they
      // carry their own name and image on the conversation.
      final userIds = inbox
          .where((p) => !p.isGroup && (p.otherUserId ?? '').isNotEmpty)
          .map((p) => p.otherUserId!)
          .toSet()
          .toList();

      final profiles = await UserProfileCache.instance.resolve(userIds);

      if (!mounted) return;

      setState(() {
        _myUserId = myId;
        _recents = inbox.map((p) => _fromPreview(p, profiles)).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Share] recents failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  _Recipient _fromPreview(
    ConversationPreview preview,
    Map<String, UserProfile> profiles,
  ) {
    if (preview.isGroup) {
      return _Recipient(
        userId: '',
        name: preview.conversation.groupName?.trim().isNotEmpty == true
            ? preview.conversation.groupName!
            : 'Group',
        avatar: preview.conversation.groupImage,
        conversationId: preview.conversation.id,
        isGroup: true,
      );
    }

    final id = preview.otherUserId ?? '';
    final profile = profiles[id];

    return _Recipient(
      userId: id,
      // bestName, which is the full name when there is one and the
      // display name otherwise — the same rule the inbox itself uses.
      name: profile?.bestName.trim().isNotEmpty == true
          ? profile!.bestName
          : 'Someone',
      avatar: profile?.imageUrl,
      conversationId: preview.conversation.id,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(value.trim()),
    );
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }

    if (mounted) setState(() => _searching = true);

    try {
      // The same search the group-member picker uses, so one directory
      // rather than two that can disagree about who exists.
      final rows = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: 'users',
        taggedEntities: const [],
      );

      if (!mounted) return;

      // Anybody already in the recents is dropped: they are two rows up
      // the same sheet, and selecting one of the two would look like the
      // other had not registered.
      final recentIds = _recents.map((r) => r.userId).toSet();

      setState(() {
        _results = rows
            .map((row) {
              final id = '${row['entity_id'] ?? ''}';

              return _Recipient(
                userId: id,
                name: '${row['name'] ?? row['display_name'] ?? 'Someone'}',
                avatar: row['image']?.toString(),
              );
            })
            .where((r) => r.userId.isNotEmpty && !recentIds.contains(r.userId))
            .where((r) => r.userId != _myUserId)
            .toList();
        _searching = false;
      });
    } catch (e) {
      debugPrint('[Share] search failed: $e');
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggle(_Recipient person) {
    // Already sent to in this sheet — tapping again would be a second
    // identical message, which is never what the tap meant.
    if (_sent.contains(person.key)) return;

    setState(() {
      if (_selected.containsKey(person.key)) {
        _selected.remove(person.key);
      } else {
        _selected[person.key] = person;
      }
    });
  }

  /// Tell the caller a share happened, without letting it break this.
  ///
  /// onSent is somebody else's code running in the middle of our send
  /// flow, and it is bookkeeping -- the least important thing happening
  /// at that moment. Its first version threw a TypeError on every call
  /// (see the note in post_card's _sharePost) and took the app down
  /// with it, AFTER the messages had already been delivered.
  ///
  /// So it is isolated: a share that was sent is sent, whatever the
  /// recording afterwards does.
  void _reportSent() {
    try {
      widget.onSent?.call();
    } catch (e) {
      debugPrint('[Share] onSent threw: $e');
    }
  }

  Future<void> _send() async {
    final myId = _myUserId;

    if (myId == null || _selected.isEmpty || _sending) return;

    setState(() => _sending = true);

    final note = _note.text.trim();

    // The link LAST. The card in the bubble is built by finding the URL
    // and showing what is left as the note, so the order only matters
    // for a client too old to render the card — and there a trailing
    // link reads better than a leading one.
    final content = note.isEmpty ? widget.url : '$note\n${widget.url}';

    final people = List<_Recipient>.from(_selected.values);
    var failures = 0;

    for (final person in people) {
      try {
        var conversationId = person.conversationId;

        // No conversation yet: this message starts one. Groups always
        // have one, so this only ever runs for a person.
        conversationId ??= (await _chat.getOrCreateConversation(
          myUserId: myId,
          otherUserId: person.userId,
        )).id;

        await _chat.sendMessage(
          conversationId: conversationId,
          senderId: myId,
          content: content,
        );

        _sent.add(person.key);
      } catch (e) {
        // One failure does not abandon the rest. Somebody sharing to
        // four people should not lose three of them because one
        // conversation could not be created.
        debugPrint('[Share] send to ${person.key} failed: $e');
        failures++;
      }
    }

    if (!mounted) return;

    setState(() {
      _selected.clear();
      _sending = false;
    });

    if (_sent.isNotEmpty) _reportSent();

    final sentCount = people.length - failures;

    if (sentCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures == 0
                ? (sentCount == 1 ? 'Sent' : 'Sent to $sentCount people')
                : 'Sent to $sentCount, $failures could not be reached',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send. Try again.')),
      );
    }

    // Closed only when everything went. A sheet that closes on a partial
    // failure takes away the list showing which ones worked.
    if (failures == 0 && mounted) Navigator.pop(context);
  }

  Future<void> _shareElsewhere() async {
    // Popped first. On iOS the OS sheet anchors to the top view
    // controller, and presenting it from under a modal has it appear
    // behind the sheet that opened it.
    Navigator.pop(context);

    try {
      await SharePlus.instance.share(
        ShareParams(text: widget.shareText, subject: widget.subject),
      );
      _reportSent();
    } catch (e) {
      debugPrint('[Share] os sheet failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // Lifted by the keyboard, so the note field and the send button
      // are not behind it while somebody is typing into them.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.subtextColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Send to',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.textColor,
                  ),
                ),
                const SizedBox(height: 12),

                _searchField(theme),

                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: theme.primaryColor,
                          ),
                        )
                      : _list(theme, scrollController),
                ),

                _footer(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _searchField(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _search,
        onChanged: _onSearchChanged,
        style: TextStyle(color: theme.textColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search for someone',
          hintStyle: TextStyle(color: theme.subtextColor, fontSize: 15),
          prefixIcon: Icon(Icons.search, color: theme.subtextColor, size: 20),
          suffixIcon: _searching
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primaryColor,
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: theme.subtextColor.withValues(alpha: 0.08),
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _list(ThemeProvider theme, ScrollController controller) {
    final searching = _search.text.trim().isNotEmpty;
    final people = searching ? _results : _recents;

    if (people.isEmpty) {
      return ListView(
        controller: controller,
        children: [
          const SizedBox(height: 50),
          Center(
            child: Text(
              searching
                  ? 'Nobody found'
                  : 'No chats yet — search for someone above',
              style: TextStyle(color: theme.subtextColor, fontSize: 14.5),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      itemCount: people.length,
      itemBuilder: (context, index) => _row(theme, people[index]),
    );
  }

  Widget _row(ThemeProvider theme, _Recipient person) {
    final chosen = _selected.containsKey(person.key);
    final done = _sent.contains(person.key);

    return ListTile(
      onTap: () => _toggle(person),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: theme.subtextColor.withValues(alpha: 0.15),
        backgroundImage:
            (person.avatar != null && person.avatar!.isNotEmpty)
            ? CachedNetworkImageProvider(person.avatar!)
            : null,
        // Conditional, like every other avatar in the app: CircleAvatar
        // asserts that backgroundImage is non-null whenever an error
        // handler is given.
        onBackgroundImageError:
            (person.avatar != null && person.avatar!.isNotEmpty)
            ? (_, _) {}
            : null,
        child: (person.avatar == null || person.avatar!.isEmpty)
            ? Icon(
                person.isGroup ? Icons.group : Icons.person,
                color: theme.subtextColor,
                size: 22,
              )
            : null,
      ),
      title: Text(
        person.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: theme.textColor,
        ),
      ),
      trailing: done
          ? Text(
              'Sent',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.subtextColor,
              ),
            )
          : Icon(
              chosen ? Icons.check_circle : Icons.circle_outlined,
              color: chosen ? theme.primaryColor : theme.subtextColor,
            ),
    );
  }

  Widget _footer(ThemeProvider theme) {
    final chosen = _selected.length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only once somebody is selected. An empty note field above
            // an empty list is a form asking to be filled in before it
            // can do anything.
            if (chosen > 0) ...[
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: theme.textColor, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Add a message…',
                  hintStyle: TextStyle(
                    color: theme.subtextColor,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: theme.subtextColor.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          chosen == 1 ? 'Send' : 'Send to $chosen',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Always there, selection or not. This is the escape hatch to
            // WhatsApp, Messages and everything else, and it was the
            // whole of this button before the sheet existed.
            InkWell(
              onTap: _shareElsewhere,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.ios_share, size: 19, color: theme.textColor),
                    const SizedBox(width: 9),
                    Text(
                      'Share to other apps',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.textColor,
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
