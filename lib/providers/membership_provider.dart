import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/models/subscription_plan.dart';
import 'package:flutter/foundation.dart';

/// What tier the signed-in person is on, for everything that draws it.
///
/// ── THREE THINGS CAN HAVE AN OPINION ────────────────────────────────
///
/// And they do not all deserve the same weight, so they are kept apart
/// rather than written over each other:
///
///   * [_demo]   - the debug switch. Wins, because its entire job is to
///                 let somebody look at a state they are not in.
///   * [_server] - the answer the SERVER gave, from a receipt it
///                 validated with Apple or Google. Authoritative when
///                 it exists. Today it never does: there is no table
///                 and no endpoint yet.
///   * [_store]  - what StoreKit or Play told THIS DEVICE. Provisional.
///
/// [tier] is the first of those that has anything to say.
///
/// ── WHY THE STORE IS ALLOWED TO COUNT AT ALL ────────────────────────
///
/// It was not, and the result was the bug this fixes: you could buy a
/// subscription, watch the purchase succeed, and the app would still
/// say Free - because the only thing that ever set this was the demo
/// screen.
///
/// The store's word is good enough for the thing it is used for today.
/// Nothing paid is actually gated yet: the one behaviour that keys off
/// a tier is whether adverts show. A device that lies about its
/// purchases gets an ad-free feed, and that is the whole of the loss.
///
/// ── AND WHY IT STOPS COUNTING THE DAY THE SERVER SPEAKS ─────────────
///
/// A rooted phone will lie, and the moment a benefit is worth money -
/// an event allocation, a discount code - device-reported membership
/// is a hole. So [_server] sits in front of [_store] and takes over
/// the instant it is non-null, with no other code needing to change.
///
/// Note the ordering that implies: when the API lands, the purchase
/// must be reported to the server as part of buying, not after. If the
/// server answers "not a member" about a purchase it has not been told
/// about yet, that answer wins and the membership flickers off. See
/// docs/pro-membership-design.md §2.
class MembershipProvider extends ChangeNotifier {
  /// The debug override. Null means "not overridden".
  MembershipTier? _demo;

  /// What the server said. Null means the server has not said anything,
  /// which today is always.
  MembershipTier? _server;

  /// What this device's store reports. Not trusted for anything that
  /// costs real money.
  MembershipTier _store = MembershipTier.none;

  /// Not a member until something says otherwise.
  ///
  /// The safe default in both directions: a signed-out person is not a
  /// member, and a failed status read shows the free experience rather
  /// than silently giving the paid one away.
  MembershipTier get tier => _demo ?? _server ?? _store;

  bool get isMember => tier.isMember;

  /// Whether this person satisfies a gate at [required].
  ///
  /// The one place that question is answered, so a feature gate cannot
  /// invent its own comparison. SuperCharged satisfies a Plus gate;
  /// Plus does not satisfy a SuperCharged one.
  bool has(MembershipTier required) => tier.atLeast(required);

  /// Where the tier came from, for the demo screen to display.
  String get source {
    if (_demo != null) return 'demo override';
    if (_server != null) return 'server';
    if (_store.isMember) return 'this device\'s store';

    return 'nothing - not a member';
  }

  /// The server's answer, from a validated receipt.
  ///
  /// Called from the user payload on sign-in and refresh, once that
  /// payload carries a tier. Outranks the store.
  void set(MembershipTier tier) => _change(() => _server = tier);

  /// What the store told this device, as it changes.
  ///
  /// Fed by [MembershipSync] at launch and by every purchase after it.
  void applyStoreStatus(SubscriptionStatus status) => _change(() {
    // Active but on a product this build cannot name grants nothing.
    // Same rule as MembershipTier.forProduct: when in doubt the answer
    // is no, because the accident is always upward.
    _store = status.active
        ? (status.plan?.tier ?? MembershipTier.none)
        : MembershipTier.none;
  });

  /// Back to nothing. Called on sign-out, where leaving the last
  /// account's tier behind would show the next person a badge they
  /// have not got.
  ///
  /// Clears all three, including the store's view: the subscription
  /// belongs to the Apple or Google account, not to the DriveLife one,
  /// so the next person to sign in on this handset must not inherit it.
  void clear() => _change(() {
    _demo = null;
    _server = null;
    _store = MembershipTier.none;
  });

  /// The demo switch, and only that.
  ///
  /// Named so it reads as debug code at the call site, and asserts
  /// rather than quietly working if it ever reaches a release build -
  /// a release path that can set its own tier is a free membership.
  void debugSetTier(MembershipTier tier) {
    assert(
      !kReleaseMode,
      'MembershipProvider.debugSetTier must never run in release.',
    );

    _change(() => _demo = tier);
  }

  /// Drops the demo override, so the real answer shows again.
  ///
  /// Without this there is no way back from a demo to the live state
  /// short of restarting the app, which makes "did my purchase
  /// actually register" impossible to check after demoing anything.
  void debugUseLive() {
    assert(
      !kReleaseMode,
      'MembershipProvider.debugUseLive must never run in release.',
    );

    _change(() => _demo = null);
  }

  /// Applies a change and notifies only if the ANSWER moved.
  ///
  /// Not whether a slot moved. The server confirming what the store
  /// already said is not a change anybody should rebuild for.
  void _change(void Function() apply) {
    final before = tier;

    apply();

    if (tier != before) notifyListeners();
  }
}
