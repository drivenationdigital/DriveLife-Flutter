import 'dart:async';
import 'dart:convert';

import 'package:drivelife/services/app_badge.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import 'package:drivelife/config/app_environment.dart';

class NotificationsAPI {
  static String get _baseUrl =>
      '${AppEnvironment.wordpressBase}/wp-json/app/v1';

  /// The scheduled-notification endpoints live on v2.
  static String get _v2Url =>
      '${AppEnvironment.wordpressBase}/wp-json/app/v2';

  static final AuthService _auth = AuthService();

  /// Tell the server a scheduled notification was tapped.
  ///
  /// [notifyId] is the `notify_id` the push carried — a row in
  /// `ce_notify_sent`. The server stamps `clicked_at` and writes a
  /// `notification_clicked` row into `ce_user_activity`, which is how
  /// a notification's click-through rate is known at all.
  ///
  /// ── WHY THIS NEVER THROWS AND NEVER BLOCKS ──────────────────────
  ///
  /// It is called from the tap handler, immediately before navigating.
  /// Nothing the user wants depends on it: if it fails, the only cost
  /// is one uncounted tap. So it swallows everything, including a dead
  /// network, rather than risk a notification that will not open
  /// because a statistics call timed out.
  ///
  /// No token is sent, deliberately. A notification tapped from a cold
  /// start arrives before the app has restored a session, and that is
  /// precisely the tap most worth counting. The endpoint accepts a bare
  /// id for that reason — the worst a forged one does is overstate a
  /// rate. See dl_notify_clicked().
  static Future<void> reportNotificationClick(String notifyId) async {
    final id = notifyId.trim();

    if (id.isEmpty) return;

    try {
      await http
          .post(
            Uri.parse('$_v2Url/notify/clicked'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'notify_id': id}),
          )
          // Short, because a tap is waiting behind it. The server records
          // the click or it does not; either way the screen opens.
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      print('Could not report notification click: $e');
    }
  }

  /// Get user notifications
  static Future<Map<String, dynamic>?> getUserNotifications({
    bool loadOldNotifications = false,
  }) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/get-notifications'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user['id'],
          'load_old_notifications': loadOldNotifications,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print('Failed to load notifications: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
    return null;
  }

  /// Get unread notification count
  ///
  /// ── AND SET THE APP ICON BADGE WHILE WE ARE HERE ────────────────
  ///
  /// Here rather than at the call sites, of which there are three and
  /// counting: the home shell, the messages screen and the shared
  /// header. Every one of them is asking the same question for the
  /// same reason, and a fourth one added later would silently not
  /// update the badge.
  ///
  /// It matters on iOS only. The badge there is whatever the last push
  /// put on it — nothing takes it off when the notifications are read
  /// — so without this an iPhone keeps showing a number for things the
  /// person dealt with days ago. See [AppBadge].
  ///
  /// Only on a successful read. A failed request returns 0 so callers
  /// can hide their dot, but 0 is also the instruction to CLEAR the
  /// badge, and clearing it because the network dropped would hide
  /// real unread notifications.
  static Future<int> getNotificationCount() async {
    try {
      final user = await _auth.getUser();
      if (user == null) return 0;

      final response = await http.post(
        Uri.parse('$_baseUrl/get-new-notifications-count'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id']}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final count = data['count'];
        final unread = count is int
            ? count
            : int.tryParse(count.toString()) ?? 0;

        unawaited(AppBadge.set(unread));

        return unread;
      }
    } catch (e) {
      print('Error fetching notification count: $e');
    }
    return 0;
  }

  /// Mark all notifications as read
  ///
  /// Clears the icon badge with them. Opening the notifications screen
  /// is the moment somebody has dealt with the lot, and waiting for
  /// the next count refresh to notice leaves a number on the icon of
  /// an app they are currently looking at.
  static Future<bool> markMultipleNotificationsAsRead() async {
    try {
      final user = await _auth.getUser();
      if (user == null) return false;

      final response = await http.post(
        Uri.parse('$_baseUrl/bulk-notifications-read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id']}),
      );

      // Only when the server agreed. A badge cleared against a request
      // that failed says "nothing waiting" about notifications that
      // are still unread on the server and will come back on the next
      // refresh.
      if (response.statusCode == 200) {
        unawaited(AppBadge.clear());
      }

      return response.statusCode == 200;
    } catch (e) {
      print('Error marking notifications as read: $e');
      return false;
    }
  }
}
