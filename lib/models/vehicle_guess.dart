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

  /// "High", "Medium" or "Low", about the make and model only.
  final String confidence;

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
    this.imagesUsed = 0,
  });

  static const VehicleGuess none = VehicleGuess();

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
      imagesUsed: int.tryParse(read('images_used')) ?? 0,
    );
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
