import 'package:drivelife/models/membership_tier.dart';
import 'package:flutter/material.dart';

/// One thing a membership gets you.
class MembershipBenefit {
  final IconData icon;

  /// "Partner discounts". The bold half.
  final String title;

  /// "Offers from our automotive and travel partners." The rest.
  ///
  /// Empty for a benefit that needs no explaining - the ad-free one
  /// says everything in its title, and a second line repeating it is
  /// padding that makes the real explanations look less necessary.
  final String detail;

  const MembershipBenefit({
    required this.icon,
    required this.title,
    this.detail = '',
  });
}

/// What each tier is sold as.
///
/// ── WHY THE LISTS ARE WRITTEN OUT TWICE ─────────────────────────────
///
/// Three benefits are identical across the tiers and four are not: the
/// SuperCharged versions of discounts and booking are deliberately
/// WORDED stronger ("biggest", "first access", "before anyone else"),
/// and SuperCharged has one Plus does not have at all.
///
/// A shared list with per-tier overrides would hide which is which,
/// and the difference between the two tiers is the entire thing
/// somebody is choosing between. Written out, the two lists can be read
/// side by side by anybody editing them - including against the store
/// listings, which they must match word for word.
abstract final class MembershipBenefits {
  const MembershipBenefits._();

  /// The line under the tier's name.
  static String taglineFor(MembershipTier tier) => switch (tier) {
    MembershipTier.plus =>
      'Member perks, priority booking and members-only meets',
    MembershipTier.supercharged =>
      'The full DriveLife experience, on and off the road',
    MembershipTier.none => '',
  };

  static List<MembershipBenefit> forTier(MembershipTier tier) =>
      switch (tier) {
        MembershipTier.plus => _plus,
        MembershipTier.supercharged => _supercharged,
        MembershipTier.none => const [],
      };

  static const List<MembershipBenefit> _plus = [
    MembershipBenefit(
      icon: Icons.block_rounded,
      title: 'Ad-free app experience',
    ),
    MembershipBenefit(
      icon: Icons.local_offer_rounded,
      title: 'Partner discounts',
      detail: 'Offers from our automotive and travel partners.',
    ),
    MembershipBenefit(
      icon: Icons.garage_rounded,
      title: 'Exclusive static events',
      detail: 'Members-only dealership meets, factory visits and more '
          'across the UK.',
    ),
    MembershipBenefit(
      icon: Icons.schedule_rounded,
      title: 'Priority booking',
      detail: 'Early access to DriveLife Breakfast Runs and BBQs.',
    ),
    MembershipBenefit(
      icon: Icons.confirmation_number_rounded,
      title: 'Event ticket discounts',
      detail: 'Money off events in the UK and beyond.',
    ),
    MembershipBenefit(
      icon: Icons.map_rounded,
      title: 'Discounted tours',
      detail: 'Reduced prices on DriveLife tours across the UK and '
          'Europe.',
    ),
    MembershipBenefit(
      icon: Icons.verified_rounded,
      title: 'Silver verified badge on your profile',
    ),
  ];

  static const List<MembershipBenefit> _supercharged = [
    MembershipBenefit(
      icon: Icons.block_rounded,
      title: 'Ad-free app experience',
    ),
    MembershipBenefit(
      icon: Icons.local_offer_rounded,
      title: 'Partner discounts',
      detail: 'Offers from our automotive and travel partners.',
    ),
    MembershipBenefit(
      icon: Icons.garage_rounded,
      title: 'Exclusive static events',
      detail: 'Members-only dealership meets, factory visits and more '
          'across the UK.',
    ),
    // The one Plus does not have at all, and the reason to go up.
    MembershipBenefit(
      icon: Icons.speed_rounded,
      title: 'Driving events',
      detail: 'Morning drive-outs, all-day driving events and track '
          'days, reserved for SuperCharged members.',
    ),
    MembershipBenefit(
      icon: Icons.bolt_rounded,
      title: 'First access',
      detail: 'Book Breakfast Runs, BBQs and all other events and '
          'tours before anyone else.',
    ),
    MembershipBenefit(
      icon: Icons.confirmation_number_rounded,
      title: 'Biggest event ticket discounts',
      detail: 'Our best prices on events in the UK and beyond.',
    ),
    MembershipBenefit(
      icon: Icons.map_rounded,
      title: 'Biggest tour discounts',
      detail: 'Our best prices on DriveLife tours across the UK and '
          'Europe.',
    ),
    MembershipBenefit(
      icon: Icons.verified_rounded,
      title: 'Gold verified badge on your profile',
    ),
  ];
}
