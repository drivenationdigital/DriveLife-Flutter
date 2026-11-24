import 'dart:async';

import 'package:drivelife/models/membership_benefits.dart';
import 'package:drivelife/providers/membership_config_provider.dart';
import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/membership_sync.dart';
import 'package:drivelife/services/store_subscriptions.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// The paywall.
///
/// ── WHAT IS REAL HERE AND WHAT IS NOT ───────────────────────────────
///
/// The screen is real, and so is the store it talks to: the default
/// behind [SubscriptionService] is [StoreSubscriptions], which drives
/// the platform's own purchase flow. [FakeSubscriptions] is still here
/// but only reachable by being handed in, by the demo screen and the
/// tests.
///
/// What is NOT real yet is the entitlement. The store tells this device
/// what it believes; nothing has verified that with Apple or Google.
/// [MembershipProvider] therefore still takes its tier from elsewhere —
/// see docs/pro-membership-design.md §2.
///
/// That is the point of building it this way round. Every outcome a
/// real store can produce — cancelled, pending, already owned, failed
/// — can be driven here in one tap, on a simulator, before any money
/// exists. Finding out that "pending" shows a success screen is much
/// cheaper now than after the first real deferred payment.
class SubscribeScreen extends StatefulWidget {
  /// Supplied by the caller so a test, or the demo switch below, can
  /// hand in something other than the real store.
  final SubscriptionService? service;

  const SubscribeScreen({super.key, this.service});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen>
    with WidgetsBindingObserver {
  late final SubscriptionService _store;

  /// Whether this screen made the service and therefore owns it.
  ///
  /// A service handed in belongs to whoever handed it in, and
  /// disposing somebody else's stream controller closes it for every
  /// other listener.

  List<StorePlan> _plans = const [];
  bool _loading = true;
  bool _busy = false;

  /// Which one is selected. The year, because it is the better deal
  /// and the one worth defaulting somebody into — a monthly default
  /// quietly costs them a third more.
  SubscriptionPlan _chosen = SubscriptionPlan.yearly;

  /// Which tier the screen is showing.
  ///
  /// ── WHY ONE TIER AT A TIME ──────────────────────────────────────
  ///
  /// Seven benefits each, three prices, two tiers. All of it at once
  /// asks somebody to decide which tier AND which term in the same
  /// glance, and the usual answer to two decisions at once is
  /// neither.
  ///
  /// Plus first, because it is the cheaper way in and the one most
  /// people will take. SuperCharged is one tap away and says what it
  /// adds — which is a better pitch than being shouted at by both.
  MembershipTier _tier = MembershipTier.plus;

  SubscriptionStatus _status = SubscriptionStatus.none;
  StreamSubscription<SubscriptionStatus>? _watch;

  /// The app's membership sync, when this screen is using the real
  /// store. Null when a service was handed in by the demo or a test.
  MembershipSync? _sync;

  @override
  void initState() {
    super.initState();

    // The app's own store by default, borrowed from MembershipSync.
    //
    // Borrowed rather than built, because two services on the same
    // purchase feed both call completePurchase on the same
    // transaction, and the second call fails. Borrowed also means a
    // purchase made here reaches MembershipProvider through the same
    // listener as one made anywhere else, instead of this screen
    // being the only place that knows.
    //
    // FakeSubscriptions is reachable only by being handed in - the
    // demo screen and the tests do that - because a paywall that
    // defaults to the stand-in is a paywall that grants memberships
    // for free the day nobody remembers to pass one.
    _sync = widget.service == null ? context.read<MembershipSync>() : null;
    _store = widget.service ?? _sync!.store;

    _status = _store.current;

    WidgetsBinding.instance.addObserver(this);

    // A purchase can complete while this screen is not asking: a
    // deferred Play payment clears hours later, and a subscription
    // bought in iOS Settings arrives unprompted.
    _watch = _store.changes.listen((status) {
      if (mounted) setState(() => _status = status);
    });

    _load();
  }

  /// Re-reads the store when the app comes back to the foreground.
  ///
  /// A subscription can be cancelled in iOS Settings or the Play
  /// Store, with this screen sitting open behind it the whole time.
  /// Nothing arrives on the purchase feed for that - it is not a
  /// purchase - so without this the screen keeps showing what was
  /// true when it opened.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state != AppLifecycleState.resumed) return;
    if (!_status.active) return;

    unawaited(_refreshAfterManaging());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();

    // Nothing to dispose: the store is MembershipSync's, and one
    // handed in belongs to whoever handed it in. Closing a shared
    // store here would kill the purchase feed for the whole app the
    // first time somebody backed out of the paywall.

    super.dispose();
  }

