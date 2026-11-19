/// What a set of photographs says a vehicle is.
///
/// ── WHY EVERY FIELD CAN BE EMPTY ────────────────────────────────────
///
/// Because a photograph can show you a badge and not a trim level, or a
/// shape and not a badge. The model is asked to answer null rather than
/// guess, and a null arrives here as an empty string, so a field that
/// could not be read leaves the form field alone for somebody to fill
/// in themselves.
///
/// A wrong variant is worse than no variant: an empty field reads as a
/// question and a wrong one reads as an answer, and the second is the
/// one people accept without looking.
class VehicleGuess {
  final String make;
  final String model;

  /// The trim, generation or performance badge — "GT3 Touring".
  ///
  /// The part an owner would correct you on, and the part a make and
  /// model dropdown can never hold.
  final String variant;

  /// "2022", or a range like "2015-2023", or empty.
  final String year;

  final String colour;
  final String body;

  /// The number plate, uppercased with the spaces out, or empty.
  ///
  /// ── READ, NOT RECALLED, AND STILL THE RISKIEST FIELD ────────────
  ///
  /// This one really is in the photograph, which makes it the most
  /// reliable thing here and the most consequential thing to get wrong.
  /// A plate is how a vehicle is matched against photographs other
  /// people have uploaded, so a single wrong character does not read as
  /// a typo — it points at a different car.
  ///
  /// The server nulls it unless every character was certain and checks
  /// the shape of what is left, so an empty string here is the normal
  /// answer for a plate that was angled, blurred or cropped.
  final String registration;

  /// "High", "Medium" or "Low", about the make and model only.
  final String confidence;

  /// Peak power in BHP, as a whole number. Empty when unknown.
  ///
  /// ── RECALLED, NOT SEEN ──────────────────────────────────────────
  ///
  /// Nothing in a photograph shows how fast a car is. These are the
  /// manufacturer's published figures for whatever variant the photos
  /// were read as, so they inherit the variant's uncertainty and add
  /// to it: a GT3 read as a Carrera gives three plausible, wrong
  /// numbers, and a remapped car's real figures were never published
  /// at all.
  ///
  /// Which is why they only ever fill an empty field.
  final String powerBhp;

  /// 0-62mph in seconds, one decimal place. Empty when unknown.
  final String zeroTo62;

  /// Top speed in MPH, a whole number. Empty when unknown.
  final String topSpeedMph;

  /// How many of the photographs the server actually managed to read.
  final int imagesUsed;

  const VehicleGuess({
    this.make = '',
    this.model = '',
    this.variant = '',
    this.year = '',
    this.colour = '',
    this.body = '',
    this.confidence = '',
    this.registration = '',
    this.imagesUsed = 0,
    this.powerBhp = '',
    this.zeroTo62 = '',
    this.topSpeedMph = '',
  });

  static const VehicleGuess none = VehicleGuess();

  /// The same guess, with figures that arrived later.
  ///
  /// ── WHY THEY ARE PUT BACK ON THE GUESS ──────────────────────────
  ///
  /// The figures come from a second call now, which means the banner's
  /// "Not right?" would otherwise know nothing about them — and
  /// clearing a wrong car would leave its power, 0-62 and top speed
  /// sitting in the form underneath.
  ///
  /// They were recalled from the name this guess read, so disowning
  /// the car has to disown its numbers.
  VehicleGuess copyWithStats({
    String? powerBhp,
    String? zeroTo62,
    String? topSpeedMph,
    String? registration,
  }) => VehicleGuess(
    make: make,
    model: model,
    variant: variant,
    year: year,
    colour: colour,
    body: body,
    confidence: confidence,
    registration: registration ?? this.registration,
    imagesUsed: imagesUsed,
    powerBhp: powerBhp ?? this.powerBhp,
    zeroTo62: zeroTo62 ?? this.zeroTo62,
    topSpeedMph: topSpeedMph ?? this.topSpeedMph,
  );

  /// Is there anything here worth showing somebody?
  ///
  /// A make or a model. Not a colour on its own — "we think this is a
  /// Silver" is not an identification, and offering it as one spends
  /// the credibility the real guesses need.
  bool get hasGuess => make.isNotEmpty || model.isNotEmpty;

  /// "Porsche 911 GT3 Touring", for the banner.
  String get label =>
      [make, model, variant].where((s) => s.isNotEmpty).join(' ');

  /// Worth applying without being asked.
  ///
  /// Low confidence still gets shown, and still gets filled in — the
  /// banner says what we think and the fields are editable either way,
  /// so the question is only whether to say it quietly. Kept as its own
  /// getter so that decision lives in one place if it ever changes.
  bool get isConfident => confidence.toLowerCase() != 'low';

