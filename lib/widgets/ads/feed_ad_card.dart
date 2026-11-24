import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// An advert, in the feed, dressed as an advert.
///
/// ── WHY IT LOOKS DIFFERENT FROM A POST ──────────────────────────────
///
/// Because it has to. "Sponsored" is not a courtesy — both stores
/// require advertising to be distinguishable from content, and an
/// advert built to pass for a post is the single fastest way to lose
/// the trust that makes the feed worth advertising in.
///
/// So: the label is above the fold of the card, in the same place
/// every time, and the card carries the advertiser's name rather than
/// a person's. Somebody scrolling should know what they are looking at
/// before they read the headline.
///
/// ── AND WHY IT IS NOT A FULL-BLEED IMAGE ────────────────────────────
///
/// A post is a photograph. An advert that is also a full-width
/// photograph is indistinguishable at a glance however it is labelled,
/// which is the thing above. This is a bordered card inside the feed's
/// padding — visibly an insert rather than a post.
class FeedAdCard extends StatelessWidget {
  final AdCreative ad;

  /// Which slot this is, for impression and tap counting.
  final int slot;

  final AdService service;

  const FeedAdCard({
    super.key,
    required this.ad,
    required this.slot,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return VisibilityDetector(
      // Per slot, so scrolling back past the same advert does not
      // count twice - HouseAds de-duplicates on this key.
      key: Key('feed-ad-$slot'),
      onVisibilityChanged: (info) {
        // Half on screen. A ListView builds rows well outside the
        // viewport, so counting builds as impressions overstates them
        // several times over, and every real network bills on the
        // difference.
        if (info.visibleFraction >= 0.5) service.onImpression(slot);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Material(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(context),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── THE LABEL, FIRST ────────────────────────────
                  //
                  // Above everything, in the same place on every
                  // advert. A "Sponsored" tag underneath the content
                  // is a label somebody reads after they have already
                  // been persuaded.
                  Row(
                    children: [
                      Text(
                        'SPONSORED',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: theme.subtextColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ad.advertiser,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: theme.subtextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (ad.imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          ad.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: theme.dividerColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Text(
                    ad.headline,
                    style: TextStyle(
                      fontSize: 16.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: theme.textColor,
                    ),
                  ),

                  if (ad.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ad.body,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: theme.subtextColor,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        ad.callToAction,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: theme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.primaryColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    service.onTap(slot);

    // In-app first. A house advert for the membership should open the
    // paywall, not a web page about it.
    if (ad.route.isNotEmpty) {
      await Navigator.pushNamed(context, ad.route);

      return;
    }

    if (ad.url.isEmpty) return;

    try {
      await launchUrl(
        Uri.parse(ad.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // An advert that will not open is not worth a message to the
      // person who tapped it.
    }
  }
}
