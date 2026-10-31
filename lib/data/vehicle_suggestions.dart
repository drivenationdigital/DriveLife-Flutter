/// Suggestions for the "what did you spot?" field.
///
/// WHY A BUNDLED LIST AND NOT AN API
///
/// The obvious free option is NHTSA's vPIC
/// (vpic.nhtsa.dot.gov/api) — no key, no quota, every manufacturer
/// sold in the US. It is the wrong tool here for three reasons:
///
///   * It returns ~10,000 "makes", most of them trailer and bodywork
///     manufacturers. Typing "F" offers you forty companies that do
///     not make cars.
///   * Its model names are inconsistent and often absent for the cars
///     a spotter cares about. "Carrera GT" is not in it; "911" is, as
///     several unrelated entries.
///   * It is a network round trip per keystroke for a field somebody
///     fills in standing next to a car, possibly with no signal.
///
/// A curated list is instant, works offline, needs no key, and —
/// because it is what people tap rather than type — it keeps the
/// VALUES CONSISTENT. That matters more than coverage: `spotted_vehicle`
/// is free text, and "Porsche Carrera GT", "porsche carrera gt" and
/// "Carrera GT" are three different rows in the "most spotted" query.
///
/// The field stays free text, so anything missing can still be typed.
/// This only has to cover the common cases to do its job.
///
/// If exhaustive coverage is ever wanted, vPIC is the fallback to add
/// BEHIND this list rather than instead of it: local matches first,
/// remote ones after, so the common case never waits on a request.
library;

