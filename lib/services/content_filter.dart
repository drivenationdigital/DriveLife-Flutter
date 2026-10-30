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

  /// Casual swearing about a thing, a situation or nobody in
  /// particular. NOT veiled — see [ContentFilter.shouldVeil].
  mild,

  /// Casual swearing pointed at the person reading it. Veiled.
  ///
  /// The distinction this whole file exists to draw: "that build is
  /// fucking quick" and "fuck you" share a word and share nothing else.
  aimed,

  /// Slurs, sexual aggression, threats. Veiled.
  strong,
}

/// A word list, and the normalising that makes one work.
class ContentFilter {
  const ContentFilter._();

  /// Casual profanity used as an INTENSIFIER — about a car, a job, a
  /// situation, the weather.
  ///
  /// Never veiled on its own. "that thing is absolutely mental, sounds
  /// f***ing incredible" is a compliment in the register this community
  /// actually speaks, and a warning that fires on it is a warning people
  /// learn to tap straight through.
  ///
  /// Still counted, because repetition is its own signal — see [inspect].
  static const Set<String> _mildIntensifier = {
    'fuck',
    'fucking',
    'fucked',
    'fuckin',
    'fuk',
    'fck',
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
    'arsed',
    'damn',
    'goddamn',
    'bloody',
    'wank',
  };

  /// Casual profanity that NAMES A PERSON.
  ///
  /// Split out from the intensifiers because the grammar carries the
  /// intent. An intensifier describes a thing; one of these is something
  /// you call somebody. Near a "you" it is an insult aimed at the reader,
  /// which is the case this list exists to catch.
  ///
  /// It still needs the pronoun to qualify: "what a bastard of a job" is
  /// about a gearbox, and nothing here should veil it.
  static const Set<String> _mildEpithet = {
    'asshole',
    'arsehole',
    'arse',
    'ass',
    'prick',
    'twat',
    'wanker',
    'tosser',
    'knob',
    'knobhead',
    'dickhead',
    'dick',
    'bastard',
    'bitch',
    'btch',
    'bitches',
    'slag',
    'git',
    'fucker',
    'idiot',
    'moron',
    'scumbag',
  };

  /// Second-person pronouns: the marker that turns swearing into an
  /// insult. Normalised forms, so apostrophes are already gone.
  static const Set<String> _secondPerson = {
    'you',
    'u',
    'ur',
    'your',
    'youre',
    'yours',
    'yourself',
    'urself',
    'ya',
    'yall',
    'thou',
  };

  /// Phrases that are aimed by construction, whatever is around them.
  ///
  /// A pronoun-distance rule alone misses these: "fuck off" has no
  /// pronoun in it at all, and is unambiguously directed at whoever is
  /// reading.
  static const List<String> _aimedPhrases = [
    'fuck you',
    'fuck u',
    'fuck ya',
    'fuck yourself',
    'fuck off',
    'fuck of',
    'get fucked',
    'piss off',
    'sod off',
    'screw you',
    'screw u',
    'up yours',
    'shut the fuck up',
    'stfu',
    'do one',
  ];

  /// How many tokens may sit between a pronoun and an epithet.
  ///
  /// Two, which reaches "youre an asshole" and stops short of "you are
  /// fucking quick". Widening it starts veiling compliments; narrowing it
  /// misses the commonest phrasing of the insult. This number is the
  /// whole heuristic, so it is named rather than buried in the loop.
  static const int _aimWindow = 2;

  /// The old combined list, kept as the union for counting purposes.
  static Set<String> get _mild => {..._mildIntensifier, ..._mildEpithet};

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

    return _isAimed(tokens, flattened) ? ContentFlag.aimed : ContentFlag.mild;
  }

  /// Whether the swearing in this message is pointed at the reader.
  ///
  /// Two signals, and both are heuristics rather than grammar. Said
  /// plainly because the limits matter: this will veil the occasional
  /// message that was only ever friendly, and let through cruelty that
  /// never says "you". It is a good deal better than treating "fuck you"
  /// and "fucking quick" as the same thing, which is the alternative.
  static bool _isAimed(List<String> tokens, String flattened) {
    // 1. Phrases that are directed by construction. "fuck off" has no
    //    pronoun in it and is not ambiguous.
    for (final phrase in _aimedPhrases) {
      if (flattened.contains(phrase)) return true;
    }

    // 2. A message that is nothing BUT words for a person. Someone who
    //    sends you "asshole" and nothing else has not left open the
    //    question of who they meant, and there is no pronoun for rule 3
    //    to anchor to.
    //
    //    Epithets only, deliberately. A message that is just "fuck" or
    //    just "shit" is exasperation at a situation, and veiling it
    //    would be exactly the over-firing this split exists to avoid.
    if (tokens.isNotEmpty &&
        tokens.every((token) => _matchesList(token, _mildEpithet))) {
      return true;
    }

    // 3. A word that names a person, close to a word that means the
    //    reader. "you asshole" and "youre an asshole" qualify; "what a
    //    bastard of a job" has no pronoun and does not.
    //
    //    Distance is measured in both directions because English puts
    //    the pronoun on either side — "you prick" and "prick, are you
    //    serious" are both aimed.
    for (var i = 0; i < tokens.length; i++) {
      if (!_matchesList(tokens[i], _mildEpithet)) continue;

      final from = (i - _aimWindow).clamp(0, tokens.length);
      final to = (i + _aimWindow + 1).clamp(0, tokens.length);

      for (var j = from; j < to; j++) {
        if (j != i && _secondPerson.contains(tokens[j])) return true;
      }
    }

    return false;
  }

  /// Whether to put the message behind a warning.
  ///
  /// [ContentFlag.aimed] and [ContentFlag.strong]. Swearing ABOUT
  /// something stays visible — see [_mildIntensifier] — because a
  /// warning that fires on ordinary conversation is one people learn to
  /// tap through, and then it is not protecting anybody from the message
  /// that mattered.
  static bool shouldVeil(String content) {
    final flag = inspect(content);
    return flag == ContentFlag.aimed || flag == ContentFlag.strong;
  }
}
