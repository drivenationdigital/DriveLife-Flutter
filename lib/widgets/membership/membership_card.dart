import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/subscription/subscribe_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The membership row on somebody's own profile.
///
/// ── TWO STATES, BOTH WORTH DRAWING ──────────────────────────────────
///
/// A member sees what they are and a way to manage it. Somebody who is
/// not sees the offer, once, in a place they already visit.
///
/// It is the second that earns its place here. A paywall nobody can
/// find sells nothing, and the profile is the one screen in the app
/// where people look at their own standing — which is exactly the
/// frame of mind a membership is bought in.
///
/// ── AND WHY IT IS NOT A BANNER ──────────────────────────────────────
///
/// It sits in the profile's own list, in the profile's own card style,
/// and does not float, animate, pulse or follow anybody down the page.
/// A membership prompt that behaves like an advert gets read as one,
/// and the people most likely to pay are the ones most annoyed by it.
class MembershipCard extends StatelessWidget {
  /// Shown on your own profile only. Somebody else's membership is
  /// theirs to see, not to be sold against.
  const MembershipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final tier = context.watch<MembershipProvider>().tier;

    final member = tier.isMember;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SubscribeScreen()),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              // A gold edge for a member, nothing for everybody else.
              // The card that says "you have this" may look different
              // from the one that says "you could".
              border: member
                  ? Border.all(color: tier.colour, width: 1.5)
                  : Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  size: 26,
                  color: member ? tier.colour : theme.primaryColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member
                            ? 'DriveLife ${tier.label}'
                            : 'Become a member',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member
                            ? 'Manage your membership'
                            : 'A badge, early access to events and '
                                  'partner discounts, from '
                                  '${SubscriptionPlan.monthly.fallbackPrice} '
                                  'a ${SubscriptionPlan.monthly.period}',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: theme.subtextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.subtextColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The settings-style row, for Edit profile.
///
/// Same destination, plainer dress: a list of settings is not a place
/// to sell, so this looks like every other row on that screen and says
/// what tier they are on as its trailing value.
class MembershipSettingsRow extends StatelessWidget {
  const MembershipSettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final tier = context.watch<MembershipProvider>().tier;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubscribeScreen()),
        ),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Membership',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: theme.textColor,
                  ),
                ),
              ),
              Text(
                tier.isMember ? tier.label : 'Free',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tier.isMember ? tier.colour : theme.subtextColor,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.subtextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
