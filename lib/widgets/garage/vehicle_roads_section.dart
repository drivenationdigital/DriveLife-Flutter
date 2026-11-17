import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/screens/roads/road_detail_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';

/// The roads this vehicle has been down, on its own page.
///
/// ── WHY IT IS A WIDGET AND NOT A TAB ────────────────────────────────
///
/// A fourth tab would mean the TabController's length, the Tab list and
/// the TabBarView's children all having to agree about a feature flag —
/// three places to keep in step for something most vehicles have
/// nothing to show in.
///
/// This draws nothing at all when there is nothing: no flag, no roads,
/// no server, no section. Which also means the page it sits on cannot
/// be broken by this one being wrong, and roads stay removable in one
/// line.
///
/// ── AND WHY IT ASKS RATHER THAN BEING TOLD ──────────────────────────
///
/// The vehicle payload knows nothing about roads and should not start
/// to. One request, made by the thing that needs the answer, keeps the
/// garage API exactly as it was.
class VehicleRoadsSection extends StatefulWidget {
  final int garageId;
  final Color accent;

  const VehicleRoadsSection({
    super.key,
    required this.garageId,
    required this.accent,
  });

  @override
  State<VehicleRoadsSection> createState() => _VehicleRoadsSectionState();
}

class _VehicleRoadsSectionState extends State<VehicleRoadsSection> {
  List<DrivingRoad> _roads = const [];

  @override
  void initState() {
    super.initState();

    if (FeatureFlags.drivingRoads) _load();
  }

  @override
  void didUpdateWidget(VehicleRoadsSection old) {
    super.didUpdateWidget(old);

    // The same widget can be handed a different vehicle when the page
    // is reused, and a stale list under a new car is worse than none.
    if (old.garageId != widget.garageId && FeatureFlags.drivingRoads) _load();
  }

  Future<void> _load() async {
    final roads = await RoadsAPI.forVehicle(widget.garageId);

    if (!mounted) return;

    setState(() => _roads = roads);
  }

  @override
  Widget build(BuildContext context) {
    // Nothing, not an empty state. Most vehicles have never had a road
    // recorded against them, and a heading over a blank space reads as
    // something that failed to load.
    if (!FeatureFlags.drivingRoads || _roads.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 19, color: widget.accent),
              const SizedBox(width: 8),
              const DlHeading(
                'Roads Driven',
                fontSize: 19,
                color: Color(0xFF111111),
              ),
              const Spacer(),
              Text(
                '${_roads.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9A9A9A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sideways. A vertical list inside a page that already
          // scrolls would either fight it or have to be given a fixed
          // height, and this is a strip of souvenirs rather than a
          // list anybody browses.
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _roads.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _RoadChip(
                road: _roads[i],
                accent: widget.accent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoadDetailScreen(road: _roads[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadChip extends StatelessWidget {
  final DrivingRoad road;
  final Color accent;
  final VoidCallback onTap;

  const _RoadChip({
    required this.road,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // When, if they said. The month and year — see
    // DrivingRoad.droveOnLabel for why not the day.
    final when = road.droveOnLabel;

    return SizedBox(
      width: 168,
      child: Material(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      road.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: Color(0xFF111111),
                      ),
                    ),
                    if (road.region.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        road.region,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A8A8A),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if (road.lengthLabel.isNotEmpty)
                      Text(
                        road.lengthLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    if (road.lengthLabel.isNotEmpty && when.isNotEmpty)
                      const Text(
                        '  ·  ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBDBDBD),
                        ),
                      ),
                    if (when.isNotEmpty)
                      Flexible(
                        child: Text(
                          when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
