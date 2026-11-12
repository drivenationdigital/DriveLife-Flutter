import 'package:drivelife/services/media_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

/// Turning a geocoder result into something worth reading.
///
/// The platform geocoders disagree about what each field means, and
/// Android in particular puts the HOUSE NUMBER in `name`. Taking fields
/// in their documented order produced labels like "57, Soho, London",
/// which is why this has tests rather than just a join().
void main() {
  group('formatPlacemark', () {
    test('a real place name leads', () {
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: 'Ace Cafe', locality: 'London', country: 'UK'),
        ),
        'Ace Cafe, London, UK',
      );
    });

    test('a house number in name is dropped for the street', () {
      // THE Android bug: getFeatureName() returns the street number.
      expect(
        MediaLocationService.formatPlacemark(
          _place(
            name: '57',
            subThoroughfare: '57',
            thoroughfare: 'Carnaby Street',
            subLocality: 'Soho',
            locality: 'London',
          ),
        ),
        'Carnaby Street, Soho, London',
      );
    });

    test('a number with a letter suffix is also a house number', () {
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: '12B', thoroughfare: 'High Street', locality: 'Leeds'),
        ),
        'High Street, Leeds',
      );
    });

    test('a Plus Code is never shown', () {
      // Technically a location, but meaningless to read, and it looks
      // enough like data to be mistaken for a real answer.
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: '9C3XGW4C+9F', locality: 'Bristol', country: 'UK'),
        ),
        'Bristol, UK',
      );
    });

    test('a postcode in name is dropped', () {
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: '90210', locality: 'Beverly Hills'),
        ),
        'Beverly Hills',
      );
    });

    test('repeated fields are shown once', () {
      // Placemarks repeat themselves constantly, and "Soho, Soho,
      // London" reads like a bug.
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: 'Soho', subLocality: 'Soho', locality: 'London'),
        ),
        'Soho, London',
      );
    });

    test('case differences still count as repeats', () {
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: 'SOHO', subLocality: 'Soho', locality: 'London'),
        ),
        'SOHO, London',
      );
    });

    test('capped at three parts, so it stays a place not an address', () {
      final label = MediaLocationService.formatPlacemark(
        _place(
          name: 'Ace Cafe',
          thoroughfare: 'North Circular',
          subLocality: 'Stonebridge',
          locality: 'London',
          administrativeArea: 'Greater London',
          country: 'UK',
        ),
      );

      expect(label!.split(', ').length, 3);
      expect(label, 'Ace Cafe, North Circular, Stonebridge');
    });

    test('falls back to whatever is available', () {
      // Rural and offshore points often resolve to a country and
      // nothing else. Something beats nothing.
      expect(
        MediaLocationService.formatPlacemark(_place(country: 'Norway')),
        'Norway',
      );
    });

    test('an empty placemark gives null rather than punctuation', () {
      // A bare join() here produced ", , " on screen.
      expect(MediaLocationService.formatPlacemark(_place()), isNull);
    });

    test('whitespace-only fields count as empty', () {
      expect(
        MediaLocationService.formatPlacemark(
          _place(name: '   ', locality: '  ', country: 'UK'),
        ),
        'UK',
      );
    });
  });
}

Placemark _place({
  String? name,
  String? subThoroughfare,
  String? thoroughfare,
  String? subLocality,
  String? locality,
  String? administrativeArea,
  String? country,
}) {
  return Placemark(
    name: name ?? '',
    street: '',
    isoCountryCode: '',
    country: country ?? '',
    postalCode: '',
    administrativeArea: administrativeArea ?? '',
    subAdministrativeArea: '',
    locality: locality ?? '',
    subLocality: subLocality ?? '',
    thoroughfare: thoroughfare ?? '',
    subThoroughfare: subThoroughfare ?? '',
  );
}
