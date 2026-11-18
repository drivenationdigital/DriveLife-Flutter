import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/roads/add_road_screen.dart';
import 'package:drivelife/screens/roads/road_detail_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/nav/pinned_sliver_bar.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

/// Roads worth driving, nearest first.
///
/// ── WHY LOCATION IS OPTIONAL HERE ───────────────────────────────────
///
/// A roads list that demands a permission before showing anything is a
/// permission prompt with nothing behind it, and the honest answer to
/// "why do you want my location" is easier to accept once somebody can
/// see what they would get.
///
/// So: a location if there is one already, a list of everything if
/// there is not, and the prompt only when they ask for near me.
class RoadsListScreen extends StatefulWidget {
  /// The shell's scroll listener, when this is a Home section.
  ///
  /// ── WHY A SECTION AND A SCREEN AT ONCE ──────────────────────────
  ///
  /// It is a tab in the Home row beside Events and Places, and it is
  /// also pushed on its own from the create menu. The difference is
  /// entirely chrome: as a section the shell supplies a header and
  /// wants to be told about scrolling so the bottom bar can get out of
  /// the way; on its own it needs an app bar of its own instead.
  ///
  /// Null for the pushed version, which is what [header] being null
  /// decides.
  final ChromeVisibility? chrome;

  /// The shell's header and section tabs, drawn inside this screen's
  /// own scroll view so the scroll moves them.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent before
  /// it is laid out, so it has to be told rather than measured.
  final double headerHeight;

