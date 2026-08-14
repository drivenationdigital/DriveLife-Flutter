import 'package:drivelife/main.dart';
import 'package:drivelife/screens/garage/garage_list_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A horizontally scrolling row of shortcuts shown at the top of the feed.
///
/// The tiles are hard-coded for now — swap [_items] for API data when the
/// endpoint exists. Each tile renders its [_HotItem.imageUrl] when one is set
/// and falls back to a dark gradient otherwise, so the row looks right before
/// any imagery is wired up.
///
/// Destinations mirror the header pills in `posts_screen.dart` so both routes
/// into a section behave identically.
class HotRightNow extends StatelessWidget {
  const HotRightNow({super.key});

  static const _gold = Color(0xFFB9965A);
  static const _dark = Color(0xFF1A1A1A);

  static const double _cardWidth = 190;
  static const double _cardHeight = 132;
  static const double _horizontalPadding = 16;

  // TODO: replace with real data when the endpoint exists.
  static final List<_HotItem> _items = [
    _HotItem(
      title: 'Find Events',
      imagePath: 'assets/hot-images/01-events-b.jpg',
      // Events tab (bottom nav index 1)
      onTap: (context) => context.read<BottomNavProvider>().setIndex(1),
    ),
    _HotItem(
      title: 'Popular Venues',
      imagePath: 'assets/hot-images/02-venues.jpg',
      // Venues/Places tab (bottom nav index 2)
      onTap: (context) => context.read<BottomNavProvider>().setIndex(2),
    ),
    _HotItem(
      title: 'Discover Clubs',
      imagePath: 'assets/hot-images/03-clubs.jpg',
      // Clubs tab (bottom nav index 3)
      onTap: (context) => context.read<BottomNavProvider>().setIndex(3),
    ),
    _HotItem(
      title: 'Your Garage',
      imagePath: 'assets/hot-images/04-garage.jpg',
      onTap: (context) =>
          NavigationHelper.navigateTo(context, const GarageListScreen()),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            _horizontalPadding,
            16,
            _horizontalPadding,
            12,
          ),
          child: Text(
            'Hot right now',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _HotCard(item: _items[index]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _HotItem {
  final String title;
  final void Function(BuildContext context) onTap;
  final String? imagePath;

  _HotItem({required this.title, required this.onTap, this.imagePath});
}

class _HotCard extends StatelessWidget {
  final _HotItem item;

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
                    fontSize: 15,
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
