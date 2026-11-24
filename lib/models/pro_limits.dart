/// What a free account may do, and what Pro lifts.
///
/// ── THE RULE, IN ONE SENTENCE ───────────────────────────────────────
///
/// Nothing is ever taken away; the cap applies to ADDING.
///
/// Somebody who already has forty routes keeps all forty when the limit
/// arrives at three. They simply cannot add a forty-first until they
/// subscribe. That is the whole of the grandfathering decision, and it
/// is the difference between a paywall people shrug at and one that
/// takes away work they already did.
///
/// ── WHY THIS IS A MODEL AND NOT AN `if` IN A SCREEN ─────────────────
///
/// Because the same rule has to hold in several places that cannot see
/// each other: the add button, the save handler behind it, the upsell
/// sheet's wording, and eventually the server. A rule written four
/// times is four rules, and the one that drifts is the one nobody
/// tests.
///
/// It is also arithmetic with an off-by-one in it. "At the limit" and
/// "over the limit" are different states that must both refuse, and
/// "under the limit" must allow — getting that wrong either blocks
/// somebody who has paid nothing wrong, or gives the feature away.
library;

/// A thing a free account has a cap on.
///
/// Add to this as features are gated. The enum is deliberately not
/// open-ended — a feature nobody has decided the number for should not
/// be silently capped at a default.
enum ProFeature {
  /// Driving routes somebody has added.
  routes,

  /// Photographs on one vehicle.
  vehiclePhotos,

  /// Vehicles in a garage.
  vehicles,
}

/// The caps, and the arithmetic that applies them.
abstract final class ProLimits {
  const ProLimits._();

  /// How many a free account may have.
  ///
  /// ── THESE NUMBERS ARE PLACEHOLDERS ──────────────────────────────
  ///
  /// They are a product decision and not a technical one. They are
  /// here so the rule can be written and tested before they are
  /// settled, and every one of them should be reviewed before this
  /// ships. A cap set too low turns an existing user into a
  /// grandfathered one overnight, which is a lot of people who can
  /// suddenly no longer add.
  static const Map<ProFeature, int> freeLimit = {
    ProFeature.routes: 3,
    ProFeature.vehiclePhotos: 10,
    ProFeature.vehicles: 2,
  };

  /// Pro has no cap on anything. Stated once, here, rather than as a
  /// large number somewhere that somebody later compares against.
  static const int unlimited = -1;

  /// The cap for this feature at this subscription level.
  static int limitFor(ProFeature feature, {required bool isPro}) =>
      isPro ? unlimited : (freeLimit[feature] ?? unlimited);

  /// Whether one more may be added.
  ///
  /// [owned] is how many they have NOW. A free account at the cap is
  /// refused, and so is one above it — see [isGrandfathered], which is
  /// the only difference between those two states and matters for what
  /// the screen SAYS rather than for what it allows.
  static bool canAdd(
    ProFeature feature, {
    required bool isPro,
    required int owned,
  }) {
    final limit = limitFor(feature, isPro: isPro);

    if (limit == unlimited) return true;

    return owned < limit;
  }

  /// Whether they are over the cap, and keeping what they have.
  ///
  /// This is never a reason to take anything away. It is how the
  /// upsell knows to say "you have 40" rather than "you have reached
  /// the limit of 3", which to somebody with 40 reads as a threat.
  static bool isGrandfathered(
    ProFeature feature, {
    required bool isPro,
    required int owned,
  }) {
    final limit = limitFor(feature, isPro: isPro);

    if (limit == unlimited) return false;

    return owned > limit;
  }

  /// How many more they may add, or null for no cap.
  ///
  /// Never negative: somebody over the cap has nought remaining, not
  /// minus thirty-seven.
  static int? remaining(
    ProFeature feature, {
    required bool isPro,
    required int owned,
  }) {
    final limit = limitFor(feature, isPro: isPro);

    if (limit == unlimited) return null;

    final left = limit - owned;

    return left < 0 ? 0 : left;
  }

  /// What to put at the top of the upsell sheet, or null when there is
  /// nothing to upsell — see ProUpsellSheet, which takes exactly this.
  ///
  /// ── WHY THE WORDING SPLITS ──────────────────────────────────────
  ///
  /// Somebody at the cap is being told a rule. Somebody over it is
  /// being reassured — they have more than the rule allows, nothing is
  /// going anywhere, and the only thing they cannot do is add. Those
  /// are different sentences and saying the first to the second is how
  /// a grandfathering promise stops sounding like one.
  static String? reasonToUpsell(
    ProFeature feature, {
    required bool isPro,
    required int owned,
  }) {
    if (canAdd(feature, isPro: isPro, owned: owned)) return null;

    final noun = _noun(feature, owned);

    if (isGrandfathered(feature, isPro: isPro, owned: owned)) {
      return 'Keep your $owned $noun, and add more with Pro';
    }

    return 'Add more than ${limitFor(feature, isPro: isPro)} $noun';
  }

  static String _noun(ProFeature feature, int count) => switch (feature) {
    ProFeature.routes => count == 1 ? 'route' : 'routes',
    ProFeature.vehiclePhotos => count == 1 ? 'photo' : 'photos',
    ProFeature.vehicles => count == 1 ? 'vehicle' : 'vehicles',
  };
}
