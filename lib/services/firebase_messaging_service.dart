import 'package:drivelife/screens/media/gallery_tag_requests_screen.dart';
import 'dart:io';

import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:drivelife/services/notification_target.dart';
import 'package:drivelife/api/notifications_api.dart';
import 'package:drivelife/screens/garage/view_reminders.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

@pragma('vm:entry-point')
/// `@username` for a notification built in the BACKGROUND isolate.
///
/// Separate from FirebaseMessagingService._accountLabel because this
/// isolate has no providers and so cannot ask how many accounts are
/// signed in. It can only honour the flag.
///
/// Returns null rather than an empty string, so it drops straight into
/// a nullable subText or subtitle.
String? _backgroundAccountLabel(NotificationTarget target) {
  if (!FeatureFlags.notificationAccountLabel) return null;

  final name = target.accountName;
  if (name == null || name.isEmpty) return null;

  return '@$name';
}

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  print('📩 Background message received: $data');

  final target = NotificationTarget.fromData(data);

  final convId = data['conversation_id'] ?? '';
  final isChatMessage = convId.isNotEmpty;
  final isGroup = data['is_group'] == 'true';
  final senderId = data['sender_id'] ?? '';
  final groupName = data['group_name'] ?? '';
  final title = data['title'] ?? 'Notification';
  final body = data['body'] ?? '';

  // Init local notifications
  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings),
  );

  // Fetch sender avatar (with proper logging this time)
  ByteArrayAndroidBitmap? largeIcon;
  final senderImageUrl = data['sender_image'] ?? '';
  if (senderImageUrl.isNotEmpty) {
    try {
      final response = await http.get(Uri.parse(senderImageUrl));
      if (response.statusCode == 200) {
        largeIcon = ByteArrayAndroidBitmap(response.bodyBytes);
      } else {
        print(
          '⚠️ BG avatar fetch failed: ${response.statusCode} for $senderImageUrl',
        );
      }
    } catch (e) {
      print('⚠️ BG avatar error: $e');
    }
  }

  // Unique ID — avoid the ''.hashCode = 0 collision for non-chat notifs
  final notificationId = isChatMessage
      ? convId.hashCode
      : (message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(100000));

  // Pick style based on notification type
  StyleInformation? style;
  if (isChatMessage) {
    final person = Person(
      name: title,
      icon: largeIcon != null ? ByteArrayAndroidIcon(largeIcon.data) : null,
      key: senderId,
    );
    style = MessagingStyleInformation(
      const Person(name: 'You'),
      conversationTitle: isGroup ? groupName : null,
      groupConversation: isGroup,
      messages: [Message(body, DateTime.now(), person)],
    );
  } else {
    style = BigTextStyleInformation(body);
  }

  await localNotifications.show(
    notificationId,
    isChatMessage && isGroup ? groupName : title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: largeIcon,
        styleInformation: style,
        playSound: true,
        // The account label, when it is switched on at all.
        //
        // This isolate has no providers, so unlike the foreground path
        // it cannot tell whether a second account is signed in -- it
        // would show the label either way. With
        // FeatureFlags.notificationAccountLabel off it shows none, and
        // the group name takes the slot on a group chat as before.
        subText: _backgroundAccountLabel(target) ??
            (isChatMessage && isGroup ? groupName : null),
        showWhen: true,
        // Per account as well as per conversation, so two accounts in the
        // same conversation do not collapse into one thread.
        groupKey: isChatMessage
            ? 'chat_${target.accountId ?? 'self'}_$convId'
            : null,
        setAsGroupSummary: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: _backgroundAccountLabel(target),
      ),
    ),
    // Carries the account, so the tap switches to it. This is the path a
    // cold start reads, which is exactly when the active account is least
    // likely to be the right one.
    payload: target.encode(),
  );
}

class FirebaseMessagingService {
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Held until the navigator exists, for a tap that launched the app.
  ///
  /// A NotificationTarget rather than a String, so the account the
  /// notification was for survives the wait. As a bare url it did not,
  /// and a cold start always opened under the active account.
  static NotificationTarget? _pendingTarget;

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Add this callback reference
  static Function(String?)? onNotificationTapped;

