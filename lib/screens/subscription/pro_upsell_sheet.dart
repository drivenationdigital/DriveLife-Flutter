import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/subscription/subscribe_screen.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "This is a Pro thing" — the sheet that introduces the plan.
///
/// ── WHY A SHEET AND NOT THE PAYWALL ─────────────────────────────────
///
/// Because of WHERE it appears. Somebody hits this in the middle of
/// doing something else — adding a route, opening a gallery — and
/// throwing a full-screen paywall over that loses their place and
/// reads as an ambush. A sheet keeps the screen behind it visible,
/// which is the difference between "this costs money" and "give us
/// money".
///
/// It also says less on purpose. One line about what they were trying
/// to do, the price, and a way through to the real paywall for the
/// detail. A sheet that lists every benefit is a paywall with a
/// handle on top.
class ProUpsellSheet extends StatelessWidget {
  /// What they were trying to do: "Add more than three routes".
  ///
  /// Named rather than generic because "Upgrade to Pro" answers a
  /// question nobody asked. The reason they are seeing this is the
  /// most persuasive thing on the sheet and it costs one string.
  final String reason;

  /// Supplied so the demo and the tests can hand in a stand-in. The
  /// paywall this opens makes its own when none is given.
  final SubscriptionService? service;

  const ProUpsellSheet({super.key, required this.reason, this.service});

  /// Shows it, and answers true if they came back subscribed.
  static Future<bool> show(
    BuildContext context, {
    required String reason,
    SubscriptionService? service,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProUpsellSheet(reason: reason, service: service),
    );

    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // The year, because it is the one worth leading with — see the
    // note on _chosen in SubscribeScreen.
    const headline = SubscriptionPlan.yearly;

    return Container(
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Icon(
            Icons.workspace_premium_rounded,
            size: 40,
            color: theme.primaryColor,
          ),
          const SizedBox(height: 14),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: theme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'DriveLife Plus, from ${SubscriptionPlan.monthly.fallbackPrice} '
            'a ${SubscriptionPlan.monthly.period}.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: theme.subtextColor),
          ),
          const SizedBox(height: 4),
          Text(
            // The saving, not the yearly price. "£45" next to "£5"
            // reads as nine times worse at a glance; "Save 25%" reads
            // as the thing it is.
            '${headline.savingLabel(SubscriptionPlan.monthly)} paying yearly',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final bought = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubscribeScreen(service: service),
                  ),
                );

                // The sheet closes with whatever the paywall decided,
                // so a caller can carry on with the thing that was
                // blocked rather than making them start it again.
                if (context.mounted) Navigator.pop(context, bought == true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'See what you get',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Not now',
              style: TextStyle(fontSize: 14, color: theme.subtextColor),
            ),
          ),
        ],
      ),
    );
  }
}
