import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The pill beside somebody's name that says they pay for this.
///
/// ── WHY A BADGE IS THE BENEFIT, NOT DECORATION ──────────────────────
///
/// It is one of the three things being sold, and it is the only one a
/// member sees every day. Early access happens a few times a year and
/// a discount happens when they remember to look — the badge is on
/// their own profile every time they open it, which is what makes the
/// other two feel like part of something rather than a coupon.
///
/// So it has to be visible where profiles are: their own, the one
/// other people see, and ideally wherever a name appears beside a
/// post. Start with profiles.
class PlusBadge extends StatelessWidget {
  /// Draw this tier. Null reads the signed-in person's own from
  /// [MembershipProvider] — which is right on your own profile and
  /// WRONG on anybody else's.
  ///
  /// Somebody else's tier has to come from their profile payload, and
  /// the server does not send it yet. Passing it explicitly is how
  /// that stays a deliberate decision rather than every badge in the
  /// app quietly showing the viewer's own membership.
  final MembershipTier? tier;

  /// Smaller, for a row rather than a header.
  final bool compact;

  const PlusBadge({super.key, this.tier, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final shown = tier ?? context.watch<MembershipProvider>().tier;

    // Nothing at all for a free account. A grey "FREE" pill is not a
    // badge, it is a nag.
    if (!shown.isMember) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: shown.colour,
        borderRadius: BorderRadius.circular(compact ? 5 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_rounded,
            size: compact ? 10 : 12,
            color: Colors.white,
          ),
          SizedBox(width: compact ? 2 : 3),
          Text(
            shown.badge,
            style: TextStyle(
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// A verified-style tick on its own, for places with no room for a
/// word.
///
/// Deliberately a DIFFERENT shape from the blue verification tick the
/// app already draws. Paying for a membership and being a verified
/// account are two different claims, and one standing in for the other
/// is a claim nobody made.
class PlusTick extends StatelessWidget {
  final MembershipTier? tier;
  final double size;

  const PlusTick({super.key, this.tier, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final shown = tier ?? context.watch<MembershipProvider>().tier;

    if (!shown.isMember) return const SizedBox.shrink();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: shown.colour, shape: BoxShape.circle),
      child: Icon(
        Icons.check_rounded,
        size: size * 0.7,
        color: Colors.white,
      ),
    );
  }
}
