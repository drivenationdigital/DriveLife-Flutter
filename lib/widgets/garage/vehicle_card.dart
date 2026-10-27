import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// How wide the card's photograph is against its height.
///
/// 16:9, which is both what the mockup draws (644x362px on the frame, so
/// 1.779, on a 358pt card) and what a sweep of the alternatives picks.
///
/// The sweep is worth recording, because the obvious instinct — shorten
/// the card so it suits landscape photographs — is backwards. The box is
/// `background-size: cover`, so it crops whichever axis the source has to
/// spare. A source WIDER than the box loses the ends of the car; a source
/// TALLER than the box loses sky and tarmac. Only the first is
/// destructive, so it is weighted three times the second.
///
/// Scored that way against a realistic mix of uploads, the best aspect is
/// always one of the common source aspects and never between them — the
/// objective is piecewise linear in the box aspect, so its maximum sits on
/// a kink. In practice that means 16:9 (201pt of photo) or 4:3 (268pt),
/// with nothing in between ever winning and nothing below 16:9 ever
/// winning at all. Every step shorter than this is strictly worse: at 1.9
/// a 4:3 phone photo loses 30% of its height instead of 25%, and the only
/// thing bought with it is 13pt of card.
///
/// 4:3 wins only if uploads are overwhelmingly 4:3 straight off a phone,
/// and it costs 67pt of height per card to take it. If the real
/// distribution ever gets sampled and comes back that lopsided, this
/// should move to 4/3 — not to anything between.
const double _coverAspect = 16 / 9;

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
              // No Stack any more: the gold star that used to float in the
              // corner has gone, and the photograph is the only thing in
              // here. AspectRatio gives its child tight constraints, so it
              // still fills the box.
              AspectRatio(
                aspectRatio: _coverAspect,
                child: cover.isEmpty
                    ? ColoredBox(color: Colors.grey.shade100)
                    : CachedNetworkImage(
                        imageUrl: cover,
                        // CSS's `background-size: cover` with
                        // `background-position: center center`, exactly:
                        // scaled to the smallest size that still covers the
                        // box, with the overflow trimmed off both ends.
                        // center is already the default — it is written out
                        // so the pair is visible together.
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
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
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_kicker.isNotEmpty)
                      Text(
                        _kicker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // 11.5, from an 8.3pt cap height on "1998 . MAZDA".
                          fontSize: 11.5,
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
                        // 18.5, from a 13.3pt cap height on "MX-5 NB 1.8" --
                        // all capitals and figures, so the ink is the cap
                        // height rather than cap-to-descender.
                        fontSize: 18.5,
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
                          fontSize: 12.5,
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
