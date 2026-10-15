import 'package:drivelife/main.dart';
import 'package:drivelife/screens/garage/garage_list_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A horizontally scrolling row of shortcuts shown at the top of the feed.
///
/// The tiles are hard-coded for now — swap [_items] for API data when the
/// endpoint exists. Each tile renders its [HotShortcut.imagePath] when one is set
/// and falls back to a dark gradient otherwise, so the row looks right before
/// any imagery is wired up.
///
/// Destinations mirror the header pills in `posts_screen.dart` so both routes
/// into a section behave identically.
class HotRightNow extends StatelessWidget {
  const HotRightNow({super.key});

  static const _gold = Color(0xFFB9965A);
  static const _dark = Color(0xFF1A1A1A);

  static const double _cardWidth = 225;
  static const double _cardHeight = 156;
  static const double _horizontalPadding = 16;

  // TODO: replace with real data when the endpoint exists.
  //
  // Destinations are named, never numbered. These used to be bare 1, 2, 3
  // from an older bottom bar where they meant Events, Venues and Clubs.
  // Events and Venues have since become sections of Home and the bar has been
  // reordered twice, so the numbers stayed valid and quietly started meaning
  // something else. Nothing crashed, which is why it survived two rounds of
  // changes before anyone noticed.
  //
  // test/hot_shortcuts_test.dart holds each tile to where it should go.
  @visibleForTesting
  static final List<HotShortcut> items = [
    HotShortcut(
      title: 'Find Events',
      imagePath: 'assets/hot-images/01-events-b.jpg',
      // Events is a section of Home, so this has to set both.
      onTap: (context) => context.read<BottomNavProvider>().openHomeSection(
        BottomNavProvider.events,
      ),
    ),
    HotShortcut(
      title: 'Popular Venues',
      imagePath: 'assets/hot-images/02-venues.jpg',
      // Places is a section of Home, so this has to set both.
      onTap: (context) => context.read<BottomNavProvider>().openHomeSection(
        BottomNavProvider.places,
      ),
    ),
    HotShortcut(
      title: 'Discover Groups',
      imagePath: 'assets/hot-images/03-clubs.jpg',
      // Groups is a destination of its own again, not a section of Home.
      onTap: (context) =>
          context.read<BottomNavProvider>().setIndex(BottomNavProvider.groups),
    ),
    HotShortcut(
      title: 'Your Garage',
      imagePath: 'assets/hot-images/04-garage.jpg',
      onTap: (context) =>
          NavigationHelper.navigateTo(context, const GarageListScreen()),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No heading. The cards say what they are, and a row of two tiles
        // under a title reads as a section of a page rather than part of a
        // feed — which is what it is now that the feed selector sits below
        // it rather than above.
        const SizedBox(height: 12),
        SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _HotCard(item: items[index]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// One tile in the row, and where tapping it goes.
class HotShortcut {
  final String title;
  final void Function(BuildContext context) onTap;
  final String? imagePath;

  HotShortcut({required this.title, required this.onTap, this.imagePath});
}

class _HotCard extends StatelessWidget {
  final HotShortcut item;

  const _HotCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: HotRightNow._cardWidth,
        height: HotRightNow._cardHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _background(),
            // Keeps the title legible over any photograph.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Sits on top so the ripple reads over the artwork.
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => item.onTap(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _background() {
    final path = item.imagePath;
    if (path == null || path.isEmpty) return const _PlaceholderBackground();

    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _PlaceholderBackground(),
    );
  }
}

/// Shown until real imagery is supplied — a dark tile with a subtle gold wash
/// so the row still reads as DriveLife rather than as a broken image.
class _PlaceholderBackground extends StatelessWidget {
  const _PlaceholderBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HotRightNow._gold, HotRightNow._dark],
        ),
      ),
    );
  }
}
