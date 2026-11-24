import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/membership_config_provider.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/subscription/pro_upsell_sheet.dart';
import 'package:drivelife/screens/subscription/subscribe_screen.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every screen and modal in the subscription flow, in one list.
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────
///
/// Because none of it is reachable yet. The stores have no products,
/// nothing in the app gates on Pro, and so the only way to look at any
/// of this would be to wire a gate somewhere and then unwire it.
///
/// It is also the only practical way to see the states that matter.
/// "Already subscribed", "payment pending" and "a purchase arrived
/// while you were looking at it" are each several minutes of setup
/// against a real store, and each is a different screen.
///
/// ── AND WHY IT IS NOT A PROBLEM THAT IT SHIPS ───────────────────────
///
/// It does not. Its only entry point is behind kDebugMode, and the
/// service behind it refuses to run in a release build at all — see
/// FakeSubscriptions. Worst case it is an unreachable screen in the
/// binary, and the day there is a real store it goes.
class SubscriptionDemoScreen extends StatefulWidget {
  const SubscriptionDemoScreen({super.key});

  @override
  State<SubscriptionDemoScreen> createState() => _SubscriptionDemoState();
}

class _SubscriptionDemoState extends State<SubscriptionDemoScreen> {
  /// ONE service across the whole demo.
  ///
  /// Shared on purpose: buying on the paywall and then opening it
  /// again has to show the subscribed state, which it only can if the
  /// two are talking to the same thing. A fresh one per screen would
  /// make every purchase forget itself the moment it closed.
  final FakeSubscriptions _store = FakeSubscriptions();

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        title: const Text(
          'Subscription demo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _note(
            theme,
            'Nothing here charges anything. There is no store behind '
            'it — every outcome is faked so each screen can be looked '
            'at on demand.',
          ),

          // ── WHAT THE REST OF THE APP SHOWS ──────────────────────
          //
          // The badge beside your name, the card on your profile and
          // the row in Edit profile all read MembershipProvider. Flip
          // the tier here and every one of them changes at once,
          // which is the only honest way to look at this before any
          // of it is wired to a store.
          //
          // The paywall below keeps its own separate state (the fake
          // store), so the two can be driven independently.
          _heading(theme, 'What the app shows'),

          _note(
            theme,
            'Changes the badge on your profile, the membership card, '
            'the Edit profile row - and whether the main feed shows '
            'adverts. Nothing to do with the store.',
          ),

          _note(
            theme,
            'To see the ad-free benefit: set a tier, then open the '
            'feed. Adverts appear after the fourth post and every six '
            'after that, and disappear entirely for a member.',
          ),

          for (final tier in MembershipTier.values)
            _row(
              theme,
              icon: context.watch<MembershipProvider>().tier == tier
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              title: tier == MembershipTier.none
                  ? 'Not a member'
                  : 'DriveLife ${tier.label}',
              detail: tier == MembershipTier.none
                  ? 'No badge, and the card offers the membership'
                  : 'Badge beside your name, and the card manages it',
              onTap: () => context
                  .read<MembershipProvider>()
                  .debugSetTier(tier),
            ),

          // The way back. Without it, demoing a tier makes the real
          // one unreachable until the app is restarted - so "did my
          // purchase actually register" becomes unanswerable the
          // moment anybody touches the switch above.
          _row(
            theme,
            icon: Icons.restart_alt_rounded,
            title: 'Whatever the store says',
            detail:
                'Drops the override. Currently reading from: '
                '${context.watch<MembershipProvider>().source}',
            onTap: () => context.read<MembershipProvider>().debugUseLive(),
          ),

          _heading(theme, 'Adverts'),

          _note(
            theme,
            'The real switch is on the server '
            '(app/v2/membership-config), off until somebody turns it '
            'on. This overrides it locally so the feed can be looked '
            'at either way.',
          ),

          _row(
            theme,
            icon: context.watch<MembershipConfigProvider>().config.ads.enabled
                ? Icons.toggle_on_rounded
                : Icons.toggle_off_rounded,
            title: context.watch<MembershipConfigProvider>().config.ads.enabled
                ? 'Adverts: on'
                : 'Adverts: off',
            detail: 'A member never sees them whatever this says',
            onTap: () {
              final c = context.read<MembershipConfigProvider>();
              c.debugSetAds(enabled: !c.config.ads.enabled);
            },
          ),

