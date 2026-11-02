import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/activity_feed_api.dart';
import 'package:drivelife/models/activity_item.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/global_group_screen.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Activity tab in Messages. Temporary, and administrators only.
///
/// It exists to answer one question with real data: when we match
/// somebody's interests against the activity log, is what comes back
/// worth showing? Everything on screen is pointed at that — the
/// interest chips at the top, the "Because you own a Porsche" line on
/// every card, and the two buttons.
///
/// The chips matter more than they look. Without them a feed full of the
/// wrong cars is ambiguous: the matcher could be broken, or we could
/// simply be wrong about what this person likes. Those need completely
/// different fixes, and the chips are what tell them apart.
///
/// Nothing here is notified, pushed or emailed. Opening the tab is the
/// only thing that makes any of it run, and the only rows written are in
/// the new activity tables.
/// WHO SEES THE ACTIVITY TAB.
///
///   true   administrators only
///   false  anybody signed in
///
/// Currently false, for an internal TestFlight build: the point of that
/// build is other people pressing the buttons.
///
/// To close it again, set this to true AND set DL_ACT_ADMINS_ONLY to
/// true in php-api/endpoints/activity-match.php. BOTH, because they do
/// different jobs — this one hides the tab, that one refuses the
/// request. One without the other leaves either a visible tab that
/// errors, or endpoints anyone signed in can call.
///
/// Note also that the grey number on each card is the raw match score,
/// a testing affordance. Worth removing before this reaches people who
/// are not testing it.
const bool kActivityTabAdminsOnly = false;

class ActivityFeedTab extends StatefulWidget {
  const ActivityFeedTab({super.key});

  @override
  State<ActivityFeedTab> createState() => _ActivityFeedTabState();
}

class _ActivityFeedTabState extends State<ActivityFeedTab> {
  ActivityFeed? _feed;
  bool _loading = true;

  /// Items the viewer has pushed away this session.
  ///
  /// Removed locally the moment they tap, rather than after the server
  /// answers and certainly not by refetching: the server already
  /// excludes anything responded to, so the next load agrees. A card
  /// that lingered while a request flew would make the button feel
  /// broken.
  final Set<int> _dismissed = {};

  /// Items they marked as wanted, so the card can say so.
  final Set<int> _kept = {};

  /// What we suggested off the back of each kept item, by activity id.
  ///
  /// Held here rather than in the card so it survives the card being
  /// rebuilt, and so a scroll away and back does not refetch. A null
  /// VALUE against a present key means the fetch failed — distinct from
  /// a key that is absent because nothing has been asked for yet, and
  /// from a set that came back genuinely empty.
  final Map<int, ActivityRelatedSet?> _related = {};

  /// Fetches in flight.
  final Set<int> _relatedLoading = {};

  /// True while the foot-of-page button is fetching a different set.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final feed = await ActivityFeedApi.fetchFeed(limit: 20);

    if (!mounted) return;

