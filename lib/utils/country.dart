/// Two-letter country codes, as people read them.
///
/// The app stores ISO 3166-1 alpha-2 on galleries and users, which is the
/// right thing to store and the wrong thing to show: "GB" is a database value,
/// not a place.
library;

/// The flag for a country code.
///
/// Derived rather than looked up: a regional indicator symbol is the letter's
/// position in the alphabet added to U+1F1E6, and two of them side by side are
/// rendered as that country's flag. So every valid code gets a flag without a
/// table to maintain, and an invalid one gets an empty string instead of a
/// wrong picture.
///
/// Some platforms — Windows notably — render the two letters rather than a
/// flag. That is still readable, which is why the name is shown beside it.
String countryFlag(String code) {
  final iso = code.trim().toUpperCase();
  if (iso.length != 2) return '';

  final first = iso.codeUnitAt(0);
  final second = iso.codeUnitAt(1);

  const a = 65; // 'A'
  const z = 90; // 'Z'
  if (first < a || first > z || second < a || second > z) return '';

  const base = 0x1F1E6;
  return String.fromCharCodes([base + first - a, base + second - a]);
}

/// Names for the countries DriveLife actually operates in, plus the ones its
/// members are most likely to be posting from.
///
/// Deliberately not the full ISO list. An unknown code falls back to the code
/// itself, which is honest and short, and the flag beside it usually settles
/// what it is anyway.
const Map<String, String> _names = {
  'GB': 'United Kingdom',
  'IE': 'Ireland',
  'US': 'United States',
  'CA': 'Canada',
  'AU': 'Australia',
  'NZ': 'New Zealand',
  'ZA': 'South Africa',
  'DE': 'Germany',
  'FR': 'France',
  'ES': 'Spain',
  'IT': 'Italy',
  'NL': 'Netherlands',
  'BE': 'Belgium',
  'PT': 'Portugal',
  'PL': 'Poland',
  'SE': 'Sweden',
  'NO': 'Norway',
  'DK': 'Denmark',
  'FI': 'Finland',
  'CH': 'Switzerland',
  'AT': 'Austria',
  'AE': 'United Arab Emirates',
  'JP': 'Japan',
  'SG': 'Singapore',
  'IN': 'India',
};

/// Aliases for names that are not the ones in [_names].
///
/// Google's formatted addresses end with whatever that country is normally
/// called — "UK", not "United Kingdom"; "USA", not "United States" — so the
/// forms it actually emits have to be here or the lookup misses.
const Map<String, String> _aliases = {
  'UK': 'GB',
  'GREAT BRITAIN': 'GB',
  'ENGLAND': 'GB',
  'SCOTLAND': 'GB',
  'WALES': 'GB',
  'NORTHERN IRELAND': 'GB',
  'USA': 'US',
  'UNITED STATES OF AMERICA': 'US',
  'REPUBLIC OF IRELAND': 'IE',
  'UAE': 'AE',
};

/// The country code for a country's name, or null if it is not one we know.
///
/// Used on the tail of a Google place description — "Toronto, ON, Canada" —
/// which is the only place in the app that can name a country outside the two
/// blogs. Null rather than a guess: an unrecognised tail means the server
/// falls back to the member's own blog, which is a worse answer but never a
/// wrong flag.
String? countryCodeFromName(String name) {
  final needle = name.trim().toUpperCase();
  if (needle.isEmpty) return null;

  // Already a code.
  if (needle.length == 2 && _names.containsKey(needle)) return needle;

  final alias = _aliases[needle];
  if (alias != null) return alias;

  for (final entry in _names.entries) {
    if (entry.value.toUpperCase() == needle) return entry.key;
  }

  return null;
}

/// The country a formatted address ends with.
///
/// Google puts the country last, so this reads the final comma-separated part
/// and nothing else — trying to find a country anywhere in the string matches
/// street names and towns that happen to share a name with one.
String? countryFromAddress(String address) {
  final parts = address.split(',');
  if (parts.isEmpty) return null;

  return countryCodeFromName(parts.last);
}

/// The country's name, or the code itself when it is not one we name.
String countryName(String code) {
  final iso = code.trim().toUpperCase();
  if (iso.isEmpty) return '';

  return _names[iso] ?? iso;
}

/// "🇬🇧 United Kingdom" — flag and name, for a filter or a menu.
String countryLabel(String code) {
  final iso = code.trim().toUpperCase();
  if (iso.isEmpty) return '';

  final flag = countryFlag(iso);
  final name = countryName(iso);

  return flag.isEmpty ? name : '$flag $name';
}
