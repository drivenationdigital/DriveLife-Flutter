import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/models/group_content.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
    // Ruled top and bottom, which is what separates the tabs from the
    // header above and the feed below. dividerColor is left transparent
    // because TabBar's own divider only draws underneath — the line
    // above it has to come from here.
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFECECEC)),
          bottom: BorderSide(color: Color(0xFFECECEC)),
        ),
      ),
      child: _bar(),
    );
  }

  Widget _bar() {
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
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: ClipRRect(
                // Top only. The foot of the photograph meets the white
                // the title sits on, so rounding it would leave two
                // slivers of background inside the card.
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(13),
                ),
                child: Stack(
                  fit: StackFit.expand,
                children: [
                  if ((vehicle.image ?? '').isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: vehicle.image!,
                      fit: BoxFit.cover,
                      // Half a screen at most, in a grid of two
                      // columns that keeps building as it scrolls.
                      memCacheWidth: 700,
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

            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    vehicle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: theme.textColor,
                    ),
                  ),

                  const SizedBox(height: 7),

                  Row(
                    children: [
                      GroupAvatar(
                        url: vehicle.owner?.avatar,
                        radius: 10,
                        theme: theme,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          compact || vehicle.mods == 0
                              ? (vehicle.owner?.shortName ?? '')
                              : '${vehicle.owner?.shortName ?? ''} · ${vehicle.mods} mods',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: theme.subtextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
                memCacheWidth: 700,
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
    // A person icon rather than a blank disc. An empty circle reads as
    // something still loading; this reads as somebody without a photo,
    // which is what it is — and it matches the club composer.
    if ((url ?? '').isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.dividerColor,
        child: Icon(Icons.person, size: radius, color: Colors.white),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.dividerColor,
      backgroundImage: CachedNetworkImageProvider(url!),
      // Without this, an avatar whose URL 404s throws an unhandled
      // image error — and this widget is in every group rail, every
      // activity card and every member list, so scrolling finds one
      // eventually. The circle falls back to its background colour.
      onBackgroundImageError: (_, _) {},
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

// ─── Loading skeletons ───────────────────────────────────────────────
//
// Shared by the group screen, the browse list and the groups page, so
// a group looks the same while it is arriving wherever you are.
//
// Shaped like the content they stand in for rather than a spinner in
// the middle of an empty screen: the page does not jump when the data
// lands, and the shapes themselves say what is coming.

/// A shimmering grey block.
class GroupBlock extends StatelessWidget {
  const GroupBlock({super.key, this.width, this.height = 14, this.radius = 7});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps blocks in the house shimmer.
///
/// One wrapper around a whole skeleton rather than one per block: the
/// animation then sweeps across the group as a single surface, which
/// is the effect, instead of every block pulsing on its own clock.
class GroupShimmer extends StatelessWidget {
  const GroupShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: child,
    );
  }
}

/// The Garages tab, mid-load: a two-up grid of cards.
class GroupGarageGridSkeleton extends StatelessWidget {
  const GroupGarageGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GroupShimmer(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: GroupBlock(radius: 12, height: 999)),
            const SizedBox(height: 9),
            const GroupBlock(width: 120),
            const SizedBox(height: 7),
            const GroupBlock(width: 80, height: 11),
          ],
        ),
      ),
    );
  }
}

/// The Spots tab, mid-load: a three-up grid of squares.
class GroupSpotGridSkeleton extends StatelessWidget {
  const GroupSpotGridSkeleton({super.key, this.count = 9});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GroupShimmer(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemBuilder: (_, _) => const GroupBlock(radius: 10, height: 999),
      ),
    );
  }
}

/// The Latest tab, mid-load: author line, picture, actions.
class GroupFeedSkeleton extends StatelessWidget {
  const GroupFeedSkeleton({super.key, this.count = 2});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GroupShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  const GroupBlock(width: 42, height: 42, radius: 21),
                  const SizedBox(width: 11),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      GroupBlock(width: 120, height: 15),
                      SizedBox(height: 6),
                      GroupBlock(width: 80, height: 12),
                    ],
                  ),
                ],
              ),
            ),
            const AspectRatio(
              aspectRatio: 1,
              child: GroupBlock(radius: 0, height: 999),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(
                children: [
                  GroupBlock(width: 56, height: 18),
                  SizedBox(width: 18),
                  GroupBlock(width: 56, height: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A list of group rows: thumbnail, name, subtitle.
///
/// Used by the browse page and by the Marque & model section.
class GroupRowsSkeleton extends StatelessWidget {
  const GroupRowsSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GroupShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const GroupBlock(width: 64, height: 48, radius: 10),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      GroupBlock(width: 160, height: 15),
                      SizedBox(height: 7),
                      GroupBlock(width: 90, height: 12),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A two-up grid of scene tiles.
class GroupTileGridSkeleton extends StatelessWidget {
  const GroupTileGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GroupShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final tile = (constraints.maxWidth - gap) / 2;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(
                    width: tile,
                    height: tile * 0.62,
                    child: const GroupBlock(radius: 16, height: 999),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