    setState(() {
      _feed = feed;
      _loading = false;
      // A fresh load is a fresh answer; anything still excluded is
      // excluded by the server now.
      _dismissed.clear();
      _kept.clear();
      _related.clear();
      _relatedLoading.clear();
    });
  }

  /// Swap the list for cards this person has not been shown before.
  ///
  /// Distinct from [_load] and from pull-to-refresh, which both return
  /// whatever matches best — usually the same cards, because the feed
  /// is allowed to re-show and would otherwise empty itself.
  ///
  /// An empty answer here is a real one, and the current list is KEPT:
  /// swapping a working feed for "all caught up" because somebody asked
  /// for variety would be a worse outcome than not finding any.
  Future<void> _showAnother() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);

    final feed = await ActivityFeedApi.fetchFeed(limit: 20, fresh: true);

    if (!mounted) return;

    if (feed == null || feed.items.isEmpty) {
      setState(() => _refreshing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing new to show yet — pull down to see the current set '
            'again.',
          ),
          duration: Duration(seconds: 2),
        ),
      );

      return;
    }

    setState(() {
      _feed = feed;
      _refreshing = false;
      _dismissed.clear();
      _kept.clear();
      _related.clear();
      _relatedLoading.clear();
    });
  }

  /// Record a response, and drop the card if that is what it means.
  Future<void> _respond(ActivityItem item, String response) async {
    final removes = response == 'not_interested' || response == 'hidden';

    setState(() {
      if (removes) {
        _dismissed.add(item.id);
      } else {
        _kept.add(item.id);
      }
    });

    final ok = await ActivityFeedApi.respond(
      activityId: item.id,
      response: response,
    );

    if (!mounted) return;

    if (!ok) {
      // Put it back rather than leave the viewer thinking a tap landed
      // when it did not.
      setState(() {
        _dismissed.remove(item.id);
        _kept.remove(item.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that — try again')),
      );

      return;
    }

    if (removes) return;

    // They have just told us they like this car. Ask what else follows
    // from that, and open it under the card.
    _loadRelated(item);
  }

  /// "If you like this, you might like these."
  ///
  /// Fired by Interested, and by the retry link if it failed. Guarded
  /// against a second fetch while one is in flight, and against
  /// refetching a set we already have.
  Future<void> _loadRelated(ActivityItem item) async {
    if (_relatedLoading.contains(item.id)) return;
    if (_related[item.id] != null) return;

    setState(() => _relatedLoading.add(item.id));

    final related = await ActivityFeedApi.fetchRelated(item.id, limit: 5);

    if (!mounted) return;

    setState(() {
      _relatedLoading.remove(item.id);
      _related[item.id] = related;
    });
  }

  /// Open a suggestion. Groups by slug, events and venues by post id.
  void _openRelated(ActivityRelated related) {
    switch (related.type) {
      case 'person':
        if (related.id.isEmpty) return;

        Navigator.pushNamed(
          context,
          AppRoutes.viewProfile,
          // The route copes with either, but a String is what the id
          // arrives as and there is nothing to gain by parsing it.
          arguments: {'userId': related.id},
        );
        break;

      case 'group':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GlobalGroupScreen(slug: related.id),
          ),
        );
        break;

      case 'event':
        if (related.id.isEmpty) return;

        Navigator.pushNamed(
          context,
          AppRoutes.eventDetail,
          // EventDetailScreen takes the whole event map, but reads only
          // id and site off it and refetches the rest — so a stub is
          // the honest thing to pass rather than half an event the
          // screen would throw away anyway. Site is required: post ids
          // are per-blog, so an id alone is ambiguous.
          arguments: {
            'event': {'id': related.id, 'site': related.site ?? 'GB'},
          },
        );
        break;

      case 'venue':
        if (related.id.isEmpty) return;

        Navigator.pushNamed(
          context,
          // venueDetails, plural — and venueId is interpolated into a
          // String at the route, so the String goes straight through.
          AppRoutes.venueDetails,
          arguments: {'venueId': related.id},
        );
        break;

      default:
        break;
    }
  }

  /// Open the thing the activity is about, and log that it was opened.
  ///
  /// 'opened' is the response the whole experiment is measured on: it is
  /// the difference between an item somebody scrolled past and one they
  /// cared enough to tap.
  void _open(ActivityItem item) {
    ActivityFeedApi.respond(activityId: item.id, response: 'opened');

    switch (item.targetType) {
      case 'vehicle':
        Navigator.pushNamed(
          context,
          AppRoutes.vehicleDetail,
          // A String: the route hands garageId straight to
          // VehicleDetailScreen without coercing it.
          arguments: {'garageId': item.targetId},
        );
        break;

      case 'post':
        final postId = int.tryParse(item.targetId) ?? 0;

        if (postId <= 0) return;

        Navigator.pushNamed(
          context,
          AppRoutes.postDetail,
          // An int here, unlike vehicleDetail — postDetail calls
          // toString() on what it is given.
          arguments: {'postId': postId},
        );
        break;

      case 'group':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GlobalGroupScreen(slug: item.targetId),
          ),
        );
        break;

      // A gallery has no screen of its own to open yet, so the card is
      // still worth showing and simply does not go anywhere.
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return const _ActivitySkeleton();
    }

    final feed = _feed;

    // Null means the call failed or we are not allowed to make it,
    // which is different from a feed that came back empty.
    if (feed == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            GroupEmptyNote(
              title: 'Not available',
              body: 'The activity feed could not be loaded. It is still '
                  'being tested, so this is expected on most accounts.',
              theme: theme,
            ),
          ],
        ),
      );
    }

    final items = feed.items
        .where((item) => !_dismissed.contains(item.id))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _TestingBanner(theme: theme),

          if (feed.interests.isNotEmpty)
            _InterestStrip(interests: feed.interests, theme: theme),

          if (items.isEmpty)
            GroupEmptyNote(
              title: _emptyTitle(feed),
              body: _emptyBody(feed),
              theme: theme,
            )
          else
            ...items.map(
              (item) => _ActivityCard(
                item: item,
                theme: theme,
                kept: _kept.contains(item.id),
                related: _related[item.id],
                relatedAsked: _related.containsKey(item.id),
                relatedLoading: _relatedLoading.contains(item.id),
                onOpen: () => _open(item),
                onInterested: () => _respond(item, 'interested'),
                onNotInterested: () => _respond(item, 'not_interested'),
                onRelatedRetry: () => _loadRelated(item),
                onRelatedTap: _openRelated,
              ),
            ),

          // At the foot, not the top: it answers "I have read these,
          // what else", which is a question you only have once you have
          // got to the bottom.
          if (items.isNotEmpty) _refreshButton(theme),
        ],
      ),
    );
  }

  Widget _refreshButton(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _refreshing ? null : _showAnother,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDEDED)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_refreshing)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primaryColor,
                    ),
                  )
                else
                  Icon(
                    Icons.refresh_rounded,
                    size: 17,
                    color: theme.primaryColor,
                  ),
                const SizedBox(width: 9),
                Text(
                  _refreshing ? 'Finding more' : 'Show me something else',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Three empties, three different things to say. Lumping them together
  /// would hide the only thing worth knowing: which part is not working.
  String _emptyTitle(ActivityFeed feed) {
    switch (feed.reason) {
      case 'not_installed':
        return 'Not set up yet';
      case 'no_interests':
        return 'Nothing to go on';
      default:
        return 'All caught up';
    }
  }

  String _emptyBody(ActivityFeed feed) {
    switch (feed.reason) {
      case 'not_installed':
        return 'The activity tables have not been created on this '
            'server yet.';
      case 'no_interests':
        return 'Add a car to your garage, or like a few, and this will '
            'start finding things. Right now there is nothing to match '
            'against.';
      default:
        return 'Nothing new about the cars you are into. Check back '
            'once there is more activity.';
    }
  }
}

