/// What everybody else picked, and how to say it.
///
/// ── WHY THIS IS WORTH SHOWING AT ALL ────────────────────────────────
///
/// A multiple choice is mostly luck, and "right" or "wrong" on its own
/// says nothing about the person who answered. The crowd is what turns
/// it into a story: being one of the four who spotted it is worth more
/// than being right, and being wrong alongside two thirds of the app is
/// a far better feeling than being wrong on your own.
///
/// So the same facts, read two ways round — rare and right is a boast,
/// common and wrong is company.
class GuessCrowd {
  /// How many people picked each option, in option order.
  final List<int> counts;

  const GuessCrowd(this.counts);

  static const GuessCrowd none = GuessCrowd([]);

  /// Below this, there is no crowd — just a handful of people.
  ///
  /// ── WHY NOT SHOW IT FROM THE FIRST PLAYER ───────────────────────
  ///
  /// Because a percentage of three people is theatre. "67% agreed with
  /// you" out of two others reads as a finding and is noise, and the
  /// first person to play would be told 100% of the app picked what
  /// they picked. A quiet card is better than a confident wrong one.
  ///
  /// Five is low enough that a slow day still shows something and high
  /// enough that no single person is a third of the result.
  static const int minimumPlayers = 5;

  int get total => counts.fold(0, (sum, n) => sum + (n < 0 ? 0 : n));

  /// Whether there are enough people for a share to mean anything.
  bool get hasCrowd => counts.isNotEmpty && total >= minimumPlayers;

  int countOf(int index) =>
      index >= 0 && index < counts.length && counts[index] > 0
      ? counts[index]
      : 0;

  /// 0.0 to 1.0.
  double shareOf(int index) {
    final all = total;

    return all == 0 ? 0 : countOf(index) / all;
  }

  /// "37%", or "<1%" for somebody who is there but rounds away.
  ///
  /// A lone picker among four hundred is the most interesting answer on
  /// the card, and rounding them to "0%" says they do not exist.
  String percentOf(int index) {
    if (countOf(index) == 0) return '0%';

    final percent = (shareOf(index) * 100).round();

    return percent < 1 ? '<1%' : '$percent%';
  }

  /// "41% got it", or null.
  ///
  /// For a list of old games, where the interesting number is not what
  /// anybody picked but how hard the car turned out to be. Null for a
  /// game with no breakdown and for a crowd too small to describe, so
  /// the row shows nothing rather than a shrug.
  String? solvedLabel(int? answerIndex) {
    if (answerIndex == null || !hasCrowd) return null;

    return '${percentOf(answerIndex)} got it';
  }

  /// The line under the result, or null when there is nothing to say.
  ///
  /// Null for somebody who did not play, for a game with no breakdown
  /// yet, and for a crowd too small to describe — the caller leaves the
  /// row out rather than printing an empty one.
  ///
  /// ── THE FOUR THINGS IT CAN SAY ──────────────────────────────────
  ///
  ///   right and rare     you saw something most people did not
  ///   right and common   a gentle one, because there is no boast in
  ///                      agreeing with everybody
  ///   wrong and common   the point of the whole feature: most of the
  ///                      app made the same call
  ///   wrong and rare     said plainly. Nobody needs consoling about a
  ///                      car quiz, and a sympathetic line about it
  ///                      would be worse than the number.
  String? noteFor({int? myChoice, bool? correct}) {
    if (myChoice == null || correct == null || !hasCrowd) return null;

    final share = shareOf(myChoice);
    final percent = percentOf(myChoice);

    if (correct) {
      if (share <= 0.25) return 'Only $percent got this one. Nice spot.';
      if (share >= 0.6) return '$percent got this one.';

      return '$percent of players got it right.';
    }

    if (share >= 0.4) return 'You were not alone - $percent said the same.';
    if (share <= 0.1) return 'Only $percent picked that one.';

    return '$percent picked the same.';
  }

  /// The counts a game payload carries, however they are typed.
  ///
  /// PHP hands integers back as JSON numbers normally and as STRINGS
  /// when a column comes straight out of MySQL without a cast, and a
  /// plain cast throws rather than returning null. The breakdown is
  /// decoration on a screen that works without it, so anything
  /// unreadable comes back empty rather than taking the card with it.
  factory GuessCrowd.fromMap(dynamic raw) {
    if (raw is! List) return none;

    return GuessCrowd(
      raw.map((n) {
        if (n is num) return n.toInt();

        return int.tryParse('$n') ?? 0;
      }).toList(),
    );
  }
}
