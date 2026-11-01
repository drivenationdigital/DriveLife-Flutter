import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/global_groups_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A global group, viewed.
///
/// GLOBAL GROUPS ONLY — scene, marque and model. Clubs keep their
/// existing screen. The intention is that clubs move onto this UI
/// later, which is why nothing here is named after a scene or a
/// marque and why the tabs are driven by counts rather than by kind:
/// pointing it at a club should eventually be a matter of giving it a
/// different data source, not a rewrite.
///
/// READ ONLY, deliberately.
///
/// The designs show a Joined pill and a composer, and both are drawn
/// here — but neither writes. Membership and posting are a later step,
/// and while this is being tested against production data a screen
/// that cannot write cannot surprise anybody. Each is wired to a
/// single "not yet" snackbar rather than being hidden, so the layout
/// is the real one and turning them on later is replacing a callback.
///
/// WHAT IS REAL
///
///   Latest    activity index — empty until the refresh has run
///   Garages   ce_group_vehicles — same
///   Spots     activity index, item_type 'spot' — same
///   Events    NOTHING. No column, no table, no rule relates an event
///             to a global group. The tab is here because the design
///             has it and because the shape should exist before the
///             relationship is designed; it says so on screen rather
///             than showing a bare empty state.
///
/// "Car of the week" from the design is not built: nothing picks one.
/// Left out rather than faked with the top-liked car, which would be a
/// different claim wearing the same badge.
class GlobalGroupScreen extends StatefulWidget {
  const GlobalGroupScreen({super.key, required this.slug, this.initial});

  final String slug;

  /// What the list already knew, so the header renders immediately
  /// instead of flashing a spinner over data we have in hand.
  final GlobalGroup? initial;

  @override
  State<GlobalGroupScreen> createState() => _GlobalGroupScreenState();
}

