import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
class LocationService {
  /// Check if location permissions are granted
  static Future<bool> hasPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Request location permission
  static Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Get current location
  static Future<Position?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return null;
      }

      // Check permission
      bool hasPermission = await LocationService.hasPermission();
      if (!hasPermission) {
        hasPermission = await requestPermission();
      }

      if (!hasPermission) {
        print('Location permission denied');
        return null;
      }

      // Get location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return position;
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  /// Get location as coordinate object
  static Future<Map<String, double>?> getCoordinates() async {
    final position = await getCurrentLocation();
    if (position == null) return null;

    return {'latitude': position.latitude, 'longitude': position.longitude};
  }

  static Future<String?> getDeviceCountry() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('📍 Location services disabled');
        return null;
      }

      // Check permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          print('📍 Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('📍 Location permission denied forever');
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );

      print('📍 Got position: ${position.latitude}, ${position.longitude}');

      // Get country from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final country = placemarks.first.isoCountryCode?.toUpperCase();
        print('📍 Resolved country: $country');
        return country;
      }

      return null;
    } catch (e) {
      print('❌ Error getting device country: $e');
      return null;
    }
  }
}
