import 'package:drivelife/models/membership_benefits.dart';
import 'package:drivelife/models/membership_tier.dart';
import 'package:flutter/material.dart';

/// The membership copy and the advert switch, as the server sends them.
///
/// ── WHY THESE TWO THINGS TRAVEL TOGETHER ────────────────────────────
///
/// Because they change for the same reason and at the same moment.
/// Turning adverts on is part of launching the membership, and the
/// benefit list is what the membership IS — both have to be editable
/// without a build, or the first wording change costs a week in review.
///
/// ── AND WHY EVERY FIELD FALLS BACK ──────────────────────────────────
///
/// A paywall with no benefits on it is worse than one showing copy a
/// day out of date, and an app that cannot reach the server is not an
/// app that should stop selling. So nothing here is required: every
/// missing, malformed or unreachable value resolves to the version
/// compiled into the build.
///
/// That also means a server sending nonsense degrades to the last good
/// build rather than to a blank screen.
class MembershipConfig {
  /// Bumped by whoever edits the config. Only used for logging and for
  /// telling a cached copy apart from a fetched one.
  final int version;

  final AdConfig ads;

  /// Per tier. A tier the server does not mention keeps its bundled
  /// copy rather than losing its benefits.
  final Map<MembershipTier, TierCopy> tiers;

  const MembershipConfig({
    this.version = 0,
    this.ads = const AdConfig(),
    this.tiers = const {},
  });

  /// What ships in the binary, and what every failure falls back to.
  ///
  /// Taken from MembershipBenefits, which stays the single written
  /// source of the copy. The server overrides it; it is never deleted.
  static MembershipConfig get bundled => MembershipConfig(
    tiers: {
      for (final tier in [MembershipTier.plus, MembershipTier.supercharged])
        tier: TierCopy(
          tagline: MembershipBenefits.taglineFor(tier),
          benefits: MembershipBenefits.forTier(tier),
        ),
    },
  );

  String taglineFor(MembershipTier tier) =>
      tiers[tier]?.tagline ?? MembershipBenefits.taglineFor(tier);

  List<MembershipBenefit> benefitsFor(MembershipTier tier) =>
      tiers[tier]?.benefits ?? MembershipBenefits.forTier(tier);

  /// Reads a payload, keeping the bundled copy for anything it cannot
  /// use.
  factory MembershipConfig.fromMap(Map<String, dynamic> map) {
    final fallback = MembershipConfig.bundled;

    final rawTiers = map['tiers'];
    final tiers = <MembershipTier, TierCopy>{...fallback.tiers};

    if (rawTiers is Map) {
      for (final tier in MembershipTier.values) {
        final raw = rawTiers[tier.name];

        if (raw is! Map) continue;

        final copy = TierCopy.fromMap(
          Map<String, dynamic>.from(raw),
          fallback: fallback.tiers[tier],
        );

        // A tier that came back with nothing usable keeps what it had.
        // An empty benefits list is almost always a mistake at the
        // other end, and showing it is showing a paywall that sells
        // nothing.
        if (copy != null) tiers[tier] = copy;
      }
    }

    return MembershipConfig(
      version: _int(map['version']),
      ads: map['ads'] is Map
          ? AdConfig.fromMap(Map<String, dynamic>.from(map['ads'] as Map))
          : const AdConfig(),
      tiers: tiers,
    );
  }

  Map<String, dynamic> toMap() => {
    'version': version,
    'ads': ads.toMap(),
    'tiers': {
      for (final entry in tiers.entries) entry.key.name: entry.value.toMap(),
    },
  };

  static int _int(dynamic v) {
    if (v is num) return v.toInt();

    return int.tryParse('$v') ?? 0;
  }
}

/// Whether adverts run, and how thickly.
class AdConfig {
  /// ── OFF BY DEFAULT, AND THAT IS DELIBERATE ──────────────────────
  ///
  /// A build shipped before the membership launches must not show
  /// adverts, and a build that cannot reach the config must not
  /// either. Both are the same state, and both resolve to this.
  ///
  /// The cost of being wrong in this direction is some lost revenue
  /// for as long as the server is unreachable. The cost of the other
  /// direction is adverts appearing when somebody deliberately turned
  /// them off — including, eventually, to a member whose status failed
  /// to load. Off is the side to fail on.
  final bool enabled;

  /// Posts before the first advert, and between them after that.
  /// Remote so the density can be tuned without a build — the number
  /// that is right is the one measured, not the one guessed.
  final int firstAfter;
  final int every;

