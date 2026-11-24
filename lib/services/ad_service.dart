import 'package:drivelife/models/membership_tier.dart';
import 'package:flutter/foundation.dart';

/// One advert, whoever supplied it.
///
/// Deliberately not a network's own type. An AdMob native ad, a
/// directly-sold partner placement and a house promotion for one of
/// DriveLife's own events are the same shape on screen, and the screen
/// should not know which it is drawing.
class AdCreative {
  /// Who it is for: "Michelin", "Caffeine & Machine".
  final String advertiser;

  final String headline;
  final String body;

  /// What the button says. "Learn more", "Shop now".
  final String callToAction;

  /// Where it goes. Empty for a house advert that opens something
  /// in-app instead — see [route].
  final String url;

  /// An in-app destination, for house adverts. Empty for an external
  /// one.
  final String route;

  /// A picture, or empty for a text-only placement.
  final String imageUrl;

  /// The advertiser's mark, shown small beside their name.
  final String logoUrl;

  /// True for DriveLife promoting its own things.
  ///
  /// It still says "Sponsored". A house promotion dressed as editorial
  /// is the kind of thing that gets an app pulled, and the rule is the
  /// same whoever paid: if it sits in the feed and is not what the
  /// feed is for, it is labelled.
  final bool house;

  const AdCreative({
    required this.advertiser,
    required this.headline,
    this.body = '',
    this.callToAction = 'Learn more',
    this.url = '',
    this.route = '',
    this.imageUrl = '',
    this.logoUrl = '',
    this.house = false,
  });
}

/// Where adverts come from.
///
/// ── WHY AN INTERFACE, AGAIN ─────────────────────────────────────────
///
/// Same reason as SubscriptionService. The network is not chosen yet:
/// AdMob pays per impression and needs an account, an app id and a
/// review; directly-sold partner placements pay far better per slot
/// for a community this size and need an endpoint rather than an SDK.
/// That is a commercial decision, not a technical one.
///
/// So the feed is written against this, [HouseAds] stands in, and
/// whichever is chosen drops in underneath without the feed changing.
/// It also means the slot, the spacing, the label and the member gate
/// can all be built and reviewed before a penny is spent.
abstract class AdService {
  /// The advert for slot [index] in the current feed, or null for no
  /// advert at all — which the feed draws as nothing, not as a gap.
  AdCreative? adAt(int index);

  /// Told that an advert was actually SEEN, not merely built.
  ///
  /// A ListView builds rows well outside the viewport, so counting
  /// builds as impressions overstates them several times over. Every
  /// real network bills on this distinction and so should we.
  void onImpression(int index);

  void onTap(int index);
}

/// DriveLife's own adverts, and nobody else's.
///
/// ── WHAT THIS IS FOR ────────────────────────────────────────────────
///
/// Seeing the slot in place before any network exists. Everything
/// about the placement — where it sits, how often, what it says, how a
/// member stops seeing it — can be reviewed from this, and none of it
/// changes when a real network arrives.
///
/// It is also not wasted work. A house advert slot is worth having
/// permanently: it is where DriveLife promotes its own tours, events
/// and the membership itself, and it fills the slot when no paid
/// advert is available rather than leaving a hole.
class HouseAds implements AdService {
  /// Counted so the demo can show that impressions are tracked on
  /// VIEW rather than on build.
  final List<int> impressions = [];
  final List<int> taps = [];

  @override
  AdCreative? adAt(int index) {
    if (_creatives.isEmpty) return null;

    // Cycles. Two adverts on one screen are never the same one, and
    // the list repeating down a long feed is honest about there being
    // only a few.
    return _creatives[index % _creatives.length];
  }

  @override
  void onImpression(int index) {
    if (!impressions.contains(index)) impressions.add(index);

    debugPrint('[Ads] impression on slot $index');
  }

  @override
  void onTap(int index) {
    taps.add(index);

    debugPrint('[Ads] tap on slot $index');
  }

  static const List<AdCreative> _creatives = [
    AdCreative(
      advertiser: 'DriveLife',
      headline: 'Go ad-free with DriveLife Plus',
      body: 'Member perks, priority booking and members-only meets, '
          'from £5 a month.',
      callToAction: 'See what you get',
      route: '/subscribe',
      house: true,
    ),
    AdCreative(
      advertiser: 'DriveLife Tours',
      headline: 'The Alps, next spring',
      body: 'Seven days, eleven passes. Members get a discount.',
      callToAction: 'Find out more',
      route: '/subscribe',
      house: true,
    ),
    AdCreative(
      advertiser: 'A partner brand',
      headline: 'This is where a partner advert goes',
      body: 'Supplied by whichever network or direct deal is chosen. '
          'The slot does not care which.',
      callToAction: 'Learn more',
      house: false,
    ),
  ];
}

/// Whether this person should see adverts at all.
///
/// One function, so the ad-free benefit cannot be half-implemented.
/// Every surface that might show an advert asks this and nothing else
/// — a second opinion somewhere is a screen that keeps showing them to
/// somebody who has paid not to see them.
bool adsAllowedFor(MembershipTier tier) => !tier.isMember;
