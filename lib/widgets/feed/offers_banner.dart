import 'dart:async';
import 'package:drivelife/api/offers_api_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/widgets/feed/offers_redemption.dart';
import 'package:drivelife/widgets/feed/speedwell_challenge_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Fetches available offers and renders a banner (or auto-sliding carousel
/// if multiple offers exist). Matches the dark/gold DriveLife aesthetic.
class OffersBanner extends StatefulWidget {
  final List<EventOffer>? offers;
  const OffersBanner({super.key, this.offers});

  @override
  State<OffersBanner> createState() => _OffersBannerState();
}

class _OffersBannerState extends State<OffersBanner> {
  final PageController _pageController = PageController();

  List<EventOffer> _offers = [];
  bool _loading = true;
  int _currentPage = 0;
  Timer? _autoSlide;

  static const _gold = Color(0xFFB9965A);
  static const _dark = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    if (widget.offers != null) {
      _offers = widget.offers!;
      _loading = false;
      if (_offers.length > 1) _startAutoSlide();
    } 
  }

  // on dependency change, if offers were passed via constructor, update local state
  @override
  void didUpdateWidget(covariant OffersBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.offers != null && widget.offers != oldWidget.offers) {
      setState(() {
        _offers = widget.offers!;
        _loading = false;
        if (_offers.length > 1) _startAutoSlide();
      });
    }
  }

  void _startAutoSlide() {
    // _autoSlide = Timer.periodic(const Duration(seconds: 5), (_) {
    //   if (!mounted || !_pageController.hasClients) return;
    //   final next = (_currentPage + 1) % _offers.length;
    //   _pageController.animateToPage(
    //     next,
    //     duration: const Duration(milliseconds: 400),
    //     curve: Curves.easeInOut,
    //   );
    // });
  }

  @override
  void dispose() {
    _autoSlide?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onOfferTap(BuildContext context, EventOffer offer) {
    print('Tapped offer ${offer.id} (speedwell: ${offer.speedwellChallenge})');
    if (offer.speedwellChallenge) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SpeedwellChallengeScreen(
            offerId: offer.id,
            offerImage: offer.imageUrl,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfferRedemptionScreen(
            offerId: offer.id,
            offerImage: offer.imageUrl,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_offers.isEmpty) return const SizedBox.shrink();

    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _offers.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, i) =>
                  _BannerCard(offer: _offers[i], gold: theme.primaryColor, dark: theme.secondaryColor, 
                  // onRedeem: () => {
                  //   Navigator.push(
                  //     context,
                  //     MaterialPageRoute(
                  //       builder: (_) => OfferRedemptionScreen(offerId: _offers[i].id, offerImage: _offers[i].imageUrl),
                  //     ),
                  //   )
                  // }
                  onRedeem: () => _onOfferTap(context, _offers[i])
                  ),
            ),
          ),

          // Dot indicators — only shown when there are multiple offers
          if (_offers.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_offers.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? _gold : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Single banner card ────────────────────────────────────────────────────────

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double radius;

  const _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength = 6,
    this.gapLength = 5,
    this.radius = 14,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final total = metric.length;

    double distance = 0;
    bool draw = true;

    while (distance < total) {
      final len = draw ? dashLength : gapLength;
      final end = (distance + len).clamp(0, total);
      if (draw) {
        canvas.drawPath(metric.extractPath(distance, end.toDouble()), paint);
      }
      distance += len;
      draw = !draw;
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength ||
      old.radius != radius;
}

// ── Banner card ───────────────────────────────────────────────────────────────

class _BannerCard extends StatelessWidget {
  final EventOffer offer;
  final Color gold;
  final Color dark;
  final VoidCallback? onRedeem;

  const _BannerCard({
    required this.offer,
    required this.gold,
    required this.dark,
    this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = offer.locationName.isNotEmpty;

    return CustomPaint(
      painter: _DashedBorderPainter(
        color: gold.withOpacity(0.6),
        strokeWidth: 1.5,
        dashLength: 6,
        gapLength: 5,
        radius: 14,
      ),
      child: Container(
        // Inner padding slightly inset so the dash sits on the outer edge
        decoration: BoxDecoration(
          color: dark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // ── Left: icon + text ────────────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Flag icon — only when location is set
                    if (hasLocation) ...[
                      Icon(Icons.flag_rounded, color: gold, size: 22),
                      const SizedBox(width: 10),
                    ],

                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // "Are you at {location}?" or plain title
                          Text(
                            hasLocation
                                ? offer.locationName
                                : offer.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 4),

                          // Subtitle with **bold** support
                          _RichSubtitle(
                            text: offer.subtitle.isNotEmpty
                                ? offer.subtitle
                                : offer.title,
                            baseStyle: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 13,
                              height: 1.4,
                            ),
                            boldStyle: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // ── Right: Redeem button ──────────────────────────────────
              GestureDetector(
                onTap: onRedeem,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'REDEEM',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'NOW',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ── Subtitle renderer — bolds **text** markdown-style ────────────────────────

class _RichSubtitle extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final TextStyle boldStyle;

  const _RichSubtitle({
    required this.text,
    required this.baseStyle,
    required this.boldStyle,
  });

  @override
  Widget build(BuildContext context) {
    // Parse **bold** markers from the subtitle field
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(
          TextSpan(text: text.substring(last, match.start), style: baseStyle),
        );
      }
      spans.add(TextSpan(text: match.group(1), style: boldStyle));
      last = match.end;
    }

    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