  const AdConfig({
    this.enabled = false,
    this.firstAfter = 4,
    this.every = 6,
  });

  factory AdConfig.fromMap(Map<String, dynamic> map) {
    const fallback = AdConfig();

    // Clamped, not trusted. A zero would put an advert in every slot
    // and a negative would break the arithmetic in FeedAdSlots - and
    // this value arrives from outside the app.
    int at(String key, int fallbackValue) {
      final raw = map[key];
      final value = raw is num ? raw.toInt() : int.tryParse('$raw');

      if (value == null || value < 1) return fallbackValue;

      return value > 50 ? 50 : value;
    }

    return AdConfig(
      // Anything that is not explicitly true is false. A missing key,
      // a null, a string the server meant as a flag - all of them
      // leave adverts off, which is the direction above.
      enabled: map['enabled'] == true || map['enabled'] == 1 ||
          map['enabled'] == '1' || map['enabled'] == 'true',
      firstAfter: at('first_after', fallback.firstAfter),
      every: at('every', fallback.every),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'first_after': firstAfter,
    'every': every,
  };
}

/// One tier's words.
class TierCopy {
  final String tagline;
  final List<MembershipBenefit> benefits;

  const TierCopy({required this.tagline, required this.benefits});

  /// Null when the payload has nothing usable in it, so the caller
  /// keeps what it had.
  static TierCopy? fromMap(
    Map<String, dynamic> map, {
    TierCopy? fallback,
  }) {
    final raw = map['benefits'];
    final benefits = <MembershipBenefit>[];

    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;

        final title = '${item['title'] ?? ''}'.trim();

        // A benefit with no title is a bullet point with nothing on
        // it. Dropped rather than drawn blank.
        if (title.isEmpty) continue;

        benefits.add(
          MembershipBenefit(
            icon: benefitIcon('${item['icon'] ?? ''}'),
            title: title,
            detail: '${item['detail'] ?? ''}'.trim(),
          ),
        );
      }
    }

    final tagline = '${map['tagline'] ?? ''}'.trim();

    if (benefits.isEmpty) {
      // Keep the bundled benefits, but take a new tagline if there is
      // one - the two are separately useful.
      if (fallback == null) return null;

      return TierCopy(
        tagline: tagline.isEmpty ? fallback.tagline : tagline,
        benefits: fallback.benefits,
      );
    }

    return TierCopy(
      tagline: tagline.isEmpty ? (fallback?.tagline ?? '') : tagline,
      benefits: benefits,
    );
  }

  Map<String, dynamic> toMap() => {
    'tagline': tagline,
    'benefits': [
      for (final b in benefits)
        {
          'icon': benefitIconName(b.icon),
          'title': b.title,
          'detail': b.detail,
        },
    ],
  };
}

/// ── WHY THE SERVER SENDS A NAME AND NOT AN ICON ─────────────────────
///
/// Because an icon is a code point in a font, and a server free to
/// send any of them is a server that can put anything at all on the
/// paywall. This is a fixed list: a name the app knows resolves to its
/// icon, and anything else resolves to a neutral tick.
///
/// Adding an icon is a build. That is the right trade - the words
/// change often and the pictures almost never.
const Map<String, IconData> _benefitIcons = {
  'block': Icons.block_rounded,
  'offer': Icons.local_offer_rounded,
  'garage': Icons.garage_rounded,
  'clock': Icons.schedule_rounded,
  'ticket': Icons.confirmation_number_rounded,
  'map': Icons.map_rounded,
  'verified': Icons.verified_rounded,
  'speed': Icons.speed_rounded,
  'bolt': Icons.bolt_rounded,
  'star': Icons.star_rounded,
  'route': Icons.route_rounded,
  'photo': Icons.photo_library_rounded,
  'event': Icons.event_rounded,
  'badge': Icons.workspace_premium_rounded,
  'check': Icons.check_circle_rounded,
};

IconData benefitIcon(String name) =>
    _benefitIcons[name.trim().toLowerCase()] ?? Icons.check_circle_rounded;

/// The name for an icon, for writing a config back out.
String benefitIconName(IconData icon) {
  for (final entry in _benefitIcons.entries) {
    if (entry.value == icon) return entry.key;
  }

  return 'check';
}

/// Every name the server may send, for the admin page that edits it.
List<String> get benefitIconNames => _benefitIcons.keys.toList();
