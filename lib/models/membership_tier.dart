import 'package:flutter/material.dart';

/// What somebody is, membership-wise.
///
/// ── WHY A TIER AND NOT A BOOLEAN ────────────────────────────────────
///
/// Because there are two paid levels in App Store Connect, not one:
/// Plus at level 2 and SuperCharged at level 1. A boolean `isPro`
/// cannot tell them apart, and every place that draws a badge or opens
/// a gate would end up with its own private idea of which is which.
///
/// Ordered deliberately: a later value outranks an earlier one, which
/// is what [atLeast] compares. Reorder these and every gate in the app
/// changes meaning, so do not.
enum MembershipTier {
  /// Not a member. The default, and what every signed-out or unknown
  /// state resolves to — see MembershipProvider.
  none(label: 'Free', badge: '', colour: Color(0xFF9A9A9A)),

  /// DriveLife Plus. Level 2 in the subscription group.
  ///
  /// SILVER, because the benefit is written as "silver verified badge
  /// on your profile" and the badge has to be the thing that was sold.
  plus(
    label: 'Plus',
    badge: 'PLUS',
    colour: Color(0xFF8E959E),
  ),

  /// DriveLife SuperCharged. Level 1 — the higher of the two.
  ///
  /// GOLD, and specifically the BRAND's gold (PRIMARY_COLOR_CODE),
  /// not a brighter one. The top tier wearing the app's own colour is
  /// the strongest thing a badge can say, and a second gold beside it
  /// would read as a near-miss.
  supercharged(
    label: 'SuperCharged',
    badge: 'SUPERCHARGED',
    colour: Color(0xFFAE9159),
  );

  const MembershipTier({
    required this.label,
    required this.badge,
    required this.colour,
  });

  /// "Plus". What it is called in a sentence.
  final String label;

  /// "PLUS". What goes in the pill beside somebody's name. Empty for
  /// [none], which draws nothing at all rather than a grey "FREE" pill
  /// — a badge saying you have not paid is not a badge.
  final String badge;

  /// The pill's colour.
  ///
  /// Silver for Plus and gold for SuperCharged, because that is how
  /// the two are SOLD — "silver verified badge" and "gold verified
  /// badge" are written benefits, so the colours are a promise rather
  /// than a design choice, and changing them breaks the listing.
  ///
  /// Both are dark enough to carry white text. A literal silver
  /// (#C0C0C0) is not: white on it fails at badge size, which is why
  /// this is a deeper grey that still reads as silver.
  final Color colour;

  bool get isMember => this != MembershipTier.none;

  /// Whether this tier includes everything [other] does.
  ///
  /// SuperCharged satisfies a Plus gate; Plus does not satisfy a
  /// SuperCharged one. Written as an index comparison because the enum
  /// is ordered, which is why the order carries a warning above it.
  bool atLeast(MembershipTier other) => index >= other.index;

  /// The tier a store product belongs to.
  ///
  /// Null for an id this build does not know — an older product, or a
  /// new one shipped to the store before the app caught up. Null is
  /// the only safe answer: granting a tier for an unrecognised
  /// purchase is granting the highest one by accident.
  static MembershipTier? forProduct(String productId) {
    final id = productId.toLowerCase();

    if (id.contains('supercharged')) return MembershipTier.supercharged;
    if (id.contains('plus')) return MembershipTier.plus;

    return null;
  }
}
