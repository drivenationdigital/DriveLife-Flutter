import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Whether a vehicle is the account's featured one — the gold star.
///
/// primary_car is a three-way flag on ce_user_garage, not a boolean:
/// '1' is the featured car, '2' is a dream car, anything else is ordinary.
bool vehicleIsPrimary(dynamic vehicle) =>
    vehicle['primary_car']?.toString() == '1';

/// One vehicle: the photograph, then what it is.
class VehicleCard extends StatelessWidget {
  final dynamic vehicle;
  final VoidCallback onTap;

  const VehicleCard({required this.vehicle, required this.onTap});

  /// "2023 · POLESTAR", or just the make when no year is recorded.
  ///
  /// There is no year column on ce_user_garage today, so most vehicles will
  /// show the make alone. Written to take one the moment the field exists
  /// rather than inventing one from owned_since, which is a different fact:
  /// a 1998 MX-5 owned since 2019 would read as a 2019 car.
  String get _kicker {
    final make = (vehicle['make'] ?? '').toString().trim().toUpperCase();
    final year = (vehicle['year'] ?? '').toString().trim();

    if (year.isEmpty) return make;
    return '$year · $make';
  }

  String get _title {
    final model = (vehicle['model'] ?? '').toString().trim();
    final variant = (vehicle['variant'] ?? '').toString().trim();

    return [model, variant].where((p) => p.isNotEmpty).join(' ');
  }

  /// "Owned since 2019", or nothing when the date is missing or unreadable.
  String? get _owned {
    final raw = (vehicle['owned_since'] ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final year =
        DateTime.tryParse(raw)?.year ??
        int.tryParse(RegExp(r'\b(\d{4})\b').firstMatch(raw)?.group(1) ?? '');

    return year == null ? null : 'Owned since $year';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final cover = (vehicle['cover_photo'] ?? '').toString().trim();
    final owned = _owned;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // A soft lift rather than a border: the page is white and the card
        // is white, so without this the only thing separating them is the
        // photograph. Low and wide, which is what reads as paper rather
        // than as a drop shadow.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                // 16/9, measured: the photo is ~645x355 in the mockup, which
                // is 1.82. A car is a wide subject and the extra height was
                // cropping the ends off it.
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover.isEmpty)
                      ColoredBox(color: Colors.grey.shade100)
                    else
                      CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        // Decoded at the width it is drawn, not the source's.
                        memCacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        placeholder: (_, __) =>
                            ColoredBox(color: Colors.grey.shade100),
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: Colors.grey.shade100,
                          child: Icon(
                            Icons.directions_car_outlined,
                            size: 38,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),

                    if (vehicleIsPrimary(vehicle))
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            size: 21,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 15, 18, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_kicker.isNotEmpty)
                      Text(
                        _kicker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      _title.isEmpty ? 'Vehicle' : _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Color(0xFF111111),
                      ),
                    ),
                    if (owned != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        owned,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
