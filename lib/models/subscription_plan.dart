import 'package:drivelife/models/membership_tier.dart';

/// What can be subscribed to, and what it costs.
///
/// ── WHY THE PRICES HERE ARE FALLBACKS ───────────────────────────────
///
/// Both stores require the price shown in the app to be the price the
/// store will actually charge — localised, tax-inclusive, and whatever
/// the store says it is today. A hardcoded "£5" shown to somebody in
/// Dublin being charged €6 is a rejection, not a rounding error.
///
/// So [fallbackPrice] is only for the moment before the store answers,
/// and for a build that cannot reach it at all. Anything the store
/// returns wins — see StorePlan.
enum SubscriptionPlan {
  /// £5 a month.
  monthly(
    productId: 'drivelife_plus_monthly',
    fallbackPrice: '£5',
    period: 'month',
    pence: 500,
    months: 1,
  ),

  /// £45 a year, which is two months free against the monthly.
  yearly(
    productId: 'drivelife_plus_yearly',
    fallbackPrice: '£45',
    period: 'year',
    pence: 4500,
    months: 12,
  ),

  /// The higher tier. Level 1 in the group, against Plus at level 2.
  ///
  /// ── TWO THINGS HERE ARE GUESSES ─────────────────────────────────
  ///
  /// The product id was truncated in App Store Connect
  /// ('drivelife_supercharged_year…') and the price was invented to
  /// make the tier visible. Both must be corrected from the console
  /// before anything is tested, HERE and in ios/DriveLife.storekit —
  /// an id that does not match is a product that never loads, and the
  /// paywall shows no price rather than an error.
  ///
  /// YEARLY ONLY, as created. Worth noticing: somebody on Plus
  /// Monthly who wants this has to jump straight to an annual
  /// commitment, with no monthly step in between.
  superchargedYearly(
    productId: 'drivelife_supercharged_yearly',
    fallbackPrice: '£99.99',
    period: 'year',
    pence: 9999,
    months: 12,
    tier: MembershipTier.supercharged,
  );

  const SubscriptionPlan({
    required this.productId,
    required this.fallbackPrice,
    required this.period,
    required this.pence,
    required this.months,
    this.tier = MembershipTier.plus,
  });

  /// What buying this makes somebody.
  ///
  /// Defaulted to Plus because two of the three are Plus, and a new
  /// plan added without thinking about it belongs to the lower tier —
  /// the direction that gives nothing away by accident.
  final MembershipTier tier;

  /// The id as it is registered in App Store Connect and Play Console.
  ///
  /// The SAME string on both, deliberately. Neither store requires it,
  /// and keeping them apart would mean every lookup in the app had to
  /// know which platform it was on before it could ask a question.
  ///
  /// ── THESE ARE NOW FIXED FOREVER ─────────────────────────────────
  ///
  /// Created in App Store Connect on 24 November 2026, in the
  /// DriveLife Plus subscription group, both at level 2.
  ///
  /// A product id CANNOT be renamed once it exists, and cannot be
  /// reused even after the product is deleted. So these two strings
  /// are now a fact about the world rather than a choice in this file,
  /// and a typo here is a paywall that silently lists nothing.
  final String productId;

  /// Shown only until the store says otherwise. See the note above.
  final String fallbackPrice;

  /// "month" or "year", for "£5 / month".
  final String period;

  /// For working out the saving. Not for display — a price is a
  /// string from the store, not a number we do arithmetic on.
  final int pence;

  final int months;

  /// What a year of this costs, in pence.
  int get yearlyPence => (pence / months * 12).round();

  /// How much cheaper this is than paying monthly, as a percentage.
  ///
  /// Zero for the monthly plan itself, and for anything that is not
  /// actually cheaper — a "save 0%" badge is worse than no badge, and
  /// a negative one is a bug printed on the screen.
  int savingAgainst(SubscriptionPlan monthlyPlan) {
    final full = monthlyPlan.yearlyPence;

    if (full <= 0 || yearlyPence >= full) return 0;

    return ((full - yearlyPence) / full * 100).round();
  }

  /// "Save 25%", or null when there is nothing to shout about.
  String? savingLabel(SubscriptionPlan monthlyPlan) {
    final saving = savingAgainst(monthlyPlan);

    return saving <= 0 ? null : 'Save $saving%';
  }