  Future<void> _load() async {
    final plans = await _store.plans();

    if (!mounted) return;

    setState(() {
      // Falls back rather than showing nothing. A paywall with no
      // prices on it is a dead end, and the fallbacks are right often
      // enough to beat blank — see SubscriptionPlan.fallbackPrice for
      // why they are not to be trusted further than that.
      _plans = plans.isNotEmpty
          ? plans
          : SubscriptionPlan.values.map(StorePlan.fallback).toList();
      _loading = false;
    });
  }

  StorePlan _planFor(SubscriptionPlan plan) => _plans.firstWhere(
    (p) => p.plan == plan,
    orElse: () => StorePlan.fallback(plan),
  );

  /// The plans of the tier on screen, longest term first.
  ///
  /// Yearly before monthly, so the better value is read first and the
  /// saving badge is the first thing the eye lands on.
  List<SubscriptionPlan> get _tierPlans {
    final plans = SubscriptionPlan.forTier(_tier)
      ..sort((a, b) => b.months.compareTo(a.months));

    return plans;
  }

  /// Moves to the other tier, taking the selection with it.
  ///
  /// The selected plan must always belong to the tier on screen -
  /// otherwise the button says "Subscribe for £44.99" while the page
  /// says SuperCharged, and the purchase quietly buys the wrong thing.
  void _showTier(MembershipTier tier) {
    if (_tier == tier) return;

    final plans = SubscriptionPlan.forTier(tier)
      ..sort((a, b) => b.months.compareTo(a.months));

    setState(() {
      _tier = tier;
      _chosen = plans.isEmpty ? _chosen : plans.first;
    });
  }

  Future<void> _buy() async {
    if (_busy) return;

    setState(() => _busy = true);

    final outcome = await _store.buy(_chosen);

    if (!mounted) return;

    setState(() => _busy = false);

    if (outcome.granted) {
      await _thankThem();

      return;
    }

    // Null for the one that speaks for itself: a cancel is somebody
    // changing their mind rather than something going wrong. See
    // PurchaseOutcome.message.
    final message = outcome.message;

    if (message != null) _say(message);
  }

  /// The moment it worked.
  ///
  /// ── WHY A DIALOG AND NOT A SNACKBAR ─────────────────────────────
  ///
  /// Because somebody has just spent money, and a grey bar at the
  /// bottom for four seconds is the same acknowledgement an app gives
  /// for copying a link. This is the one moment in the whole flow
  /// worth stopping for.
  ///
  /// It also pops the screen afterwards, carrying true, so whatever
  /// sent them here — a sheet over a half-finished route — can carry
  /// on rather than making them start again.
  Future<void> _thankThem() async {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: 52,
              color: theme.primaryColor,
            ),
            const SizedBox(height: 14),
            Text(
              'You are in',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: theme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Everything is unlocked. Thank you for keeping the '
              'lights on.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: theme.subtextColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(
              'Get going',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Only when there is something to go back to. Opened as a route
    // of its own — from the demo, or from a menu — there is not, and
    // popping would take the screen under it with them.
    if (Navigator.canPop(context)) Navigator.pop(context, true);
  }

  Future<void> _restore() async {
    if (_busy) return;

    setState(() => _busy = true);

    final status = await _store.restore();

    if (!mounted) return;

    setState(() {
      _status = status;
      _busy = false;
    });

    if (!status.active) _say('Nothing to restore on this account.');
  }

