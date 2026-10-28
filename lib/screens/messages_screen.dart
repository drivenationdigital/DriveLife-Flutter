import 'package:drivelife/api/notifications_api.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Messages and notifications, in one place behind two tabs.
///
/// They were two destinations reached two different ways — the inbox was
/// a tab in the home header, notifications were a bell beside it — which
/// meant two things to check and no way to see at a glance whether either
/// wanted you. One screen, one way in, two counts on the tabs.
///
/// A pushed route rather than a home section. It is somewhere you go and
/// come back from, like a profile, not one of the places the app lives;
/// and as a section it would have carried the home chrome, which is the
/// logo and the tab row this screen replaces with its own.
class MessagesScreen extends StatefulWidget {
  /// Which tab opens first. A notification tap arrives here wanting the
  /// notifications tab, not the inbox.
  final int initialTab;

  const MessagesScreen({super.key, this.initialTab = 0});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 1),
  );

  /// How many unread notifications there are.
  ///
  /// Held here rather than read from a provider because nothing owns it:
  /// the count lives in NotificationsAPI and the header fetches it each
  /// time it is built. This screen takes the number it was given and
  /// stops showing it once the tab has been opened — see [_tabBar].
  int _notificationCount = 0;
  bool _notificationsSeen = false;

  /// Held so the compose button can reach into the inbox and put the
  /// cursor in its search field. The picker lives there, behind that
  /// field; a second one here would be a second way in that drifts.
  ///
  /// Remade whenever the signed-in account changes, which is the job the
  /// ValueKey('inbox-<id>') here used to do. InboxScreen has no
  /// didUpdateWidget and never reacts to myUserId changing, so it needs
  /// a new key to get a new State — reusing one across a switch leaves
  /// the previous account's conversations on screen.
  GlobalKey<InboxScreenState>? _inbox;
  String? _inboxFor;

  GlobalKey<InboxScreenState> _inboxKey(String userId) {
    if (_inboxFor != userId) {
      _inboxFor = userId;
      _inbox = GlobalKey<InboxScreenState>();
    }
    return _inbox!;
  }

  @override
  void initState() {
    super.initState();

    _loadNotificationCount();

    _tabs.addListener(() {
      // Opening the notifications tab marks the badge spent. The screen
      // itself marks them read on the server; this is only so the number
      // beside the word does not sit there contradicting the empty list
      // underneath it.
      if (_tabs.index == 1 && !_notificationsSeen) {
        setState(() => _notificationsSeen = true);
      }
    });
  }

  Future<void> _loadNotificationCount() async {
    try {
      final count = await NotificationsAPI.getNotificationCount();
      if (!mounted) return;
      setState(() => _notificationCount = count);
    } catch (_) {
      // A missing badge is better than an error over a list that works.
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final user = context.watch<AccountManager>().activeUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 64,
        leading: Center(
          child: _circleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Color(0xFF111111),
          ),
        ),
        actions: [
          _circleButton(
            icon: Icons.edit_outlined,
            // The inbox owns starting a conversation; this hands the
            // gesture to it rather than keeping a second copy of the
            // people-picker here. Switch to that tab first — the key
            // points at a widget that is not built while Notifications
            // is showing.
            onTap: () {
              _tabs.animateTo(0);
              _inbox?.currentState?.startNewConversation();
            },
            tooltip: 'New message',
          ),
          const SizedBox(width: 16),
        ],
        bottom: _tabBar(theme),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          if (user == null)
            const _SignedOut()
          else
            InboxScreen(
              key: _inboxKey(user.id.toString()),
              myUserId: user.id.toString(),
            ),

          // Embedded: the same list, without the Scaffold and app bar it
          // uses when it is a screen of its own.
          //
          // Keyed by account for the same reason the inbox is: this page
          // is kept alive across tab switches, so without a new key the
          // previous account's State — and its list — stays on screen
          // after a switch.
          NotificationsScreen(
            key: ValueKey('notifications-${user?.id ?? 'none'}'),
            embedded: true,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _tabBar(ThemeProvider theme) {
    final unreadMessages = context.watch<UnreadCountProvider>().count;
    final unreadNotifications = _notificationsSeen ? 0 : _notificationCount;

    return PreferredSize(
      preferredSize: const Size.fromHeight(49),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: _tabs,
            labelColor: const Color(0xFF111111),
            unselectedLabelColor: const Color(0xFF9A9A9A),
            indicatorColor: const Color(0xFF111111),
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
            tabs: [
              _tab('Inbox', unreadMessages, theme.primaryColor),
              _tab(
                'Notifications',
                unreadNotifications,
                const Color(0xFF9A9A9A),
              ),
            ],
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEDEDED)),
        ],
      ),
    );
  }

  /// A tab's label, with its count beside it when there is one.
  ///
  /// Gold on the inbox, grey on notifications: an unread message is
  /// somebody waiting on a reply, and a notification is not.
  Widget _tab(String label, int count, Color badge) {
    return Tab(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 7),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badge,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF4F4F4),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 17, color: const Color(0xFF111111)),
          ),
        ),
      ),
    );
  }
}

/// Nobody is signed in, so there is no inbox to show.
class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in to see your messages',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