/// A plain statement that this is not finished, and an ask.
///
/// Two jobs. It says the feature is an experiment, so the first instinct
/// on seeing a thin feed is to judge whether the matching is any good
/// rather than to report it as broken. And it says what the buttons are
/// FOR — that pressing them is what shapes the feed — because somebody
/// who thinks Interested is a bookmark will not bother, and the buttons
/// are the only thing here that teaches the profile anything.
///
/// Addressed to a person rather than to a tester, even though only
/// admins can see it today. The wording is what it would say to
/// everybody, which is the point: if it does not read well now, it will
/// not read well when the tab opens up.
class _TestingBanner extends StatelessWidget {
  const _TestingBanner({required this.theme});

  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0E2C4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.science_outlined,
            size: 17,
            color: Color(0xFF8A6D28),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Experimental Feature. Tell us what you like and what you '
              'don\'t — it is what shapes your feed and the cars we '
              'put in front of you.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6A5520),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the feed thinks this person is into, strongest first.
class _InterestStrip extends StatelessWidget {
  const _InterestStrip({required this.interests, required this.theme});

  final List<ActivityInterest> interests;
  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'WE THINK YOU LIKE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: Color(0xFF9A9A9A),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: interests.map((interest) {
                // The strongest interest is the one driving the feed, so
                // it is the one that looks like it.
                final lead = interest.strength >= 100;

                return Container(
                  margin: const EdgeInsets.only(right: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: lead
                        ? theme.primaryColor.withValues(alpha: 0.12)
                        : const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: lead
                          ? theme.primaryColor.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    interest.make,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: lead
                          ? const Color(0xFF6A5520)
                          : const Color(0xFF55555A),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// One suggestion.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.item,
    required this.theme,
    required this.kept,
    required this.related,
    required this.relatedAsked,
    required this.relatedLoading,
    required this.onOpen,
    required this.onInterested,
    required this.onNotInterested,
    required this.onRelatedRetry,
    required this.onRelatedTap,
  });

  final ActivityItem item;
  final ThemeProvider theme;
  final bool kept;

  /// Null and [relatedAsked] false: never asked. Null and asked: the
  /// fetch failed. Non-null: an answer, possibly an empty one.
  final ActivityRelatedSet? related;
  final bool relatedAsked;
  final bool relatedLoading;

