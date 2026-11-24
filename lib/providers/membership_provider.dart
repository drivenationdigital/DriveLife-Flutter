import 'package:drivelife/models/membership_tier.dart';
import 'package:flutter/foundation.dart';

/// What tier the signed-in person is on, for everything that draws it.
///
/// ── WHAT THIS IS TODAY ──────────────────────────────────────────────
///
/// A holder, and nothing more. Nothing sets it except the demo screen,
/// because the server does not know about memberships yet — there is no
/// table, no receipt validation and no flag on the user payload.
///
/// It exists now so the badge, the profile row and the membership page
/// can be built and LOOKED AT in both states before any of that is
/// written. Flip the tier in the demo screen and every surface in the
/// app changes at once, which is the only way to review this honestly.
///
/// ── AND WHAT IT MUST BECOME ─────────────────────────────────────────
///
/// [tier] has to come from the SERVER, read from a store-validated
/// receipt. Not from a local flag, not from what StoreKit last told
/// this device, and never from anything the app can talk itself into.
///
/// A rooted phone will lie to the app about its purchases. The only
/// answer that can be trusted is one the server checked with Apple or
/// Google — see docs/pro-membership-design.md §2.
///
/// So when the API lands: [set] is called from the user payload on
/// sign-in and refresh, the demo override is removed, and everything
/// drawing from here keeps working unchanged.
class MembershipProvider extends ChangeNotifier {
  MembershipTier _tier = MembershipTier.none;

  /// Not a member until something says otherwise.
  ///
  /// The safe default in both directions: a signed-out person is not a
  /// member, and a failed status read shows the free experience rather
  /// than silently giving the paid one away.
  MembershipTier get tier => _tier;

  bool get isMember => _tier.isMember;

  /// Whether this person satisfies a gate at [required].
  ///
  /// The one place that question is answered, so a feature gate cannot
  /// invent its own comparison. SuperCharged satisfies a Plus gate;
  /// Plus does not satisfy a SuperCharged one.
  bool has(MembershipTier required) => _tier.atLeast(required);

  void set(MembershipTier tier) {
    if (_tier == tier) return;

    _tier = tier;
    notifyListeners();
  }

  /// Back to nothing. Called on sign-out, where leaving the last
  /// account's tier behind would show the next person a badge they
  /// have not got.
  void clear() => set(MembershipTier.none);

  /// The demo switch, and only that.
  ///
  /// Named so it reads as debug code at the call site, and asserts
  /// rather than quietly working if it ever reaches a release build —
  /// a release path that can set its own tier is a free membership.
  void debugSetTier(MembershipTier tier) {
    assert(
      !kReleaseMode,
      'MembershipProvider.debugSetTier must never run in release.',
    );

    set(tier);
  }
}