  static Future<void> initialize() async {
    // Request permission (iOS)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');
    } else {
      print('User declined or has not accepted notification permission');
    }

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // Update iOS settings to include action categories
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'post_complete',
          actions: [
            DarwinNotificationAction.plain('view_post', 'View Post'),
            DarwinNotificationAction.plain('view_profile', 'View Profile'),
          ],
        ),
      ],
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channel (Android)
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // Handle case where app was launched by tapping a local notification
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        // Queue it — navigator won't be ready yet at this point
        final target = NotificationTarget.fromPayload(payload);
        _pendingTarget = target;
        print('🚀 Cold-start from local notification, queued: $payload');

        // ── THE COLD START THAT ACTUALLY HAPPENS ──────────────────
        //
        // Logged HERE, not where the target is finally opened: the
        // queue is flushed by flushPendingDeepLink() once a navigator
        // exists, and an open that never found one is still an open.
        //
        // This is the real killed-app path for us. The FCM equivalents
        // (onMessageOpenedApp, getInitialMessage) only fire for
        // notifications FCM RENDERED, and ours are data-only — FCM
        // draws nothing, so it knows nothing was tapped.
        _logPushOpened(target, 'cold_start');
      }
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was opened from a notification
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // NOT expected to fire while every send is data-only: FCM only
      // reports a tap on a notification it drew itself. Logged under
      // its own name so that if it ever DOES appear, it is a signal
      // that something started sending notification-payload messages
      // rather than a cold start being double counted.
      _handleNotificationTap(initialMessage, path: 'cold_start_fcm');
    }
  }

  // ── PUSH REPORTING ───────────────────────────────────────────────
  //
  // Logged by hand, because Firebase will not do it for us here.
  //
  // FCM auto-logs notification_receive / _open ONLY for messages that
  // carry a `notification` block, which it renders itself. Ours are
  // DATA-ONLY on purpose — the title and body travel in `data` and the
  // app renders them, which is what lets a notification carry
  // account_id and open on the right signed-in account. So the Firebase
  // console's own funnel will always read zero for us, however many go
  // out, and the only honest numbers are the ones logged here.
  //
  // Event names and parameters have to be registered as custom
  // dimensions in GA4 before they appear in reports; they are visible
  // in DebugView immediately either way.

  /// A notification was opened.
  ///
  /// [path] separates the ways that can happen, because they are
  /// different code paths and any of them can break alone:
  ///   fcm_tap    — tapped while the app sat in the background
  ///   local_tap  — tapped on a notification the app drew itself
  ///   cold_start — tapped while the app was not running
  static void _logPushOpened(NotificationTarget target, String path) {
    _logPush('dl_push_opened', {
      'notify_kind': target.notifyKind ?? 'unknown',
      'open_path': path,
    });
  }

  static void _logPush(String name, Map<String, String> params) {
    // Fire and forget, and never allowed to matter: an analytics
    // failure must not stop a notification opening what it points at.
    FirebaseAnalytics.instance
        .logEvent(name: name, parameters: params)
        .catchError((Object e) {
          debugPrint('[Push] analytics $name failed: $e');
        });
  }

  // Handle notification tap (both tap and action buttons)
  static void _onNotificationResponse(NotificationResponse response) {
    print('Local notification tapped: ${response.payload}');
    final target = NotificationTarget.fromPayload(response.payload);
    _logPushOpened(target, 'local_tap');
    openTarget(target);
  }

  /// Opens what a notification points at, on the account it belongs to.
  ///
  /// The account comes first: switching after navigating would rebuild the
  /// shell under the screen that had just been pushed onto it.
  static Future<void> openTarget(NotificationTarget target) async {
    if (target.isEmpty) {
      print('No URL in notification payload');
      return;
    }

    final nav = FirebaseMessagingService.navigatorKey?.currentState;
    if (nav == null) {
      _pendingTarget = target;
      print('Navigator not ready, queued: $target');
      return;
    }

    // Counted before the account check, not after.
    //
    // _ensureAccount returns false for a notification belonging to an
    // account signed out on this device, and that tap still happened —
    // somebody saw the notification and chose it. Counting only the
    // ones that opened successfully would quietly flatter every
    // notification's click-through rate.
    //
    // Not awaited: the tap should not wait on a statistics call. See
    // reportNotificationClick, which swallows its own failures.
    final notifyId = target.notifyId;
    if (notifyId != null) {
      NotificationsAPI.reportNotificationClick(notifyId);
    }

    final ready = await _ensureAccount(target);
    if (!ready) return;

    final url = target.url!;
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    final type = segments[0];
    final id = segments.length > 1 ? segments[1] : null;

    print('Navigating: type=$type, id=$id');

    switch (type) {
      // Straight into reviewing what was found, rather than to the
      // post — the notification's whole point is "come and check
      // these", and landing on the post leaves somebody hunting for
      // Edit tags in a menu.
      case 'post-tags':
        nav.pushNamed(
          AppRoutes.postTags,
          arguments: {'postId': int.tryParse(id ?? '')},
        );
        break;
      case 'post-view':
        nav.pushNamed(
          AppRoutes.postDetail,
          arguments: {
            'postId': int.tryParse(id ?? ''),
            'highlightCommentId': null,
          },
        );
        break;
      case 'profile-view':
        nav.pushNamed(
          AppRoutes.viewProfile,
          arguments: {'userId': id, 'username': ''},
        );
        break;
      case 'club-view':
        nav.pushNamed(AppRoutes.clubDetail, arguments: {'clubId': id});
        break;
      case 'gallery':
        // Carries ?photo= for a comment on one photo, so the viewer opens on
        // it with the gallery behind.
        final photo = int.tryParse(uri.queryParameters['photo'] ?? '');
        nav.pushNamed(
          AppRoutes.galleryDetail,
          arguments: {
            'galleryId': int.tryParse(id ?? ''),
            if (photo != null) 'photoId': photo,
          },
        );
        break;
      case 'gallery-tag':
        // A gallery tag request. The gallery id is in the URL for context,
        // but the screen lists every pending request, so it needs no argument.
        nav.push(
          MaterialPageRoute(builder: (_) => const GalleryTagRequestsScreen()),
        );
        break;
      case 'guess-view':
        // The result push lands on the leaderboard, because the result
        // is why it was sent. Anything else opens the puzzle.
        nav.pushNamed(
          AppRoutes.guess,
          arguments: {'tab': id == 'leaderboard' ? 1 : 0},
        );
        break;
      case 'vehicle-view':
        nav.pushNamed(AppRoutes.vehicleDetail, arguments: {'garageId': id});
        break;
      case 'vehicle-reminders':
        // Pushed directly rather than by name, like gallery-tag above:
        // RemindersScreen has no entry in AppRoutes, and adding one for
        // a single deep link is more indirection than it removes.
        //
        // This is where the MOT / insurance / service reminders open,
        // and until now nothing could reach it from outside the app —
        // the reminders bell on the vehicle page was the only warning
        // anybody got that one was due, and only if they went looking.
        if (id != null) {
          nav.push(
            MaterialPageRoute(builder: (_) => RemindersScreen(garageId: id)),
          );
        }
        break;
      case 'event-view':
        // AppRoutes.eventDetail takes the event rather than an id,
        // because every in-app caller already has the object from the
        // list it was drawn in. A notification does not — but it does
        // not need to fetch one either: EventDetailScreen hydrates
        // itself from event['id'] and event['site'] ?? ['country'], so
        // a stub with those two is enough and the screen keeps its own
        // loading and not-found states.
        //
        // ?country= matters. An event id only means something inside
        // its own region's blog and the same id exists in both, so
        // without the region this opens whichever event shares the
        // number. The server puts it in the url for that reason; see
        // dl_notify_event_url().
        nav.pushNamed(
          AppRoutes.eventDetail,
          arguments: {
            'event': {
              'id': id,
              'country': uri.queryParameters['country'] ?? 'GB',
            },
          },
        );
        break;
      default:
        print('Unknown deep link type: $type');
    }
  }

  /// Puts the right account in front before the route is pushed.
  ///
  /// Returns false when the notification should not be opened at all --
  /// which happens when it belongs to an account that has since been signed
  /// out on this device. Opening it anyway would show one account's
  /// notification under another's identity, and most of those requests
  /// would be refused by the server in any case.
  static Future<bool> _ensureAccount(NotificationTarget target) async {
    final context = FirebaseMessagingService.navigatorKey?.currentContext;
    if (context == null) return true;

    final AccountManager manager;
    try {
      manager = Provider.of<AccountManager>(context, listen: false);
    } catch (e) {
      // No provider above this navigator. Nothing to switch to, so carry on
      // rather than swallowing the tap.
      debugPrint('[Notifications] no AccountManager in scope: $e');
      return true;
    }

    final decision = resolveAccountSwitch(
      targetAccountId: target.accountId,
      signedInIds: manager.accounts.map((a) => a.user.id.toString()).toList(),
      activeId: manager.activeUser?.id.toString(),
    );

    switch (decision) {
      case AccountSwitch.none:
        return true;

      case AccountSwitch.notSignedIn:
        final name = target.accountName ?? 'that account';
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'That notification is for @$name. Sign in to open it.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;

      case AccountSwitch.switchTo:
        final index = manager.accounts.indexWhere(
          (a) => a.user.id.toString() == target.accountId,
        );
        if (index < 0) return true;

        await manager.switchAccount(index);

        // One frame is not enough: switching re-reads the account's data
        // and rebuilds the shell, and a route pushed into the middle of
        // that lands on a screen that is about to be replaced.
        await Future.delayed(const Duration(milliseconds: 400));

        return true;
    }
  }

  /// Call this once after your navigator is mounted (e.g. from your home
  /// screen's initState) to flush a deep link captured during cold start.
  static void flushPendingDeepLink() {
    final target = _pendingTarget;
    if (target != null) {
      _pendingTarget = null;
      openTarget(target);
    }
  }

  static Future<String?> getToken() async {
    try {
      await _messaging.setAutoInitEnabled(true);

      if (Platform.isIOS) {
        String? apnsToken;
        int retries = 0;
        while (apnsToken == null && retries < 10) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken == null) {
            retries++;
            debugPrint('⏳ Waiting for APNS token... attempt $retries');
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        if (apnsToken == null) {
          debugPrint('⚠️ APNS token unavailable after $retries retries');
          return null;
        }

        debugPrint('✅ APNS token: $apnsToken');
      }

      final token = await _messaging.getToken();
      debugPrint('✅ FCM token: $token');
      return token;
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  // Subscribe to token refresh
  static void onTokenRefresh(Function(String) callback) {
    _messaging.onTokenRefresh.listen(callback);
  }

  // Handle foreground messages
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📩 Foreground message received: ${message.data}');
    final data = message.data;

    // FOREGROUND ONLY, and named so. The background handler runs in its
    // own isolate with no Firebase initialised, so a delivery to a
    // backgrounded app is not counted here — which means this is a
    // floor on receives, not a total. Use the FCM delivery data for the
    // real denominator.
    _logPush('dl_push_received', {
      'notify_kind': data['notify_kind']?.toString() ?? 'unknown',
      'app_state': 'foreground',
    });
    final isGroup = data['is_group'] == 'true';
    final senderId = data['sender_id'] ?? '';
    final convId = data['conversation_id'] ?? '';
    final groupName = data['group_name'] ?? '';
    final senderName = data['title'] ?? 'Someone';
    final body = data['body'] ?? '';

    // ── Fetch sender avatar for largeIcon ──
    ByteArrayAndroidBitmap? largeIcon;

    // 1. Prefer the URL in the payload (always present from your server)
    String? imageUrl = data['sender_image'];

    // 2. Fall back to cache if payload didn't include one
    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = UserProfileCache.instance.getCached(senderId)?.imageUrl;
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          largeIcon = ByteArrayAndroidBitmap(response.bodyBytes);
        } else {
          debugPrint(
            '⚠️ Avatar fetch failed: ${response.statusCode} for $imageUrl',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Avatar fetch error: $e');
      }
    }

    // Which account this arrived for, shown only when there is more than
    // one signed in. With a single account the line is just noise, and
    // Instagram does the same -- the account only appears once there is
    // another one it could have been.
    final target = NotificationTarget.fromData(data);
    final accountLabel = _accountLabel(target);

    // ── Build messaging style ──
    final person = Person(
      name: senderName,
      icon: largeIcon != null ? ByteArrayAndroidIcon(largeIcon.data) : null,
      key: senderId,
    );

    final style = MessagingStyleInformation(
      // "you" — the recipient
      Person(name: 'You'),
      conversationTitle: isGroup ? groupName : null,
      groupConversation: isGroup,
      messages: [Message(body, DateTime.now(), person)],
    );

    await _localNotifications.show(
      // Use convId as notification ID so messages in same chat stack
      convId.hashCode,
      isGroup ? groupName : senderName,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Chat messages',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher', // small icon in status bar
          largeIcon: largeIcon, // profile pic in notification
          styleInformation: style, // WhatsApp-style grouping
          playSound: true,
          // Beside the app name in the shade. The account wins over the
          // group name here: the group is already the notification's title,
          // and which account it came to is the thing you cannot otherwise
          // tell.
          subText: accountLabel ?? (isGroup ? groupName : null),
          showWhen: true,
          // Grouped per conversation AND per account, so two accounts in
          // the same conversation do not collapse into one thread.
          groupKey: 'chat_${target.accountId ?? 'self'}_$convId',
          setAsGroupSummary: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          subtitle: accountLabel,
          threadIdentifier: 'chat_${target.accountId ?? 'self'}_$convId',
        ),
      ),
      // Carries the account as well as the url, so the tap can switch to
      // it. It used to be the bare url, which is why a tap always opened
      // under whichever account was already active.
      payload: target.encode(),
    );
  }

  /// `@username` when more than one account is signed in, else null.
  ///
  /// Returns null rather than an empty string so it can be handed straight
  /// to a nullable subText/subtitle.
  static String? _accountLabel(NotificationTarget target) {
    if (!FeatureFlags.notificationAccountLabel) return null;

    final name = target.accountName;
    if (name == null || name.isEmpty) return null;

    final context = FirebaseMessagingService.navigatorKey?.currentContext;
    if (context == null) return null;

    try {
      final manager = Provider.of<AccountManager>(context, listen: false);
      if (manager.accounts.length < 2) return null;
    } catch (_) {
      return null;
    }

    return '@$name';
  }

  static void _handleNotificationTap(
    RemoteMessage message, {
    String path = 'fcm_tap',
  }) {
    print('FCM notification tapped: ${message.data}');
    final target = NotificationTarget.fromData(message.data);
    _logPushOpened(target, path);
    openTarget(target);
  }

  // Subscribe to topic
  static Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }

  // Unsubscribe from topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from topic: $topic');
  }
}