  void _say(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        foregroundColor: theme.textColor,
        title: Text(
          _status.active ? 'Your subscription' : 'DriveLife Plus',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: theme.textColor,
          ),
        ),
        actions: [
          // The demo switch. Never built in release — see
          // FakeSubscriptions, which refuses to run there anyway.
          if (!kReleaseMode && _store is FakeSubscriptions)
            IconButton(
              icon: const Icon(Icons.science_outlined),
              tooltip: 'Demo outcomes',
              onPressed: _openDemoSheet,
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            )
          : _status.active
          ? _subscribed(theme)
          : _offer(theme),
    );
  }

  // ── Already paying ─────────────────────────────────────────────────

  /// ── WHY THERE IS NO CANCEL BUTTON ──────────────────────────────────
  ///
  /// Because neither store allows one. A subscription is cancelled in
  /// the App Store or Play Store account settings, and an app that
  /// offers its own cancel either does nothing or lies. Both stores
  /// require a link to the real place instead.
  /// The line under the heading, which has to carry the state.
  String _subtitle(SubscriptionPlan? plan) {
    if (_status.endingSoon) return 'Cancelled, and still yours for now.';

    if (plan == null) return 'Thank you.';

    return 'Billed every ${plan.period}. Thank you.';
  }

  Widget _subscribed(ThemeProvider theme) {
    final plan = _status.plan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Icon(
          Icons.workspace_premium_rounded,
          size: 56,
          color: (_status.plan?.tier ?? MembershipTier.plus).colour,
        ),
        const SizedBox(height: 16),
        Text(
          _status.endingSoon
              ? '${(_status.plan?.tier ?? MembershipTier.plus).label} '
                    'until it ends'
              : 'You are a '
                    '${(_status.plan?.tier ?? MembershipTier.plus).label} '
                    'member',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: theme.textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _subtitle(plan),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: theme.subtextColor),
        ),
        if (_status.renewsAt != null) ...[
          const SizedBox(height: 4),
          Text(
            // The same date, and the word in front of it is the whole
            // difference between the two states.
            _status.endingSoon
                ? 'You keep everything until '
                      '${_date(_status.renewsAt!)}'
                : _status.willRenew == true
                ? 'Renews ${_date(_status.renewsAt!)}'
                : 'Next due ${_date(_status.renewsAt!)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: theme.subtextColor,
              fontWeight: _status.endingSoon
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ],
        const SizedBox(height: 28),
        for (final benefit in context
            .watch<MembershipConfigProvider>()
            .config
            .benefitsFor(_status.plan?.tier ?? MembershipTier.plus))
          _benefitRow(theme, benefit),
        const SizedBox(height: 24),

        // ── THE BUTTON THAT WAS STALE ─────────────────────────────
        //
        // It said "Manage or cancel" to everybody, including people
        // who had just cancelled. Offering to cancel something
        // already cancelled reads as the cancellation not having
        // worked, and the one thing they might actually want - to
        // come back - was nowhere on the screen.
        //
        // Both states lead to the same sheet, because the store owns
        // this and there is no other way in. What changes is what the
        // screen says it is for.
        if (_status.endingSoon)
          FilledButton(
            onPressed: _openStoreSettings,
            style: FilledButton.styleFrom(
              backgroundColor:
                  (_status.plan?.tier ?? MembershipTier.plus).colour,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Turn renewal back on',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        else
          OutlinedButton(
            onPressed: _openStoreSettings,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.dividerColor),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              // Not "or cancel" when we cannot see whether they
              // already have. "Manage" covers both and claims
              // neither.
              _status.willRenew == true
                  ? 'Manage or cancel'
                  : 'Manage subscription',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.textColor,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          _status.endingSoon
              ? 'Your membership is cancelled and will not renew. You '
                    'keep everything until it ends, and turning '
                    'renewal back on costs nothing extra.'
              : 'Subscriptions are managed by the App Store or Google '
                    'Play, not by DriveLife.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: theme.subtextColor,
          ),
        ),
      ],
    );
  }

  // ── Not paying yet ─────────────────────────────────────────────────

  Widget _offer(ThemeProvider theme) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              _tierSwitch(theme),
              const SizedBox(height: 18),
              Text(
                'DriveLife ${_tier.label}',
                style: TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: theme.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // From the server where there is one, from the build
                // otherwise. Never empty - see MembershipConfig.
                context
                    .watch<MembershipConfigProvider>()
                    .config
                    .taglineFor(_tier),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.3,
                  color: theme.subtextColor,
                ),
              ),
              const SizedBox(height: 20),
              for (final benefit in context
                  .watch<MembershipConfigProvider>()
                  .config
                  .benefitsFor(_tier))
                _benefitRow(theme, benefit),
              const SizedBox(height: 10),
              for (final plan in _tierPlans) ...[
                _planCard(theme, plan),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        _footer(theme),
      ],
    );
  }

  /// Plus or SuperCharged, as two halves of one control.
  ///
  /// A segmented switch rather than two cards: this is a choice
  /// between two things, not two offers competing, and the tier NOT
  /// chosen should be one tap away rather than half the screen.
  Widget _tierSwitch(ThemeProvider theme) {
    const tiers = [MembershipTier.plus, MembershipTier.supercharged];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final tier in tiers)
            Expanded(
              child: GestureDetector(
                onTap: _busy ? null : () => _showTier(tier),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tier == tier ? tier.colour : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    tier.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _tier == tier
                          ? Colors.white
                          : theme.subtextColor,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _benefitRow(ThemeProvider theme, MembershipBenefit benefit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The tier's own colour, so a SuperCharged list reads as
          // gold throughout rather than as the Plus list with a
          // different heading.
          Icon(benefit.icon, size: 22, color: _tier.colour),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  benefit.title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: theme.textColor,
                  ),
                ),
                // Only when there is one. "Ad-free app experience"
                // says everything in its title, and a second line
                // repeating it makes the real explanations look less
                // necessary.
                if (benefit.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    benefit.detail,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      color: theme.subtextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One plan, pickable.
  ///
  /// The price comes from [StorePlan] and is printed exactly as the
  /// store gave it. Both stores require that; see the note on
  /// SubscriptionPlan.
  Widget _planCard(ThemeProvider theme, SubscriptionPlan plan) {
    final store = _planFor(plan);
    final chosen = _chosen == plan;
    // Against this TIER's own monthly, not the Plus one. A saving is
    // only a saving against the same thing bought over a shorter
    // term - see SubscriptionPlan.monthlyOf. Null where the tier has
    // no monthly plan, and then no badge is drawn.
    final monthly = SubscriptionPlan.monthlyOf(plan.tier);
    final saving = monthly == null ? null : plan.savingLabel(monthly);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _chosen = plan),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: chosen ? _tier.colour : theme.dividerColor,
              width: chosen ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                chosen
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: chosen ? _tier.colour : theme.subtextColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.months >= 12 ? 'Yearly' : 'Monthly',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.priceLine,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.subtextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (saving != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _tier.colour.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    saving,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _tier.colour,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The buy button, the restore control and the small print.
  ///
  /// ── WHY THE SMALL PRINT IS NOT OPTIONAL ─────────────────────────
  ///
  /// Both stores require an auto-renewing subscription to state the
  /// length of the term, the price, that it renews automatically, and
  /// to link terms and a privacy policy — on the screen where it is
  /// bought, not two taps away. An app without it is rejected, and the
  /// rejection says nothing useful about which part was missing.
  Widget _footer(ThemeProvider theme) {
    final store = _planFor(_chosen);

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _buy,
              style: ElevatedButton.styleFrom(
                backgroundColor: _tier.colour,
                disabledBackgroundColor: _tier.colour.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Subscribe for ${store.price}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Renews automatically every ${_chosen.period} at '
            '${store.price} until cancelled. Cancel any time in your '
            'App Store or Google Play account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: theme.subtextColor,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Required on iOS: an app selling a subscription without
              // a visible way to restore one is rejected.
              TextButton(
                onPressed: _busy ? null : _restore,
                child: Text(
                  'Restore',
                  style: TextStyle(fontSize: 12.5, color: theme.subtextColor),
                ),
              ),
              Text('·', style: TextStyle(color: theme.subtextColor)),
              TextButton(
                onPressed: () => _openLink('https://www.drivelife.app/terms'),
                child: Text(
                  'Terms',
                  style: TextStyle(fontSize: 12.5, color: theme.subtextColor),
                ),
              ),
              Text('·', style: TextStyle(color: theme.subtextColor)),
              TextButton(
                onPressed: () => _openLink('https://www.drivelife.app/privacy'),
                child: Text(
                  'Privacy',
                  style: TextStyle(fontSize: 12.5, color: theme.subtextColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Odds and ends ──────────────────────────────────────────────────

  Future<void> _openLink(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Subscribe] could not open $url: $e');
    }
  }

  /// The store's own subscription settings.
  ///
  /// Two different places, and neither is ours. iOS has a documented
  /// URL; Android wants the Play subscriptions page, which takes the
  /// package name to land on the right one.
  /// Opens the place a subscription is actually cancelled.
  ///
  /// On iOS this is the NATIVE sheet, not a link to apps.apple.com.
  /// Two reasons, and the second is the one that matters:
  ///
  ///   * It opens in place instead of throwing somebody out of the
  ///     app into Safari and then Settings.
  ///   * The link form cannot be tested. Under a local StoreKit
  ///     configuration there is no App Store account to open, so the
  ///     link goes somewhere real and unrelated, and the cancel path -
  ///     the one path a reviewer always checks - can never be
  ///     exercised before release. `showManageSubscriptions` is
  ///     simulated by Xcode's StoreKit testing, so it can.
  ///
  /// Needs iOS 15 and StoreKit 2. The plugin defaults to StoreKit 2;
  /// if the call fails for any reason the link is still there as a
  /// fallback, because "we could not open it" is not an acceptable
  /// answer to somebody trying to stop paying.
  Future<void> _openStoreSettings() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await InAppPurchaseStoreKitPlatformAddition()
            .showManageSubscriptions();

        // They may have just cancelled. Ask the store again rather
        // than keep drawing a membership that has ended.
        if (mounted) await _refreshAfterManaging();

        return;
      } catch (e) {
        debugPrint('[subscriptions] manage sheet: $e');
      }

      await _openLink('https://apps.apple.com/account/subscriptions');

      return;
    }

    await _openLink('https://play.google.com/store/account/subscriptions');
  }

  /// Re-reads the store after the manage sheet closes.
  ///
  /// A cancellation does not always arrive on the purchase feed, and
  /// an app still showing "you are a member" after somebody has just
  /// cancelled reads as the cancellation not having worked.
  Future<void> _refreshAfterManaging() async {
    final status = await _store.restore();

    if (mounted) setState(() => _status = status);
  }

  static String _date(DateTime when) =>
      '${when.day} ${_months[when.month - 1]} ${when.year}';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Forces each outcome a real store can produce.
  ///
  /// Debug only. Reaching "pending" on a real Play account means a
  /// test card and a wait; reaching "already owned" on StoreKit means
  /// a second sandbox account. Here they are one tap each, which is
  /// the whole reason the screen was built against an interface.
  void _openDemoSheet() {
    final fake = _store;

    if (fake is! FakeSubscriptions) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Demo: what the store does next',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final outcome in PurchaseOutcome.values)
              ListTile(
                dense: true,
                leading: Icon(
                  fake.nextOutcome == outcome
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(outcome.name),
                onTap: () {
                  fake.nextOutcome = outcome;
                  Navigator.pop(sheet);
                  setState(() {});
                },
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('A purchase arrives from outside'),
              subtitle: const Text('A deferred payment clearing'),
              onTap: () {
                fake.arriveFromOutside(_chosen);
                Navigator.pop(sheet);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Lapse the subscription'),
              onTap: () {
                fake.lapse();
                Navigator.pop(sheet);
              },
            ),
          ],
        ),
      ),
    );
  }
}
