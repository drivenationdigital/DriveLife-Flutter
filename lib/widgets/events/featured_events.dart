import 'package:flutter/material.dart';

/// Featured banner card with event details
class FeaturedBannerCard extends StatelessWidget {
  final String title;
  final String date;
  final String location;
  final String imageUrl;
  final VoidCallback? onTap;

  const FeaturedBannerCard({
    Key? key,
    required this.title,
    required this.date,
    required this.location,
    required this.imageUrl,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.grey.shade800),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 8,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        date,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Page indicator dots for the carousel
class CarouselPageIndicator extends StatelessWidget {
  final int itemCount;
  final int currentIndex;
  final Color activeColor;
  final Color inactiveColor;

  const CarouselPageIndicator({
    Key? key,
    required this.itemCount,
    required this.currentIndex,
    required this.activeColor,
    Color? inactiveColor,
  }) : inactiveColor = inactiveColor ?? const Color(0x80FFFFFF),
       super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        itemCount,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: currentIndex == index ? activeColor : inactiveColor,
          ),
        ),
      ),
    );
  }
}

/// Featured events carousel with page indicators
class FeaturedEventsCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> featuredEvents;
  final PageController pageController;
  final int currentPage;
  final Function(int) onPageChanged;
  final Function(Map<String, dynamic>) onEventTap;
  final Color primaryColor;
  final String Function(String date) formatEventDate;

  const FeaturedEventsCarousel({
    Key? key,
    required this.featuredEvents,
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
    required this.onEventTap,
    required this.primaryColor,
    required this.formatEventDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240, // Increased from 220 to fix overflow
      child: Stack(
        children: [
          PageView(
            controller: pageController,
            onPageChanged: onPageChanged,
            children: featuredEvents.map((event) {
              final title = event['title'] ?? 'Featured Event';
              final date = event['start_date'] != null
                  ? formatEventDate(event['start_date'])
                  : 'TBA';
              final location = event['location'] ?? 'TBA';
              final imageUrl =
                  event['thumbnail'] ??
                  'https://via.placeholder.com/800x400/000000/ffffff?text=No+Image';

              return FeaturedBannerCard(
                title: title,
                date: date,
                location: location,
                imageUrl: imageUrl,
                onTap: () => onEventTap(event),
              );
            }).toList(),
          ),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: CarouselPageIndicator(
              itemCount: featuredEvents.length,
              currentIndex: currentPage,
              activeColor: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
