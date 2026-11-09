/// How long somebody has had a vehicle, in words.
///
/// ── WHY THIS IS SHARED ───────────────────────────────────────────────
///
/// The vehicle card and the vehicle page both drew this, from the same
/// column, with two separate copies of the same regex — and both said
/// "Owned since 2019" whether the car was still in the garage or sold
/// four years ago. Fixing one would have left the other saying the old
/// thing, which is how a card and the page it opens disagree.
class OwnedDates {
  /// Jan, Feb, Mar … Sept … Dec.
  ///
  /// Three letters apart from September, which is the British habit and
  /// the form "Owned Mar 2019 - Sept 2023" was specified in. 'Sep' next
  /// to 'Mar' is not wrong, it is simply not what was asked for.
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec',
  ];

  /// 'Mar 2019', or null when the date is missing or unreadable.
  ///
  /// Falls back to a bare year when there is a four-digit number and
  /// nothing else parseable — some rows predate the date picker and
  /// hold just '2019'. A year on its own is still worth showing.
  static String? monthYear(Object? raw) {
    final text = '${raw ?? ''}'.trim();

    if (text.isEmpty) return null;

    final parsed = DateTime.tryParse(text);

    if (parsed != null) {
      // Guards against a stored 0000-00-00, which MySQL will hand back
      // and DateTime will happily parse into year 0.
      if (parsed.year < 1900) return null;

      return '${_months[parsed.month - 1]} ${parsed.year}';
    }

    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(text)?.group(0);

    return year;
  }

  /// The line under a vehicle's name.
  ///
  /// Past:    'Owned Mar 2019 - Sept 2023'
  /// Current: 'Owned since Mar 2019'
  ///
  /// [primaryCar] is the raw column: 1 current, 0 past, 2 a dream car.
  /// It arrives as a String from JSON and an int from some callers, so
  /// it is compared as text.
  ///
  /// Null when there is nothing worth saying — no start date, or a
  /// dream car, which nobody has owned and so has no dates at all.
  static String? label({
    Object? ownedSince,
    Object? ownedUntil,
    Object? primaryCar,
  }) {
    final flag = '${primaryCar ?? ''}'.trim();

    // A dream car is an aspiration. "Owned since" about one would be
    // putting words in somebody's mouth — the same reason the activity
    // feed words it differently.
    if (flag == '2') return null;

    final from = monthYear(ownedSince);

    if (from == null) return null;

    final isPast = flag == '0';
    final to = monthYear(ownedUntil);

    // Past, and we know when it ended.
    if (isPast && to != null) return 'Owned $from - $to';

    // Past, but no end date recorded. "Owned since" would imply they
    // still have it, so this says what is actually known.
    if (isPast) return 'Owned from $from';

    return 'Owned since $from';
  }
}