  const RoadsListScreen({
    super.key,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<RoadsListScreen> createState() => _RoadsListScreenState();
}

class _RoadsListScreenState extends State<RoadsListScreen>
    with TickerProviderStateMixin {
  List<DrivingRoad> _roads = const [];

  bool _loading = true;

  /// Whether the list on screen was measured from somewhere.
  bool _nearby = false;

  /// Whose roads are on screen.
  ///
  /// ── WHY "MINE" IS A VIEW AND NOT A SCREEN ───────────────────────
  ///
  /// Because a road somebody added and a road near them are the same
  /// object, opened the same way, and the question "did the one I
  /// added work" is asked from exactly here. A separate screen behind
  /// a menu would be a second place to maintain and one more tap from
  /// the only moment anybody wonders.
  bool _mine = false;

  /// How many of their own roads are still waiting to be checked.
  int _waiting = 0;

  /// Set when the radius found nothing and the whole country was shown
  /// instead.
  ///
  /// ── WHY THE FALLBACK EXISTS ─────────────────────────────────────
  ///
  /// The first two roads in the table were 55 and 62 miles from where
  /// they were being looked for, and the default radius was 50. The
  /// screen said "no roads near you yet", which was TRUE and useless:
  /// there were roads, they were a reasonable drive away, and nothing
  /// on screen suggested looking further.
  ///
  /// A feature with a handful of roads nationally cannot afford a
  /// correct empty screen. So an empty radius now asks for everything
  /// and says what it did.
  bool _widened = false;

  /// Where the question was asked from, kept so the national list can
  /// still be ordered by distance. Every row carries its midpoint, so
  /// that is arithmetic rather than another request.
  RoadPoint? _from;

  /// How far "near me" looks before widening.
  ///
  /// Further than the 50 it opened with. People drive two hours to a
  /// good road — treating 50 miles as the edge of the world is a
  /// judgement about commuting, not about driving for its own sake.
  static const double _radiusMiles = 100;

  /// Whether the server has roads switched on at all.
  ///
  /// Its own state because the screen it deserves is different: an
  /// empty list means "none near you", and this means "not yet", and
  /// showing the first for the second sends somebody looking for roads
  /// that were never there.
  bool _ready = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    if (_mine) {
      // No location, no radius, no widening. These are theirs
      // wherever they are, and sorting a list of five by distance
      // answers a question nobody asked of it.
      final roads = await RoadsAPI.mine();

      if (!mounted) return;

      setState(() {
        _roads = roads;
        _waiting = roads.where((r) => r.isPending).length;
        _nearby = false;
        _widened = false;
        _ready = RoadsAPI.lastReady;
        _loading = false;
      });

      return;
    }

    // A cached fix, with no GPS wait and no prompt. Somebody who has
    // already granted location to Discover gets a nearby list without
    // being asked anything; somebody who has not gets the full list.
    Position? here;

    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        final permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          here = await Geolocator.getLastKnownPosition();
        }
      }
    } catch (_) {
      // Any failure here is "no location", which is a state this screen
      // already handles.
    }

    final from = here == null
        ? null
        : RoadPoint(here.latitude, here.longitude);

    var roads = from == null
        ? await RoadsAPI.list()
        : await RoadsAPI.nearby(
            lat: from.lat,
            lng: from.lng,
            radius: _radiusMiles,
          );

    // Nothing within the radius, but there may be roads. Ask for all of
    // them rather than leaving a true and useless empty screen.
    var widened = false;

    if (roads.isEmpty && from != null && RoadsAPI.lastReady) {
      roads = _byDistance(await RoadsAPI.list(), from);
      widened = roads.isNotEmpty;
    }

    if (!mounted) return;

    setState(() {
      _roads = roads;
      _from = from;
      _nearby = from != null;
      _widened = widened;
      _ready = RoadsAPI.lastReady;
      _loading = false;
    });
  }

  /// The national list, measured and sorted from here.
  ///
  /// The server only works distances out for a nearby query, but every
  /// row carries its midpoint either way — so this costs one pass and
  /// no extra request, and the widened list still reads nearest first
  /// rather than newest first.
  List<DrivingRoad> _byDistance(List<DrivingRoad> roads, RoadPoint from) {
    final measured = roads
        .map(
          (road) => road.mid.isReal
              ? road.copyWith(distanceMiles: from.milesTo(road.mid))
              : road,
        )
        .toList();

    measured.sort((a, b) {
      // A road with no usable midpoint cannot be placed, so it goes
      // last rather than to the top on a distance of zero.
      final aMiles = a.distanceMiles <= 0 ? double.infinity : a.distanceMiles;
      final bMiles = b.distanceMiles <= 0 ? double.infinity : b.distanceMiles;

      return aMiles.compareTo(bMiles);
    });

    return measured;
  }

  Future<void> _add() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddRoadScreen()),
    );

    // A submitted road is pending, so it will not be in the published
    // list — but it IS visible to the person who sent it, and a list
    // that looks unchanged after a save reads as a save that failed.
    if (added == true && mounted) _load();
  }

  Future<void> _open(DrivingRoad road) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RoadDetailScreen(road: road)),
    );

    // Only when something was actually pressed in there. A detail
    // screen opened and closed should not cost a round trip.
    if (changed == true && mounted) _load();
  }

  /// Whether the shell is drawing the chrome above this.
  bool get _asSection => widget.header != null;

  /// How tall the switcher row is, declared because a pinned sliver
  /// has to say its extent up front. The row boxes itself to the same
  /// number, so the two cannot drift.
  static const double _switcherHeight = 62;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      // Only when it is a screen. As a section the shell above has
      // already drawn one, and a second would be two headers arguing.
      appBar: _asSection
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
              centerTitle: true,
              title: const Text(
                'Driving Roads',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      // Every scroll in here reports to the shell through this one
      // listener, which is what takes the bottom bar away and brings
      // it back. Harmless when there is no shell.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          color: theme.primaryColor,
          onRefresh: _load,
          child: CustomScrollView(
            // Always scrollable, so a short list still reaches far
            // enough for pull-to-refresh and for the chrome to be
            // scrolled away.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_asSection) _floatingChrome(),

              // Pinned, like the tab row on Places: the one control
              // that changes what the list IS should not have to be
              // scrolled back to.
              SliverPersistentHeader(
                pinned: true,
                delegate: PinnedSliverBar(
                  height: _switcherHeight,
                  child: _Switcher(
                    mine: _mine,
                    accent: theme.primaryColor,
                    onChanged: (mine) {
                      if (mine == _mine) return;

                      setState(() {
                        _mine = mine;
                        // Cleared rather than left behind: the old
                        // list under the other tab's heading is worse
                        // than a spinner.
                        _roads = const [];
                      });

                      _load();
                    },
                  ),
                ),
              ),

              ..._contentSlivers(theme),
            ],
          ),
        ),
      ),
      // ── NO FLOATING BUTTON ────────────────────────────────────
      //
      // It sat underneath the shell's bottom bar, which draws over
      // this screen rather than around it — a Scaffold inside a
      // destination cannot see the chrome above it, so it had no way
      // to know what it was hiding behind.
      //
      // Nothing is lost. Adding a road is a create action and the
      // create menu is where create actions live; the empty state
      // below offers it as well, for the one moment somebody is
      // looking at this screen with nothing on it.
    );
  }

  /// The shell's header, floating: it leaves as you scroll on and comes
  /// back the moment you scroll up, without having to reach the top.
  Widget _floatingChrome() {
    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        height: widget.headerHeight,
        vsync: this,
        child: widget.header!,
      ),
    );
  }

  List<Widget> _contentSlivers(ThemeProvider theme) {
    if (_loading) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        ),
      ];
    }

    if (!_ready) {
      return [
        _messageSliver(
          icon: Icons.cloud_off_rounded,
          title: 'Not switched on yet',
          body:
              'Driving roads are not available on this server. '
              'Nothing is wrong with the app.',
        ),
      ];
    }

    if (_roads.isEmpty) {
      if (_mine) {
        return [
          _messageSliver(
            icon: Icons.add_road_rounded,
            title: 'You have not added one yet',
            body:
                'Add a road you think is worth driving and it will show up '
                'here, with whether it has been checked yet.',
            action: 'Add a road',
          ),
        ];
      }

      // No longer "none near you": by this point the radius has been
      // dropped and the whole country asked for, so an empty list
      // means the table is empty.
      return [
        _messageSliver(
          icon: Icons.route_rounded,
          title: 'No roads yet',
          body: 'Nobody has added one yet. Yours could be the first.',
          action: 'Add a road',
        ),
      ];
    }

    return [
      SliverPadding(
        // Enough to clear the shell's bottom bar, which draws over
        // this screen rather than around it.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 108),
        sliver: SliverList.separated(
          itemCount: _roads.length + (_widened || _waitingNote ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i == 0) {
              if (_widened) return _widenedNote();
              if (_waitingNote) return _waitingBanner(theme);
            }

            final road = _roads[i - (_widened || _waitingNote ? 1 : 0)];

            return _RoadCard(
              road: road,
              accent: theme.primaryColor,
              showStatus: _mine,
              onTap: () => _open(road),
            );
          },
        ),
      ),
    ];
  }

  /// An empty state that says which kind of empty it is.
  ///
  /// [action] is offered only where it is the obvious next thing. On
  /// "the server has no roads switched on" there is nothing anybody
  /// here can do about it, and a button would be a lie.
  Widget _messageSliver({
    required IconData icon,
    required String title,
    required String body,
    String? action,
  }) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
        child: Column(
          children: [
            Icon(icon, size: 46, color: const Color(0xFFBDBDBD)),
            const SizedBox(height: 18),
            DlHeading(
              title,
              fontSize: 22,
              color: const Color(0xFF0B0B0B),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF6B6B6B)),
            ),
            if (action != null) ...[
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_road_rounded, size: 19),
                label: Text(
                  action,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Provider.of<ThemeProvider>(
                    context,
                    listen: false,
                  ).primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Whether there is something to say at the top of their own list.
  bool get _waitingNote => _mine && _waiting > 0;

  /// What "waiting to be checked" actually means, said once.
  ///
  /// Per road it would be noise on a list where most of them are
  /// waiting; said once at the top it answers the question the whole
  /// screen exists for.
  Widget _waitingBanner(ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 19, color: theme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _waiting == 1
                  ? 'One road is waiting to be checked. Only you can see '
                        'it until then.'
                  : '$_waiting roads are waiting to be checked. Only you '
                        'can see them until then.',
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF4A4A4A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Says the radius came up empty, rather than quietly showing the
  /// country and letting somebody think it is all local.
  Widget _widenedNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            size: 19,
            color: Color(0xFF6B6B6B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nothing within ${_radiusMiles.round()} miles. '
              'Showing every road, nearest first.',
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF4A4A4A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadCard extends StatelessWidget {
  final DrivingRoad road;
  final Color accent;
  final VoidCallback onTap;

  /// Whether to say what state this road is in.
  ///
  /// Only on somebody's own list. In a public one every road is
  /// published by definition, and a row of "Live" badges says nothing
  /// anybody needed.
  final bool showStatus;

  const _RoadCard({
    required this.road,
    required this.accent,
    required this.onTap,
    this.showStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final facts = [
      road.lengthLabel,
      road.awayLabel,
      road.region,
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 92,
                  height: 72,
                  // The URL, not the stored id — see
                  // DrivingRoad.coverUrl.
                  child: road.coverUrl.isNotEmpty
                      ? Image.network(
                          road.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _Placeholder(accent),
                        )
                      : _Placeholder(accent),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DlHeading(
                      road.title,
                      fontSize: 19,
                      color: const Color(0xFF0B0B0B),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        facts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B6B6B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    // Said out loud, because a road somebody submitted
                    // that is simply not in a list reads as lost.
                    if (showStatus && road.statusLabel.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _StatusChip(road: road, accent: accent),
                    ] else if (road.isPending) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Waiting to be checked',
                        style: TextStyle(
                          fontSize: 12,
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFBDBDBD),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Near me, or mine.
class _Switcher extends StatelessWidget {
  final bool mine;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _Switcher({
    required this.mine,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'All roads',
              on: !mine,
              accent: accent,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Segment(
              label: 'My roads',
              on: mine,
              accent: accent,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool on;
  final Color accent;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.on,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? accent : const Color(0xFFF2F2F2),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : const Color(0xFF6B6B6B),
            ),
          ),
        ),
      ),
    );
  }
}

/// What became of a road its owner submitted.
///
/// Coloured by what it means for them rather than by whether it is a
/// "good" status: amber is "nothing to do but wait", grey is "this is
/// over", green is "it worked".
class _StatusChip extends StatelessWidget {
  final DrivingRoad road;
  final Color accent;

  const _StatusChip({required this.road, required this.accent});

  @override
  Widget build(BuildContext context) {
    late final Color colour;
    late final IconData icon;

    if (road.isPublished) {
      colour = const Color(0xFF2E7D32);
      icon = Icons.check_circle_rounded;
    } else if (road.isPending) {
      colour = accent;
      icon = Icons.schedule_rounded;
    } else if (road.isRejected) {
      colour = const Color(0xFFB3261E);
      icon = Icons.block_rounded;
    } else {
      colour = const Color(0xFF8A8A8A);
      icon = Icons.visibility_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colour),
          const SizedBox(width: 5),
          Text(
            road.statusLabel,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final Color accent;

  const _Placeholder(this.accent);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.30), const Color(0xFF0B0B0B)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.route_rounded,
          color: Colors.white.withValues(alpha: 0.45),
          size: 26,
        ),
      ),
    );
  }
}