/// Cars worth suggesting: the exotic, the rare and the notable.
///
/// Weighted towards what somebody would actually stop and photograph.
/// A Fiesta is not a spot; a 2000 GT is.
const List<String> kVehicleSuggestions = [
  // Ferrari
  'Ferrari F40', 'Ferrari F50', 'Ferrari Enzo', 'Ferrari LaFerrari',
  'Ferrari 288 GTO', 'Ferrari 250 GTO', 'Ferrari F12', 'Ferrari 812',
  'Ferrari 488', 'Ferrari F8 Tributo', 'Ferrari SF90', 'Ferrari 296',
  'Ferrari Roma', 'Ferrari Purosangue', 'Ferrari Daytona SP3',
  'Ferrari Monza SP2', 'Ferrari 458 Speciale', 'Ferrari 430 Scuderia',
  'Ferrari Testarossa', 'Ferrari 355', 'Ferrari 360',

  // Lamborghini
  'Lamborghini Miura', 'Lamborghini Countach', 'Lamborghini Diablo',
  'Lamborghini Murcielago', 'Lamborghini Gallardo', 'Lamborghini Aventador',
  'Lamborghini Huracan', 'Lamborghini Revuelto', 'Lamborghini Urus',
  'Lamborghini Sian', 'Lamborghini Centenario', 'Lamborghini Veneno',
  'Lamborghini Reventon', 'Lamborghini Sesto Elemento',

  // Porsche
  'Porsche 911 GT3', 'Porsche 911 GT3 RS', 'Porsche 911 GT2 RS',
  'Porsche 911 Turbo S', 'Porsche 911 R', 'Porsche 911 Sport Classic',
  'Porsche Carrera GT', 'Porsche 918 Spyder', 'Porsche 959',
  'Porsche Cayman GT4', 'Porsche Boxster Spyder', 'Porsche Taycan',
  'Porsche Macan', 'Porsche Cayenne', 'Porsche Panamera',
  'Porsche 968 Club Sport', 'Porsche 993 Turbo', 'Porsche 996 GT3',

  // McLaren
  'McLaren F1', 'McLaren P1', 'McLaren Senna', 'McLaren Speedtail',
  'McLaren 720S', 'McLaren 750S', 'McLaren 765LT', 'McLaren 600LT',
  'McLaren 570S', 'McLaren Artura', 'McLaren GT', 'McLaren Elva',
  'McLaren Sabre', 'McLaren 12C',

  // Aston Martin
  'Aston Martin DB5', 'Aston Martin DB11', 'Aston Martin DB12',
  'Aston Martin Vantage', 'Aston Martin DBS', 'Aston Martin Valkyrie',
  'Aston Martin Valhalla', 'Aston Martin Vulcan', 'Aston Martin One-77',
  'Aston Martin Victor', 'Aston Martin DBX',

  // Bugatti, Koenigsegg, Pagani and the rest of the hypercars
  'Bugatti Veyron', 'Bugatti Chiron', 'Bugatti Divo', 'Bugatti Bolide',
  'Bugatti Centodieci', 'Bugatti Tourbillon', 'Bugatti EB110',
  'Koenigsegg Agera', 'Koenigsegg Jesko', 'Koenigsegg Regera',
  'Koenigsegg Gemera', 'Koenigsegg CCX', 'Koenigsegg One:1',
  'Pagani Zonda', 'Pagani Huayra', 'Pagani Utopia',
  'Rimac Nevera', 'Hennessey Venom', 'SSC Tuatara', 'Czinger 21C',
  'Gordon Murray T.50', 'Gordon Murray T.33', 'De Tomaso P72',
  'Zenvo TSR-S', 'Noble M600', 'Ultima RS', 'Radical SR3',
  'Ariel Atom', 'Ariel Nomad', 'BAC Mono', 'Caterham Seven',
  'Morgan Plus Four', 'Morgan Super 3', 'TVR Sagaris', 'TVR Chimaera',
  'Lotus Elise', 'Lotus Exige', 'Lotus Evora', 'Lotus Emira',
  'Lotus Evija', 'Lotus Esprit',

  // Mercedes-AMG
  'Mercedes-AMG GT', 'Mercedes-AMG GT Black Series', 'Mercedes-AMG One',
  'Mercedes-AMG C63', 'Mercedes-AMG E63', 'Mercedes-AMG A45',
  'Mercedes-AMG G63', 'Mercedes-Benz SLS AMG', 'Mercedes-Benz SLR McLaren',
  'Mercedes-Benz 300SL', 'Mercedes-Benz G-Wagon',

  // BMW
  'BMW M3', 'BMW M4', 'BMW M5', 'BMW M2', 'BMW M8', 'BMW XM',
  'BMW M1', 'BMW i8', 'BMW Z8', 'BMW 2002 Turbo', 'BMW E30 M3',
  'BMW E46 M3 CSL', 'BMW 1M',

  // Audi
  'Audi R8', 'Audi RS6', 'Audi RS3', 'Audi RS7', 'Audi TT RS',
  'Audi Quattro', 'Audi RS Q8', 'Audi S1',

  // Japanese
  'Nissan GT-R', 'Nissan Skyline R34', 'Nissan Skyline R33',
  'Nissan Skyline R32', 'Nissan 370Z', 'Nissan 400Z', 'Nissan Silvia S15',
  'Toyota Supra', 'Toyota GR Yaris', 'Toyota GR86', 'Toyota 2000GT',
  'Toyota Celica GT-Four', 'Toyota MR2', 'Lexus LFA', 'Lexus LC500',
  'Honda NSX', 'Honda S2000', 'Honda Civic Type R', 'Honda Integra Type R',
  'Mazda RX-7', 'Mazda RX-8', 'Mazda MX-5', 'Mitsubishi Evo',
  'Mitsubishi 3000GT', 'Subaru Impreza WRX STI', 'Subaru BRZ',
  'Suzuki Cappuccino',

  // American
  'Ford GT', 'Ford GT40', 'Ford Mustang', 'Ford Mustang Shelby GT500',
  'Ford Focus RS', 'Ford Sierra Cosworth', 'Ford Escort Cosworth',
  'Ford RS200', 'Chevrolet Corvette', 'Chevrolet Corvette Z06',
  'Chevrolet Camaro', 'Dodge Viper', 'Dodge Challenger Hellcat',
  'Dodge Charger', 'Shelby Cobra', 'Hummer H1', 'Cadillac CTS-V',
  'Tesla Model S Plaid', 'Tesla Roadster',

  // British and European saloons, estates and oddities
  'Jaguar F-Type', 'Jaguar XKR', 'Jaguar E-Type', 'Jaguar XJ220',
  'Jaguar Project 8', 'Land Rover Defender', 'Range Rover Sport SVR',
  'Bentley Continental GT', 'Bentley Bacalar', 'Bentley Mulliner Batur',
  'Rolls-Royce Phantom', 'Rolls-Royce Ghost', 'Rolls-Royce Wraith',
  'Rolls-Royce Spectre', 'Mini Cooper S', 'Mini JCW',
  'Alpine A110', 'Alfa Romeo Giulia Quadrifoglio', 'Alfa Romeo 4C',
  'Alfa Romeo 8C', 'Alfa Romeo 33 Stradale', 'Maserati MC20',
  'Maserati GranTurismo', 'Maserati MC12', 'Lancia Delta Integrale',
  'Lancia Stratos', 'Renault Clio Williams', 'Renault Megane RS',
  'Peugeot 205 GTI', 'Volkswagen Golf R', 'Volkswagen Golf GTI',
  'Volkswagen Corrado VR6', 'Vauxhall Lotus Carlton', 'Opel Manta',
  'Saab 900 Turbo', 'Volvo 850 R', 'Polestar 1', 'Polestar 2',
];

/// Suggestions matching what has been typed.
///
/// Matches anywhere in the string, not just at the start: somebody
/// looking for a Carrera GT types "carrera", not "porsche". A
/// prefix-only match is the single most common way an autocomplete
/// feels broken.
///
/// Results starting with the query come first, because when both match
/// the one that starts with it is almost always the one meant.
List<String> suggestVehicles(String query, {int limit = 6}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];

  final starts = <String>[];
  final contains = <String>[];

  for (final name in kVehicleSuggestions) {
    final lower = name.toLowerCase();

    if (lower.startsWith(q)) {
      starts.add(name);
    } else if (lower.contains(q)) {
      contains.add(name);
    }

    if (starts.length >= limit) break;
  }

  return [...starts, ...contains].take(limit).toList();
}