  /// The plan a product id belongs to, or null.
  ///
  /// Null rather than a guess: a purchase the app cannot name is a
  /// purchase it must not act on, and both stores can hand back an id
  /// from an older build that no longer exists here.
  static SubscriptionPlan? forProduct(String productId) {
    for (final plan in SubscriptionPlan.values) {
      if (plan.productId == productId) return plan;
    }

    return null;
  }

  /// Every id, for the one call that asks the store about all of them.
  static List<String> get allProductIds =>
      SubscriptionPlan.values.map((p) => p.productId).toList();

  /// The monthly plan of a tier, or null when it has none.
  ///
  /// ── WHY THIS IS NOT JUST SubscriptionPlan.monthly ───────────────
  ///
  /// Because that one is PLUS monthly, and a saving is only a saving
  /// against the same tier's own monthly price. Comparing SuperCharged
  /// yearly to the Plus monthly rate says nothing true: the two are
  /// not the same thing bought over different terms, and the answer
  /// would be a percentage somebody could act on.
  ///
  /// SuperCharged has no monthly plan today, so this returns null for
  /// it and the card draws no badge — which is the honest answer, not
  /// a missing feature.
  static SubscriptionPlan? monthlyOf(MembershipTier tier) {
    for (final plan in SubscriptionPlan.values) {
      if (plan.tier == tier && plan.months == 1) return plan;
    }

    return null;
  }

  /// The plans that make somebody [tier], in the order to show them.
  ///
  /// The paywall sells one tier at a time: a screen offering three
  /// prices across two tiers asks somebody to make two decisions at
  /// once, and the usual answer to that is neither.
  static List<SubscriptionPlan> forTier(MembershipTier tier) =>
      SubscriptionPlan.values.where((p) => p.tier == tier).toList();
}

/// A plan as the STORE describes it.
///
/// The price is a string and stays a string: it arrives localised and
/// tax-inclusive ("£4.99", "€5,99", "¥800"), and parsing it into a
/// number to reformat it is how an app ends up showing a price nobody
/// is actually charged.
class StorePlan {
  final SubscriptionPlan plan;

  /// Exactly what the store said to show.
  final String price;

  /// The store's own title and blurb, where it has them. Unused by the
  /// screen today — it writes its own copy — but kept because a store
  /// listing is the one description that is guaranteed to match what
  /// is being sold.
  final String title;
  final String description;

  const StorePlan({
    required this.plan,
    required this.price,
    this.title = '',
    this.description = '',
  });

  /// What to show before the store has answered.
  factory StorePlan.fallback(SubscriptionPlan plan) =>
      StorePlan(plan: plan, price: plan.fallbackPrice);

  /// "£45 / year".
  String get priceLine => '$price / ${plan.period}';
}

/// Whether somebody is subscribed, and to what.
class SubscriptionStatus {
  final bool active;
  final SubscriptionPlan? plan;

  /// When it next renews, where the store says. Null is ordinary —
  /// neither store promises this on every platform or every path.
  final DateTime? renewsAt;

  const SubscriptionStatus({this.active = false, this.plan, this.renewsAt});

  static const SubscriptionStatus none = SubscriptionStatus();
}

/// How a purchase ended.
///
/// ── WHY CANCELLED IS NOT A FAILURE ──────────────────────────────────
///
/// Because somebody deciding not to buy something is not an error, and
/// showing them "Purchase failed" for changing their mind is both
/// wrong and faintly rude. It is the single most common outcome of a
/// paywall and it deserves its own case.
///
/// `pending` is real and easy to forget: Google Play supports deferred
/// payment methods where the purchase completes hours later, at a
/// shop. The app has to say "we will let you know" rather than either
/// granting access or calling it a failure.
enum PurchaseOutcome {
  success,
  cancelled,
  pending,
  alreadyOwned,
  failed;

  /// Whether this outcome means they now have it.
  bool get granted => this == PurchaseOutcome.success ||
      this == PurchaseOutcome.alreadyOwned;

  /// What to say. Null for the two that speak for themselves — the
  /// screen changes instead, and a message on top of that is noise.
  String? get message => switch (this) {
    PurchaseOutcome.success => null,
    PurchaseOutcome.cancelled => null,
    PurchaseOutcome.alreadyOwned => 'You are already subscribed.',
    PurchaseOutcome.pending =>
      'Payment pending. We will unlock it as soon as it clears.',
    PurchaseOutcome.failed => 'That did not go through. Nothing was charged.',
  };
}
