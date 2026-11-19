import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/screens/roads/road_detail_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';

/// The roads a vehicle has been down, in two sizes.
///
/// ── WHY BOTH ───────────────────────────────────────────────────────
///
/// [VehicleRoadsPreview] sits above the tabs and shows the two most
/// recent. It is a hook, not a list: a car with thirty roads against
/// it would otherwise push everything else off the page, and the
/// question it answers is "does this car get driven", not "where".
///
/// [VehicleRoadsList] is the tab, and is where the rest of them live.
///
/// Neither fetches. The page loads the roads once and hands the same
/// list to both, so the preview cannot disagree with the tab — which
/// it would, the first time one of them refreshed and the other did
/// not.
class VehicleRoadsPreview extends StatelessWidget {
  final List<DrivingRoad> roads;
  final Color accent;

  /// Jumps to the tab. Null hides the "See all" affordance, for a
  /// build where the tab is not there.
  final VoidCallback? onSeeAll;

  /// How many to show before the rest become somebody else's problem.
  static const int _shown = 2;

  const VehicleRoadsPreview({
    super.key,
    required this.roads,
    required this.accent,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing, not an empty state. Most vehicles have never had a road
    // recorded against them, and a heading over a blank space reads as
    // something that failed to load.
    if (roads.isEmpty) return const SizedBox.shrink();

    final shown = roads.take(_shown).toList();
    final more = roads.length - shown.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 19, color: accent),
              const SizedBox(width: 8),
              const DlHeading(
                'Roads Driven',
                fontSize: 19,
                color: Color(0xFF111111),
              ),
              const Spacer(),
              // Only when there is something behind it. "See all 2" on
              // a list showing both of them is a button that does
              // nothing.
              if (more > 0 && onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Text(
                    'See all ${roads.length}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          for (final road in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RoadRow(road: road, accent: accent),
            ),
        ],
      ),
    );
  }
}

/// Every road, as the tab shows them.
class VehicleRoadsList extends StatelessWidget {
  final List<DrivingRoad> roads;
  final Color accent;

  const VehicleRoadsList({
    super.key,
    required this.roads,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (roads.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          children: [
            const Icon(
              Icons.route_rounded,
              size: 42,
              color: Color(0xFFD5D5D5),
            ),
            const SizedBox(height: 14),
            const Text(
              'No roads yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Mark a road as driven and pick this vehicle, and it '
              'will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: roads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => RoadRow(road: roads[i], accent: accent),
    );
  }
}

/// One road, with its photograph.
///
/// The same row in the preview and in the tab, so moving between them
/// is the same list getting longer rather than a different design.
class RoadRow extends StatelessWidget {
  final DrivingRoad road;
  final Color accent;

  const RoadRow({super.key, required this.road, required this.accent});

  @override
  Widget build(BuildContext context) {
    // When, if they said. Month and year — see
    // DrivingRoad.droveOnLabel for why not the day.
    final when = road.droveOnLabel;

    final facts = [
      road.lengthLabel,
      road.region,
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return Material(
      color: const Color(0xFFF6F6F6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RoadDetailScreen(road: road)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 86,
                  height: 64,
                  // The delivery URL, not the stored id — see
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      road.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111111),
                      ),
                    ),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        facts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF8A8A8A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Driven $when',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
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

/// What a road with no photograph looks like.
///
/// A shape rather than a grey box: a road is a line, and an empty
/// rectangle in a list of photographs reads as one that failed to
/// load.
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
          color: Colors.white.withValues(alpha: 0.5),
          size: 24,
        ),
      ),
    );
  }
}
