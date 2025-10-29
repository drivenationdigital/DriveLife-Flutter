import 'package:flutter/material.dart';

class VideoMuteProvider extends ChangeNotifier {
  bool _muted = true;

  bool get muted => _muted;

  void toggle() {
    _muted = !_muted;
    notifyListeners();
  }
}