class _GlobalGroupScreenState extends State<GlobalGroupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  GlobalGroup? _group;
  List<GlobalGroupPost> _latest = const [];
  List<GlobalGroupVehicle> _garages = const [];
  List<GlobalGroupSpot> _spots = const [];
  List<GlobalGroupEvent> _events = const [];

  bool _loading = true;
  bool _failed = false;

  /// A join or leave in flight, so a second tap cannot start a second
  /// request.
  bool _joining = false;

  /// The membership state while the server catches up, or null to use
  /// whatever the group last said. Cleared by the reload that follows
  /// a successful join.
  bool? _joinedOverride;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _group = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Everything at once.
  ///
  /// Four small requests in parallel rather than one per tab on first
  /// view: the counts are in the header from the start, so a tab that
  /// says 212 and then takes a second to fill would be the worse
  /// experience. Revisit if any of these grows expensive.
  Future<void> _load() async {
    final results = await Future.wait([
      GlobalGroupsApi.fetchGroup(widget.slug),
      GlobalGroupsApi.fetchActivity(widget.slug),
      GlobalGroupsApi.fetchVehicles(widget.slug),
      GlobalGroupsApi.fetchSpots(widget.slug),
      GlobalGroupsApi.fetchEvents(widget.slug),
    ]);

    if (!mounted) return;

    final group = results[0] as GlobalGroup?;

    setState(() {
      _group = group ?? _group;
      _latest = results[1] as List<GlobalGroupPost>;
      _garages = results[2] as List<GlobalGroupVehicle>;
      _spots = results[3] as List<GlobalGroupSpot>;
      _events = results[4] as List<GlobalGroupEvent>;
      _loading = false;
      _failed = group == null && _group == null;

      // Fresh truth from the server supersedes the optimistic flip.
      // Left in place, a stale override would keep claiming "Joined"
      // through any later reload.
      if (group != null) _joinedOverride = null;
    });
  }

  void _notYet(String what) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what is not built yet.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final group = _group;

    if (_failed) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: AppBar(backgroundColor: theme.backgroundColor),
        body: const Center(child: Text('That group could not be loaded.')),
      );
    }

    if (group == null) {
      // The page's own shape, not a spinner in the middle of nothing:
      // the header, the tab bar and a feed are all coming, and laying
      // them out now means nothing jumps when they land.
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                child: Row(
                  children: [
                    _circleBack(theme),
                    const SizedBox(width: 10),
                    const GroupShimmer(
                      child: Row(
                        children: [
                          GroupBlock(width: 36, height: 36, radius: 8),
                          SizedBox(width: 10),
                          GroupBlock(width: 150, height: 18),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const GroupShimmer(
                      child: GroupBlock(width: 86, height: 42, radius: 21),
                    ),
                  ],
                ),
              ),
              const GroupShimmer(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      GroupBlock(width: 60, height: 16),
                      SizedBox(width: 22),
                      GroupBlock(width: 78, height: 16),
                      SizedBox(width: 22),
                      GroupBlock(width: 62, height: 16),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              const Expanded(
                child: SingleChildScrollView(
                  physics: NeverScrollableScrollPhysics(),
                  child: GroupFeedSkeleton(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(theme, group),
            _tabBar(theme, group),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _latestTab(theme, group),
                  _garagesTab(theme),
                  _spotsTab(theme),
                  _eventsTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────

  Widget _header(ThemeProvider theme, GlobalGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      child: Row(
        children: [
          _circleBack(theme),
          const SizedBox(width: 10),

          _headerLogo(theme, group),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // 17, matching the club header. 21 competed with
                    // the tab labels directly beneath it, and left
                    // nothing for a long marque name beside the logo
                    // and the Join pill.
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.textColor,
                  ),
                ),

                // Every group is a draft while this is being tested and
                // the endpoint is deliberately serving them. Without
                // this a test build looks exactly like a live one.
                if (group.status != 'published')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      group.status.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: Color(0xFFAE9159),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 10),
          _joinPill(theme, group),
        ],
      ),
    );
  }

  /// The group's mark, between the back button and the name.
  ///
  /// Prefers the logo over the cover: a logo is made to be small and
  /// square, while a cover photo cropped to 36px is usually an
  /// unreadable scrap of bodywork. Falls back to the cover only
  /// because a scrap is still better than a grey square, and to an
  /// icon when there is neither.
  ///
  /// Takes no space at all when the group has no images, rather than
  /// leaving a placeholder gap — most groups have none yet.
  Widget _headerLogo(ThemeProvider theme, GlobalGroup group) {
    final url = (group.logo ?? '').isNotEmpty
        ? group.logo
        : (group.coverImage ?? '');

    if ((url ?? '').isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(
              color: theme.cardColor,
              child: Icon(
                Icons.groups_outlined,
                size: 19,
                color: theme.subtextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleBack(ThemeProvider theme) {
    return Material(
      color: theme.cardColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.maybePop(context),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_ios_new,
            size: 17,
            color: theme.textColor,
          ),
        ),
      ),
    );
  }

  /// Join or leave. The one thing on this screen that writes.
  ///
  /// Optimistic, and it puts itself back if the server disagreed —
  /// showing "Joined" for a membership that does not exist would send
  /// somebody away believing they are in a group they are not.
  Widget _joinPill(ThemeProvider theme, GlobalGroup group) {
    final joined = _joinedOverride ?? group.isMember;

    return OutlinedButton(
      onPressed: _joining ? null : () => _toggleJoin(group, joined),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: theme.dividerColor),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        foregroundColor: theme.textColor,
        backgroundColor: joined ? null : theme.textColor,
        disabledForegroundColor: theme.subtextColor,
      ),
      child: _joining
          ? SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: joined ? theme.textColor : theme.textColorSecondary,
              ),
            )
          : Text(
              joined ? 'Joined' : 'Join',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: joined ? theme.textColor : theme.textColorSecondary,
              ),
            ),
    );
  }

  Future<void> _toggleJoin(GlobalGroup group, bool joined) async {
    // Ask before leaving, never before joining — leaving loses a
    // membership and stops the group being suggested again, while
    // joining is undone by the same button.
    if (joined && !await _confirmLeave(group)) return;

    setState(() {
      // No optimistic flip: the pill shows a spinner and changes only
      // when the server has agreed. Flipping first made a slow request
      // look finished, and a failed one look successful.
      _joining = true;
    });

    final ok = joined
        ? await GlobalGroupsApi.leave(group.slug)
        : await GlobalGroupsApi.join(group.slug);

    if (!mounted) return;

    if (!ok) {
      // Nothing to roll back: the pill never claimed the new state.
      setState(() => _joining = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            joined
                ? 'Could not leave ${group.title}.'
                : 'Could not join ${group.title}.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _joining = false;
      _joinedOverride = !joined;
    });

    // Reload: joining puts this person's matching cars into the
    // group's garage, so the Garages tab and its count are both stale
    // the moment the server says yes.
    await _load();
  }

  /// "Leave this group?"
  ///
  /// Names the two consequences that are not obvious from the button:
  /// the member's cars come out of the group's garage, and the group
  /// stops being suggested to them afterwards.
  Future<bool> _confirmLeave(GlobalGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${group.title}?'),
        content: const Text(
          'Your vehicles will be removed from this group, and it will '
          'stop being suggested to you. You can join again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  // ─── Tabs ──────────────────────────────────────────────────────────

  Widget _tabBar(ThemeProvider theme, GlobalGroup group) {
    return GroupTabBar(
      controller: _tabs,
      theme: theme,
      tabs: [
        // No count on Latest: a number there would be a post count
        // nobody asked for.
        const GroupTab('Latest'),
        GroupTab('Garages', group.garageCount),
        GroupTab('Spots', group.spotCount),
        GroupTab('Events', group.eventCount),
      ],
    );
  }

  // ─── Latest ────────────────────────────────────────────────────────

  Widget _latestTab(ThemeProvider theme, GlobalGroup group) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _composer(theme, group),

          if (_garages.isNotEmpty) _latestGarages(theme),

          if (_loading && _latest.isEmpty)
            const GroupFeedSkeleton()
          else if (_latest.isEmpty)
            GroupEmptyNote(
              theme: theme,
              title: 'No activity yet',
              body:
                  'Posts and spots are gathered by a background pass, which '
                  'has not run for this group. That is not the same as '
                  'nothing matching it.',
            )
          else
            for (final post in _latest) _postCard(theme, post),
        ],
      ),
    );
  }

  /// The composer row. Inert, like the Joined pill.
  Widget _composer(ThemeProvider theme, GlobalGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            // The signed-in user's own photo, like the club composer —
            // it is their post being invited, so it should be their
            // face. listen: false because the avatar does not change
            // while this row is on screen, and rebuilding the whole
            // feed when the provider ticks would be wasteful.
            GroupAvatar(
              url: Provider.of<UserProvider>(
                context,
                listen: false,
              ).user?.profileImage,
              radius: 19,
              theme: theme,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Post to ${group.title}...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.5, color: theme.subtextColor),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _notYet('Posting to a group'),
              icon: const Icon(Icons.add, size: 19),
              label: const Text('Post'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.textColor,
                foregroundColor: theme.textColorSecondary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _latestGarages(ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Expanded(child: _sectionTitle(theme, 'Latest garages')),
              GestureDetector(
                onTap: () => _tabs.animateTo(1),
                child: const Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAE9159),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _garages.length > 10 ? 10 : _garages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: 196,
              child: GroupGarageCard(
                vehicle: _garages[i],
                theme: theme,
                compact: true,
                onTap: () => _openVehicle(_garages[i].id),
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  Widget _postCard(ThemeProvider theme, GlobalGroupPost post) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Only 6 at the bottom: the author row sits close to the
          // photograph it belongs to, and 12 read as a gap between two
          // unrelated things rather than a header on a card.
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              GroupAvatar(url: post.user?.avatar, radius: 21, theme: theme),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.user?.shortName ?? 'Someone',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.textColor,
                      ),
                    ),
                    Text(
                      _ago(post.happenedAt),
                      style: TextStyle(fontSize: 14, color: theme.subtextColor),
                    ),
                  ],
                ),
              ),

              // Why this is in the group. 'member' means somebody
              // posted it here; anything else means we matched it in,
              // and claiming otherwise would be a small lie that adds
              // up across a feed.
              //
              // Always "Matched", never "Spotted": the caption's first
              // line already says a post is a spot, and the same word
              // twice on one card reads as a bug.
              if (post.source != 'member')
                Text(
                  'Matched',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: theme.subtextColor,
                  ),
                ),
            ],
          ),
        ),

        if ((post.image ?? '').isNotEmpty)
          GestureDetector(
            onTap: () => _openPost(post.postId),
            child: AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: post.image!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(color: theme.cardColor),
              ),
            ),
          ),

        if ((post.spottedVehicle ?? '').trim().isNotEmpty ||
            post.caption.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The same first line the main feed shows, from the
                // same field — see _PostCaptionSection in
                // components/post_card.dart. Written out rather than
                // shared because that widget is private to the feed
                // card and takes a Map; if a third caller appears it
                // is worth lifting out.
                if ((post.spottedVehicle ?? '').trim().isNotEmpty)
                  Text(
                    '📸 Spotted: ${post.spottedVehicle!.trim()}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.textColor,
                    ),
                  ),

                if (post.caption.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: (post.spottedVehicle ?? '').trim().isEmpty ? 0 : 4,
                    ),
                    child: Text(
                      post.caption,
                      style: TextStyle(fontSize: 15, color: theme.textColor),
                    ),
                  ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              Icon(
                post.isLiked ? Icons.favorite : Icons.favorite_border,
                size: 23,
                color: post.isLiked ? Colors.red : theme.textColor,
              ),
              const SizedBox(width: 6),
              Text(
                '${post.likes}',
                style: TextStyle(color: theme.subtextColor),
              ),
              const SizedBox(width: 18),
              Icon(
                Icons.mode_comment_outlined,
                size: 21,
                color: theme.textColor,
              ),
              const SizedBox(width: 6),
              Text(
                '${post.comments}',
                style: TextStyle(color: theme.subtextColor),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  // ─── Garages ───────────────────────────────────────────────────────

  Widget _garagesTab(ThemeProvider theme) {
    if (_loading && _garages.isEmpty) {
      return const SingleChildScrollView(child: GroupGarageGridSkeleton());
    }

    if (_garages.isEmpty) {
      return ListView(
        // Explicit: a ListView with padding: null adopts
        // MediaQuery.padding, drawing the status-bar inset as a blank
        // band under the header.
        padding: EdgeInsets.zero,
        children: [
          GroupEmptyNote(
            theme: theme,
            title: 'No vehicles matched yet',
            body:
                'Vehicles are matched by a background pass, which has not '
                'run for this group. This is not the same as no car '
                'fitting the rules.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _garages.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (_, i) => GroupGarageCard(
          vehicle: _garages[i],
          theme: theme,
          onTap: () => _openVehicle(_garages[i].id),
        ),
      ),
    );
  }

  // ─── Spots ─────────────────────────────────────────────────────────

  Widget _spotsTab(ThemeProvider theme) {
    if (_loading && _spots.isEmpty) {
      return const SingleChildScrollView(child: GroupSpotGridSkeleton());
    }

    if (_spots.isEmpty) {
      return ListView(
        // Explicit: a ListView with padding: null adopts
        // MediaQuery.padding, drawing the status-bar inset as a blank
        // band under the header.
        padding: EdgeInsets.zero,
        children: [
          GroupEmptyNote(
            theme: theme,
            title: 'No spots yet',
            body:
                'Spots are matched to a group by name, and that matching '
                'runs in the background pass. It has not run for this '
                'group.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        itemCount: _spots.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemBuilder: (_, i) => GroupSpotTile(
          spot: _spots[i],
          theme: theme,
          onTap: () => _openPost(_spots[i].postId),
        ),
      ),
    );
  }

  // ─── Events ────────────────────────────────────────────────────────

  Widget _eventsTab(ThemeProvider theme) {
    if (_events.isEmpty) {
      return ListView(
        // Explicit: a ListView with padding: null adopts
        // MediaQuery.padding, drawing the status-bar inset as a blank
        // band under the header.
        padding: EdgeInsets.zero,
        children: [
          GroupEmptyNote(
            theme: theme,
            title: 'Events are not connected yet',
            body:
                'Nothing relates an event to a global group — no field, no '
                'link table, no rule. An event belongs to a region and a '
                'site, and a global group belongs to neither, so this is '
                'a design decision rather than a missing query.',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: _events.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.dividerColor, indent: 76),
      itemBuilder: (_, i) => _eventRow(theme, _events[i]),
    );
  }

  Widget _eventRow(ThemeProvider theme, GlobalGroupEvent event) {
    final date = event.startsAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              date == null ? '' : _month(date).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.subtextColor,
              ),
            ),
            Text(
              date == null ? '?' : '${date.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: theme.textColor,
              ),
            ),
          ],
        ),
      ),
      title: Text(
        event.title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: theme.textColor,
        ),
      ),
      subtitle: (event.location ?? '').isEmpty
          ? null
          : Text(
              event.location!,
              style: TextStyle(fontSize: 14, color: theme.subtextColor),
            ),
      trailing: Icon(Icons.chevron_right, color: theme.subtextColor),
      onTap: () => _notYet('Group events'),
    );
  }

  // ─── Shared bits ───────────────────────────────────────────────────

  Widget _sectionTitle(ThemeProvider theme, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: theme.textColor,
      ),
    );
  }

  void _openPost(int postId) {
    if (postId <= 0) return;

    Navigator.pushNamed(
      context,
      AppRoutes.postDetail,
      arguments: {'postId': postId},
    );
  }

  void _openVehicle(int garageId) {
    if (garageId <= 0) return;

    Navigator.pushNamed(
      context,
      AppRoutes.vehicleDetail,
      // A STRING. The route passes garageId straight through to
      // VehicleDetailScreen without coercing it, unlike postDetail
      // which calls toString() — and every existing caller sends a
      // string, so an int here would be a type error at the far end.
      arguments: {'garageId': '$garageId'},
    );
  }

  String _ago(DateTime? when) {
    if (when == null) return '';

    final diff = DateTime.now().difference(when);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
    }

    return '${when.day} ${_month(when)}';
  }

  String _month(DateTime when) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[when.month - 1];
  }
}