  factory VehicleGuess.fromMap(Map<String, dynamic> map) {
    String read(String key) {
      final value = map[key];
      return value == null ? '' : '$value'.trim();
    }

    return VehicleGuess(
      make: read('make'),
      model: read('model'),
      variant: read('variant'),
      year: read('year'),
      colour: read('colour'),
      body: read('body'),
      confidence: read('confidence'),
      registration: read('registration'),
      imagesUsed: int.tryParse(read('images_used')) ?? 0,
      powerBhp: read('power_bhp'),
      zeroTo62: read('zero_to_62'),
      topSpeedMph: read('top_speed_mph'),
    );
  }

  /// Which entry of a make dropdown this guess means, or null.
  ///
  /// ── WHY AN EXACT MATCH IS NOT ENOUGH ────────────────────────────
  ///
  /// The list is how a British road registry spells these names; the
  /// model answers with how people say them. Compared literally,
  /// lowercased, the failures are all of the common ones:
  ///
  ///   Mercedes        vs  Mercedes-Benz
  ///   Mercedes Benz   vs  Mercedes-Benz
  ///   Citroën         vs  Citroen
  ///   Alfa            vs  Alfa Romeo
  ///   VW              vs  Volkswagen
  ///   Range Rover     vs  Land Rover      (that one is a model)
  ///
  /// So: punctuation and accents are set aside, a short list of names
  /// people actually use is translated, and a guess that is the start
  /// of exactly one entry takes it.
  ///
  /// Returns null rather than a wrong entry. The banner still names
  /// what the photographs said, so an unmatched make is visible rather
  /// than silently replaced by whatever sorted first.
  static String? matchMake(String guess, List<String> options) {
    final wanted = _fold(guess);

    if (wanted.isEmpty) return null;

    String? exact(String name) {
      for (final option in options) {
        if (_fold(option) == name) return option;
      }

      return null;
    }

    // ── THE LIST WINS BEFORE ANY ALIAS ──────────────────────────────
    //
    // This list carries BOTH "Opel" and "Vauxhall", and both "Rover"
    // and "Land Rover". Translating a name before checking whether the
    // list already has it would answer "Opel" with Vauxhall and
    // "Rover" with Land Rover — picking a different marque over the
    // one the photographs actually said.
    final straight = exact(wanted);

    if (straight != null) return straight;

    // Only now: what people say, against what the list calls it.
    // Nothing here may be a list entry in its own right.
    const aliases = <String, String>{
      'vw': 'volkswagen',
      'merc': 'mercedesbenz',
      'mercedes': 'mercedesbenz',
      'benz': 'mercedesbenz',
      'amg': 'mercedesbenz',
      'chevy': 'chevrolet',
      'rangerover': 'landrover',
      'rangeroversport': 'landrover',
      'ds': 'dsautomobiles',
      'beemer': 'bmw',
      'bimmer': 'bmw',
      'vauxhallopel': 'vauxhall',
      'volvocars': 'volvo',
      'skodaauto': 'skoda',
      'seatcupra': 'cupra',
      'astonmartinlagonda': 'astonmartin',
      'thelandroverco': 'landrover',
    };

    final aliased = aliases[wanted];

    if (aliased != null) {
      final match = exact(aliased);

      if (match != null) return match;
    }

    // A prefix, but only when it picks out exactly one. "Mercedes"
    // starts "Mercedes-Benz" and nothing else; "A" starts a dozen
    // makes and means none of them.
    if (wanted.length >= 3) {
      final starts = options.where((o) => _fold(o).startsWith(wanted)).toList();

      if (starts.length == 1) return starts.first;

      // And the other way round: "Volkswagen Golf" as a make, which is
      // a make and a model run together.
      final within = options.where((o) => wanted.startsWith(_fold(o))).toList();

      if (within.length == 1) return within.first;
    }

    return null;
  }

  /// A name reduced to its letters and digits, accents folded out.
  static String _fold(String value) {
    var out = value.toLowerCase().trim();

    const accents = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n', 'ß': 'ss',
    };

    accents.forEach((from, to) => out = out.replaceAll(from, to));

    return out.replaceAll(RegExp('[^a-z0-9]+'), '');
  }

  /// The year as something a four-digit field will accept.
  ///
  /// A range — "2015-2023" — is a real answer to "when was this made"
  /// and a useless one to put in a box expecting one year. The first
  /// year of the range is the honest reading of it, and an owner who
  /// knows better will correct it; an owner who does not is no worse
  /// off than with an empty field.
  String get yearForField {
    final match = RegExp(r'(19|20)\d{2}').firstMatch(year);
    return match?.group(0) ?? '';
  }
}
