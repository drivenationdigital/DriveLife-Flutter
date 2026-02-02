import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/models/venue_model.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VenueCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback? onTap;
  final bool showOwnerBadge;

  const VenueCard({
    super.key,
    required this.venue,
    this.onTap,
    this.showOwnerBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Image with logo overlay
              _buildImageSection(),
              const SizedBox(width: 12),

              // Venue details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      venue.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Location
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            venue.venueLocation,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Distance
                    Text(
                      '${venue.distance.toStringAsFixed(2)} miles away',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // View button
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  side: const BorderSide(color: Color(0xFFAE9159)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(
                    color: Color(0xFFAE9159),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return SizedBox(
      width: 100,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover image with caching
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: venue.coverImage,
              width: 100,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade200,
                child: Center(
                  child: CircularProgressIndicator(
                    color: const Color(0xFFAE9159),
                    strokeWidth: 2,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade200,
                child: Icon(
                  Icons.image_not_supported,
                  color: Colors.grey.shade400,
                  size: 30,
                ),
              ),
            ),
          ),

          // Logo overlay (centered)
          Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: venue.logo,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.white,
                    child: const SizedBox.shrink(),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.white,
                    child: Icon(
                      Icons.business,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
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