          _row(
            theme,
            icon: Icons.cloud_sync_rounded,
            title: 'Copy and switch: '
                '${context.watch<MembershipConfigProvider>().source}',
            detail: 'Where the benefit list on the paywall came from. '
                'Tap to re-fetch from the server',
            onTap: () => context
                .read<MembershipConfigProvider>()
                .refresh(force: true),
          ),

          _heading(theme, 'The screens'),

          _row(
            theme,
            icon: Icons.workspace_premium_rounded,
            title: 'Paywall',
            detail: _store.current.active
                ? 'Currently subscribed, so it shows the member state'
                : 'The offer, with both plans',
            onTap: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => SubscribeScreen(service: _store),
                ),
              );

              if (mounted) setState(() {});
            },
          ),

          _row(
            theme,
            icon: Icons.vertical_align_bottom_rounded,
            title: 'Upsell sheet',
            detail: 'What somebody sees when they hit a Pro feature',
            onTap: () async {
              await ProUpsellSheet.show(
                context,
                reason: 'Add more than three routes',
                service: _store,
              );

              if (mounted) setState(() {});
            },
          ),

          _heading(theme, 'What the store does next'),

          _note(
            theme,
            'Pick one, then buy on the paywall. These are the outcomes '
            'a real store can produce, and each takes a test account '
            'and several minutes to reach for real.',
          ),

          for (final outcome in PurchaseOutcome.values)
            _row(
              theme,
              icon: _store.nextOutcome == outcome
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              title: _outcomeTitle(outcome),
              detail: _outcomeDetail(outcome),
              onTap: () => setState(() => _store.nextOutcome = outcome),
            ),

          _heading(theme, 'The awkward ones'),

          _row(
            theme,
            icon: Icons.cloud_download_outlined,
            title: 'A purchase arrives on its own',
            detail: 'A deferred Play payment clearing, or a buy in '
                'iOS Settings',
            onTap: () {
              _store.arriveFromOutside(SubscriptionPlan.yearly);
              setState(() {});
            },
          ),

          _row(
            theme,
            icon: Icons.restart_alt_rounded,
            title: 'Lapse it',
            detail: 'Back to not subscribed',
            onTap: () {
              _store.lapse();
              setState(() {});
            },
          ),

          _row(
            theme,
            icon: Icons.wifi_off_rounded,
            title: _store.breakPlans
                ? 'Store listing: broken'
                : 'Store listing: working',
            detail: 'A paywall whose prices never arrive falls back '
                'rather than showing nothing',
            onTap: () =>
                setState(() => _store.breakPlans = !_store.breakPlans),
          ),

          _row(
            theme,
            icon: Icons.speed_rounded,
            title: _store.delay == Duration.zero
                ? 'Store speed: instant'
                : 'Store speed: slow',
            detail: 'Slow is the honest one — it is what catches a '
                'button that stays tappable mid-purchase',
            onTap: () => setState(() {
              _store.delay = _store.delay == Duration.zero
                  ? const Duration(milliseconds: 900)
                  : Duration.zero;
            }),
          ),

          const SizedBox(height: 20),

          _note(
            theme,
            _store.current.active
                ? 'State: subscribed to the '
                      '${_store.current.plan?.period ?? 'unknown'} plan.'
                : 'State: not subscribed.',
          ),
        ],
      ),
    );
  }

  static String _outcomeTitle(PurchaseOutcome outcome) => switch (outcome) {
    PurchaseOutcome.success => 'It works',
    PurchaseOutcome.cancelled => 'They back out',
    PurchaseOutcome.pending => 'Payment pending',
    PurchaseOutcome.alreadyOwned => 'Already subscribed',
    PurchaseOutcome.failed => 'It fails',
  };

  static String _outcomeDetail(PurchaseOutcome outcome) => switch (outcome) {
    PurchaseOutcome.success => 'Thank-you dialog, then the member state',
    PurchaseOutcome.cancelled => 'Nothing happens, and nothing is said',
    PurchaseOutcome.pending => 'Clears at a shop hours later. Grants nothing',
    PurchaseOutcome.alreadyOwned => 'Restoring onto a second device',
    PurchaseOutcome.failed => 'Card declined, store unreachable',
  };

  Widget _heading(ThemeProvider theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: theme.subtextColor,
      ),
    ),
  );

  Widget _note(ThemeProvider theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, height: 1.4, color: theme.subtextColor),
    ),
  );

  Widget _row(
    ThemeProvider theme, {
    required IconData icon,
    required String title,
    required String detail,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.primaryColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: theme.textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: theme.subtextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
