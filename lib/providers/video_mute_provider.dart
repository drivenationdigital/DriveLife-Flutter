import 'package:flutter/material.dart';

class VideoMuteProvider extends ChangeNotifier {
  bool _muted = true;

  bool get muted => _muted;

  void toggle() {
    _muted = !_muted;
    notifyListeners();
  }

  /// Called when the hardware volume button raises volume while muted.
  /// Does NOT fire when the user explicitly tapped the in-app mute button.
  void unmuteFromVolumeButton() {
    if (_muted) {
      _muted = false;
      notifyListeners();
    }
  }
}
