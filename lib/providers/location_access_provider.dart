import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationAccessProvider with ChangeNotifier {
  bool? _hasAccess; // null = unknown / not yet checked
  bool _checking = false;

  /// True only after a check has completed (regardless of result).
  bool get isResolved => _hasAccess != null;

  /// True if location services are on AND permission granted.
  /// Returns false until the first check completes.
  bool get hasAccess => _hasAccess ?? false;

  bool get checking => _checking;

  /// Run the access check. Coalesces concurrent calls so multiple screens
  /// asking simultaneously result in only one platform request.
  Future<bool> refresh() async {
    if (_checking) {
      // Wait for the in-flight check to complete
      while (_checking) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _hasAccess ?? false;
    }

    _checking = true;
    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        _hasAccess = false;
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      _hasAccess =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      return _hasAccess!;
    } catch (e) {
      debugPrint('LocationAccessProvider.refresh failed: $e');
      _hasAccess = false;
      return false;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }
}
