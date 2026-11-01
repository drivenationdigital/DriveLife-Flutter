import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/models/group_content.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';

/// The shared furniture of a group page.
///
/// Used by BOTH the global group screen and the club screen, so the two
/// cannot drift apart. That is the whole reason this file exists: the
/// alternative is a tab bar in each, which stays identical for about a
/// fortnight.
///
/// What is here is the part that is genuinely the same — the tab bar,
/// the garage card, the spot tile, the empty note. The HEADER is not:
/// a club's header sits over a cover photo with admin controls, a
/// global group's is a plain row, and forcing one widget to be both
/// would be worse than two honest ones.

/// One tab: a label and, optionally, a count in a pill.
class GroupTab {
  final String label;

  /// Null hides the pill. Use null rather than 0 for a tab whose count
  /// is meaningless (Latest) — a grey "0" beside it reads as broken.
  final int? count;

  const GroupTab(this.label, [this.count]);
}

/// The top tab bar from the group designs.
///
/// Scrollable, because clubs carry six tabs and four is already tight
/// on a small phone.
class GroupTabBar extends StatelessWidget {
  const GroupTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    required this.theme,
  });

  final TabController controller;
  final List<GroupTab> tabs;
  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorColor: theme.textColor,
      indicatorWeight: 2.4,
      dividerColor: Colors.transparent,
      labelColor: theme.textColor,
      unselectedLabelColor: theme.subtextColor,
      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      tabs: [for (var i = 0; i < tabs.length; i++) _tab(tabs[i], i)],
    );
  }

  /// The count pill inverts on the selected tab, which is what the
  /// designs show and what stops five numbers competing with the one
  /// label you are actually reading.
  Widget _tab(GroupTab tab, int index) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.index == index;

        return Tab(
          height: 52,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (tab.count != null) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? theme.textColor : theme.cardColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${tab.count}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? theme.textColorSecondary
                          : theme.subtextColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A vehicle tile: photo, like badge, name, owner and mod count.
class GroupGarageCard extends StatelessWidget {
  const GroupGarageCard({
    super.key,
    required this.vehicle,
    required this.theme,
    this.onTap,
    this.compact = false,
  });

  final GroupVehicle vehicle;
  final ThemeProvider theme;
  final VoidCallback? onTap;

  /// In the horizontal carousel there is no room for "· 14 mods".
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((vehicle.image ?? '').isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: vehicle.image!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          Container(color: theme.cardColor),
                    )
                  else
                    Container(
                      color: theme.cardColor,
                      child: Icon(
                        Icons.directions_car_outlined,
                        color: theme.subtextColor,
                      ),
                    ),

                  if (vehicle.likes > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.favorite,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              groupCompactCount(vehicle.likes),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 9),

          Text(
            vehicle.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: theme.textColor,
            ),
          ),

          const SizedBox(height: 5),

          Row(
            children: [
              GroupAvatar(url: vehicle.owner?.avatar, radius: 10, theme: theme),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  compact || vehicle.mods == 0
                      ? (vehicle.owner?.shortName ?? '')
                      : '${vehicle.owner?.shortName ?? ''} · ${vehicle.mods} mods',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: theme.subtextColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A square spot tile with its place name over a scrim.
class GroupSpotTile extends StatelessWidget {
  const GroupSpotTile({
    super.key,
    required this.spot,
    required this.theme,
    this.onTap,
  });

  final GroupSpot spot;
  final ThemeProvider theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = spot.location ?? spot.vehicle ?? '';

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if ((spot.image ?? '').isNotEmpty)
              CachedNetworkImage(
                imageUrl: spot.image!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(color: theme.cardColor),
              )
            else
              Container(color: theme.cardColor),

            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                ),
              ),
            ),

            if (label.isNotEmpty)
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The empty state that says WHY it is empty.
///
/// "Nothing here" and "nothing computed yet" look identical on screen
/// and only one of them is a problem — which is the confusion that
/// wastes an afternoon. So the reason goes on screen, not in a commit
/// message.
class GroupEmptyNote extends StatelessWidget {
  const GroupEmptyNote({
    super.key,
    required this.title,
    required this.body,
    required this.theme,
  });

  final String title;
  final String body;
  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.textColor,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              body,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: theme.subtextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An avatar that copes with having no picture.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.url,
    required this.radius,
    required this.theme,
  });

  final String? url;
  final double radius;
  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    if ((url ?? '').isEmpty) {
      return CircleAvatar(radius: radius, backgroundColor: theme.dividerColor);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.dividerColor,
      backgroundImage: CachedNetworkImageProvider(url!),
    );
  }
}

/// "2.1k", for a badge where the exact figure is not the point.
String groupCompactCount(int n) {
  if (n < 1000) return '$n';

  final thousands = n / 1000;

  return thousands >= 10
      ? '${thousands.round()}k'
      : '${thousands.toStringAsFixed(1)}k';
}
