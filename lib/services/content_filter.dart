/// Deciding whether a message should be shown straight away.
///
/// This is tier one of two. It is a word list: deterministic, free,
/// instant, and works with no signal. Tier two is a Gemini call in
/// chat_webhook.php that catches what a list cannot — a sentence that is
/// threatening or cruel without containing a single listed word — and
/// arrives a beat later as a flag on the row.
///
/// Both feed one piece of UI: the veil over the bubble.
///
/// WHY THIS RUNS WHEN A MESSAGE IS DRAWN, NOT WHEN IT IS SENT
///
/// The point is to protect the person reading, so the decision belongs on
/// their device at the moment of reading. Checking at send time would put
/// it on the one device with an interest in getting around it, and would
/// mean a message already in the thread could never be re-evaluated when
/// the list improves.
library;

/// How bad, as far as a word list can tell.
enum ContentFlag {
  /// Nothing matched.
  none,

  /// Casual swearing. NOT veiled — see [ContentFilter.shouldVeil].
  mild,

  /// Slurs, sexual aggression, threats. Veiled.
  strong,
}

/// A word list, and the normalising that makes one work.
class ContentFilter {
  const ContentFilter._();

  /// Casual profanity.
  ///
  /// Deliberately NOT veiled on its own. This is a car enthusiast app and
  /// "that thing is absolutely mental, sounds f***ing incredible" is a
  /// compliment in the register the community actually speaks. Veiling it
  /// would put a warning on ordinary conversation, and a warning people
  /// tap through fifty times a day is one they will also tap through on
  /// the message that mattered.
  ///
  /// Kept and scored because repetition is still a signal — see
  /// [inspect].
  static const Set<String> _mild = {
    'fuck',
    'fucking',
    'fucked',
    'fucker',
    'fuk',
    'fck',
    'fuckin',
    'shit',
    'shite',
    'shitty',
    'sht',
    'bullshit',
    'piss',
    'pissed',
    'crap',
    'bollocks',
    'bugger',
    'arse',
    'arsehole',
    'ass',
    'asshole',
    'arsed',
    'damn',
    'goddamn',
    'bloody',
    'wanker',
    'wank',
    'prick',
    'git',
    'knob',
    'knobhead',
    'tosser',
    'twat',
    'bastard',
    'bitch',
    'btch',
    'bitches',
    'slag',
  };

  /// Slurs, sexual aggression, and threats.
  ///
  /// These veil on a single occurrence. There is no register in which a
  /// racial slur arriving in a stranger's message is ordinary.
  ///
  /// Short and blunt on purpose. A long list is not a better list — it is
  /// a list nobody audits, and every entry is a chance to wrongly accuse
  /// somebody. The nuanced cases are tier two's job, not this one's.
  static const Set<String> _strong = {
    // Racial and ethnic slurs.
    'nigger', 'nigga', 'niggers', 'paki', 'pakis', 'chink', 'chinks',
    'spic', 'wetback', 'coon', 'gook', 'raghead', 'towelhead',
    // Homophobic and transphobic slurs.
    'faggot', 'fag', 'faggots', 'dyke', 'tranny', 'trannies', 'shemale',
    // Misogynistic slurs used as attacks.
    'cunt', 'cunts', 'whore', 'whores', 'slut', 'sluts',
    // Ableist slurs.
    'retard', 'retarded', 'retards', 'spastic', 'mongoloid',
    // Sexual aggression.
    'rape', 'raping', 'rapist', 'molest', 'paedo', 'pedo', 'paedophile',
  };

  /// Phrases that are threats regardless of the words around them.
  ///
  /// Matched on the normalised string rather than token by token, because
  /// the meaning is in the sequence. This is the narrow slice of "harsh
  /// things" a list can honestly catch; the rest is tier two.
  static const List<String> _threats = [
    'kill yourself',
    'kill your self',
    'kys',
    'hang yourself',
    'you should die',
    'i will kill you',
    'ill kill you',
    'im going to kill you',
    'i will find you',
    'ill find you',
    'watch your back',
    'youre dead',
    'your dead',
    'i know where you live',
    'end your life',
  ];