  final VoidCallback onOpen;
  final VoidCallback onInterested;
  final VoidCallback onNotInterested;
  final VoidCallback onRelatedRetry;
  final ValueChanged<ActivityRelated> onRelatedTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                if (item.image != null) _photo(),
                _body(),
              ],
            ),
          ),
          _actions(),
          if (kept) _relatedSection(),
        ],
      ),
    );
  }

  /// "If you like this, you might like these", under the card.
  ///
  /// Only ever shown once somebody has tapped Interested — it is an
  /// answer to that tap, not something to offer unprompted.
  Widget _relatedSection() {
    if (relatedLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          color: Color(0xFFFAFAFA),
          border: Border(top: BorderSide(color: Color(0xFFEDEDED))),
        ),
        child: Center(
          child: SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primaryColor,
            ),
          ),
        ),
      );
    }

    final set = related;

    if (set == null) {
      // Asked and failed. A retry rather than silence: "nothing to
      // suggest" and "the call did not land" are different answers.
      if (!relatedAsked) return const SizedBox.shrink();

      return _relatedShell(
        child: InkWell(
          onTap: onRelatedRetry,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Could not load suggestions · tap to retry',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A8A8A),
              ),
            ),
          ),
        ),
      );
    }

    if (set.items.isEmpty) {
      return _relatedShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            set.located
                ? 'Nothing else to suggest for this one yet.'
                : 'No groups for this one, and we do not know where you '
                      'are, so there are no events or venues to suggest.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8A8A8A),
            ),
          ),
        ),
      );
    }

    return _relatedShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          ...set.items.map(_relatedRow),
          if (!set.located) ...[
            const SizedBox(height: 6),
            Text(
              'Groups only — we do not know where you are, so no events '
              'or venues.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The grey tray the suggestions sit in, with its heading.
  Widget _relatedShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOU MIGHT ALSO LIKE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: Colors.grey.shade500,
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _relatedRow(ActivityRelated related) {
    return InkWell(
      onTap: () => onRelatedTap(related),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              // A circle for a person, a rounded square for a place or
              // a thing. Mixing the two shapes in one list is what
              // tells them apart at a glance, before any label is read.
              borderRadius: BorderRadius.circular(
                related.type == 'person' ? 21 : 8,
              ),
              child: SizedBox(
                width: 42,
                height: 42,
                child: related.image != null
                    ? CachedNetworkImage(
                        imageUrl: related.image!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: const Color(0xFFEFEFEF)),
                        errorWidget: (_, _, _) => _relatedFallback(related),
                      )
                    : _relatedFallback(related),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    related.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    related.subtitle ?? _relatedKind(related.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A8A8A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    related.why,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      // Gold for a match on taste, grey when proximity
                      // is the only claim. The whole point of the test
                      // is telling those two apart.
                      color: related.isTasteMatch
                          ? theme.primaryColor
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _relatedFallback(ActivityRelated related) {
    return Container(
      color: const Color(0xFFEFEFEF),
      child: Icon(
        _relatedIcon(related.type),
        size: 18,
        color: Colors.grey.shade500,
      ),
    );
  }

  IconData _relatedIcon(String type) {
    switch (type) {
      case 'person':
        return Icons.person_outline_rounded;
      case 'group':
        return Icons.groups_outlined;
      case 'event':
        return Icons.event_outlined;
      case 'venue':
        return Icons.place_outlined;
      default:
        return Icons.explore_outlined;
    }
  }

  String _relatedKind(String type) {
    switch (type) {
      case 'person':
        return 'Owner';
      case 'group':
        return 'Group';
      case 'event':
        return 'Event';
      case 'venue':
        return 'Venue';
      default:
        return '';
    }
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 10),
      child: Row(
        children: [
          GroupAvatar(url: item.user?.image, radius: 18, theme: theme),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: item.user?.name ?? 'Someone',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(
                        text: item.action,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    color: Color(0xFF111111),
                  ),
                ),
                if (item.ago.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.ago,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFA0A0A0),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(_icon, size: 17, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  IconData get _icon {
    switch (item.verb) {
      case 'added_vehicle':
        return Icons.directions_car_filled_outlined;
      case 'added_dream':
        return Icons.star_outline_rounded;
      case 'logged_spot':
        return Icons.camera_alt_outlined;
      // Recognised off the image rather than typed in, so a different
      // glyph from a spot even though the card reads much the same.
      case 'photographed':
        return Icons.photo_camera_back_outlined;
      case 'joined_group':
        return Icons.groups_outlined;
      case 'created_gallery':
        return Icons.photo_library_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }

  Widget _photo() {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: CachedNetworkImage(
        imageUrl: item.image!,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(color: const Color(0xFFF4F4F4)),
        errorWidget: (_, _, _) => Container(
          color: const Color(0xFFF4F4F4),
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: Color(0xFF111111),
            ),
          ),
          if (item.subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              item.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B6B6B),
              ),
            ),
          ],
          if (item.why != null) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 13,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item.why!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
                // The score the ordering is built on. Admin-only screen,
                // so it can show its working.
                Text(
                  '${item.score}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFBDBDBD),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    if (kept) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          color: Color(0xFFF7F7F7),
          border: Border(top: BorderSide(color: Color(0xFFEDEDED))),
        ),
        child: Text(
          'More like this',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: theme.primaryColor,
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _button(
              label: 'Interested',
              icon: Icons.thumb_up_outlined,
              onTap: onInterested,
              colour: theme.primaryColor,
            ),
          ),
          const SizedBox(
            height: 42,
            child: VerticalDivider(width: 1, color: Color(0xFFEDEDED)),
          ),
          Expanded(
            child: _button(
              label: 'Not for me',
              icon: Icons.thumb_down_outlined,
              onTap: onNotInterested,
              colour: const Color(0xFF9A9A9A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required Color colour,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: colour),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shape of the list before it arrives.
class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return GroupShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          3,
          (_) => Container(
            height: 300,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
