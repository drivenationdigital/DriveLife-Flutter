import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The number on the app icon.
///
/// ── WHY THIS EXISTS, AND ONLY FOR iOS ───────────────────────────────
///
/// Android keeps its own count. It knows which notifications it is
/// showing, it adds them up, and it takes the number off when they are
/// opened or swiped away. Nothing here is needed for it.
///
/// iOS counts nothing. The badge is whatever the last push PUT there,
/// and it stays at that number until another push says otherwise — so
/// an iPhone shows "3" after the person has read all three, and goes on
/// showing it for days.
///
/// The server sets it on the way out (dl_notify_badge_count), which
/// covers a phone with the app shut. This covers the other half: the
/// app is open, the person is reading, and the number has to come down
/// without waiting for somebody else to send them something.
///
/// ── WHY A CHANNEL AND NOT A PACKAGE ─────────────────────────────────
///
/// Because this is the whole of it. A badge package would be another
/// dependency, another podspec and another thing to keep current, for
/// one method on one platform.
abstract final class AppBadge {
  const AppBadge._();

  static const MethodChannel _channel = MethodChannel('drivelife/badge');

  /// Sets the badge, or clears it at zero.
  ///
  /// Does nothing off iOS — not because it would break, but because
  /// Android's own count is right and overwriting it with ours would
  /// make it wrong the moment a notification is swiped away.
  ///
  /// Never throws. A badge is decoration on every screen that calls
  /// this, and an exception from a platform channel is not worth a
  /// failed refresh anywhere.
  static Future<void> set(int count) async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      await _channel.invokeMethod<void>('setBadge', {
        'count': count < 0 ? 0 : count,
      });
    } on MissingPluginException {
      // An older build of the iOS host, which has no such channel.
      // Nothing to do and nothing worth saying about it.
    } catch (e) {
      debugPrint('[AppBadge] could not set the badge: $e');
    }
  }

  /// Takes the number off the icon.
  static Future<void> clear() => set(0);
}
