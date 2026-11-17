import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/roads/road_detail_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
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
  const RoadsListScreen({super.key});

  @override
  State<RoadsListScreen> createState() => _RoadsListScreenState();
}

class _RoadsListScreenState extends State<RoadsListScreen> {
  List<DrivingRoad> _roads = const [];

  bool _loading = true;

  /// Whether the list on screen was measured from somewhere.
  bool _nearby = false;

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

    final roads = here != null
        ? await RoadsAPI.nearby(lat: here.latitude, lng: here.longitude)
        : await RoadsAPI.list();

    if (!mounted) return;

    setState(() {
      _roads = roads;
      _nearby = here != null;
      _ready = RoadsAPI.lastReady;
      _loading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
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
      body: RefreshIndicator(
        color: theme.primaryColor,
        onRefresh: _load,
        child: _body(theme),
      ),
    );
  }

  Widget _body(ThemeProvider theme) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (!_ready) {
      return _message(
        icon: Icons.cloud_off_rounded,
        title: 'Not switched on yet',
        body:
            'Driving roads are not available on this server. '
            'Nothing is wrong with the app.',
      );
    }

    if (_roads.isEmpty) {
      return _message(
        icon: Icons.route_rounded,
        title: _nearby ? 'No roads near you yet' : 'No roads yet',
        body: _nearby
            ? 'Nobody has added a road around here. Pull down to look again.'
            : 'The first ones are on their way.',
      );
    }

    return ListView.separated(
      // Always scrollable, so a one-item list can still be pulled to
      // refresh — which is the only way back from an empty one.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: _roads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _RoadCard(
        road: _roads[i],
        accent: theme.primaryColor,
        onTap: () => _open(_roads[i]),
      ),
    );
  }

  /// An empty state that says which kind of empty it is.
  Widget _message({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
      children: [
        Icon(icon, size: 46, color: const Color(0xFFBDBDBD)),
        const SizedBox(height: 18),
        Center(
          child: DlHeading(
            title,
            fontSize: 22,
            color: const Color(0xFF0B0B0B),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Color(0xFF6B6B6B)),
        ),
      ],
    );
  }
}

class _RoadCard extends StatelessWidget {
  final DrivingRoad road;
  final Color accent;
  final VoidCallback onTap;

  const _RoadCard({
    required this.road,
    required this.accent,
    required this.onTap,
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
                  child: road.coverImage.isNotEmpty
                      ? Image.network(
                          road.coverImage,
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
                    // that is simply not in the list reads as lost.
                    if (road.isPending) ...[
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