  /// Characters people substitute to get past a list like this one.
  static const Map<String, String> _leet = {
    '4': 'a',
    '@': 'a',
    '3': 'e',
    '1': 'i',
    '!': 'i',
    '|': 'i',
    '0': 'o',
    '5': 's',
    r'$': 's',
    '7': 't',
    '+': 't',
    '8': 'b',
  };

  /// Normalise text for matching.
  ///
  /// Lowercases, folds the leet substitutions above, drops the separators
  /// people put INSIDE a word (f.u.c.k, f*ck, f-u-c-k), and collapses a
  /// run of three or more identical letters to one so "fuuuuck" matches.
  ///
  /// Three, not two: collapsing doubles would turn "pass" into "pas" and
  /// "assess" into "ases", and a normaliser that mangles ordinary English
  /// creates far more wrong answers than the obfuscation it defeats.
  static String normalise(String input) {
    final buffer = StringBuffer();

    for (final rune in input.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_leet[char] ?? char);
    }

    var text = buffer.toString();

    // Pure separators inside a word: f.u.c.k, f-u-c-k, f_u_c_k.
    text = text.replaceAll(RegExp(r'[._\-]'), '');

    // An asterisk is NOT a separator and must not be deleted. It stands
    // in for a letter, so dropping it turns "c*nt" into "cnt", which
    // matches nothing — the single most common way of writing these
    // words would sail straight through. It is kept here and treated as
    // a wildcard in [_matchesList].
    //
    // Runs of 3+ down to one, letters only. Including '*' would collapse
    // "f***k" to "f*k" and break the same case again.
    text = text.replaceAllMapped(
      RegExp(r'([a-z0-9])\1{2,}'),
      (match) => match.group(1)!,
    );

    return text;
  }

  /// Whether a token is in [list], allowing '*' to stand for any letter.
  ///
  /// A plain set lookup first, because that is the overwhelming majority
  /// of tokens and a regex per word per token is not free.
  static bool _matchesList(String token, Set<String> list) {
    if (list.contains(token)) return true;
    if (!token.contains('*')) return false;

    // Escape everything else, then let '*' mean one character. One
    // character, not many: "a*" should not match every word beginning
    // with 'a'.
    final pattern = token
        .split('')
        .map((char) => char == '*' ? '.' : RegExp.escape(char))
        .join();

    final regex = RegExp('^$pattern\$');
    return list.any(regex.hasMatch);
  }

  /// Split normalised text into comparable tokens.
  ///
  /// Whole tokens, never substrings. Substring matching is how a filter
  /// ends up refusing to discuss Scunthorpe, and this is a UK car app —
  /// "Scunthorpe", "cockpit", "dipstick", "knocker", "shaft" and "nuts"
  /// are all ordinary vocabulary here. Matching whole words means none of
  /// them can ever trip, with no allowlist to maintain.
  static List<String> _tokens(String normalised) => normalised
      .split(RegExp(r'[^a-z0-9*]+'))
      .where((token) => token.isNotEmpty && token != '*')
      .toList();

  /// What the list makes of this message.
  static ContentFlag inspect(String content) {
    if (content.trim().isEmpty) return ContentFlag.none;

    final normalised = normalise(content);

    // Threat phrases first — they outrank everything and are the whole
    // reason this is not a swearing filter.
    final flattened = normalised.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    for (final phrase in _threats) {
      if (flattened.contains(phrase)) return ContentFlag.strong;
    }

    final tokens = _tokens(normalised);

    var mildCount = 0;
    for (final token in tokens) {
      if (_matchesList(token, _strong)) return ContentFlag.strong;
      if (_matchesList(token, _mild)) mildCount++;
    }

    if (mildCount == 0) return ContentFlag.none;

    // "Spams curse words" — the thing a per-word rule cannot see. One
    // swear is how people talk; six in one message is somebody shouting,
    // and the difference is the count rather than the vocabulary.
    if (mildCount >= 4) return ContentFlag.strong;

    return ContentFlag.mild;
  }

  /// Whether to put the message behind a warning.
  ///
  /// Only [ContentFlag.strong]. See the note on [_mild] for why casual
  /// swearing does not qualify: a warning that fires constantly is a
  /// warning nobody reads.
  static bool shouldVeil(String content) =>
      inspect(content) == ContentFlag.strong;
}
