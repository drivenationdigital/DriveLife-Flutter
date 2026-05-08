import 'dart:io';

import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  print('📩 Background message received: $data');

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
        subText: isChatMessage && isGroup ? groupName : null,
        showWhen: true,
        groupKey: isChatMessage ? 'chat_$convId' : null,
        setAsGroupSummary: false,
      ),
    ),
    payload: data['url'] ?? '',
  );
}

class FirebaseMessagingService {
  static GlobalKey<NavigatorState>? navigatorKey;
  static String? _pendingDeepLink; // for cold-start before navigator is ready

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
        _pendingDeepLink = payload;
        print('🚀 Cold-start from local notification, queued: $payload');
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
      _handleNotificationTap(initialMessage);
    }
  }

  // Handle notification tap (both tap and action buttons)
  static void _onNotificationResponse(NotificationResponse response) {
    print('Local notification tapped: ${response.payload}');
    _navigateToUrl(response.payload);
  }

  static void _navigateToUrl(String? url) {
    if (url == null || url.isEmpty) {
      print('No URL in notification payload');
      return;
    }

    print('_navigateToUrl called with: $url');
    print(
      'FirebaseMessagingService.navigatorKey: ${FirebaseMessagingService.navigatorKey}',
    );
    print(
      'currentState: ${FirebaseMessagingService.navigatorKey?.currentState}',
    );

    final nav = FirebaseMessagingService.navigatorKey?.currentState;
    if (nav == null) {
      _pendingDeepLink = url;
      print('Navigator not ready, queued: $url');
      return;
    }

    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    final type = segments[0];
    final id = segments.length > 1 ? segments[1] : null;

    print('Navigating: type=$type, id=$id');

    switch (type) {
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
      default:
        print('Unknown deep link type: $type');
    }
  }

  /// Call this once after your navigator is mounted (e.g. from your home
  /// screen's initState) to flush a deep link captured during cold start.
  static void flushPendingDeepLink() {
    if (_pendingDeepLink != null) {
      final url = _pendingDeepLink;
      _pendingDeepLink = null;
      _navigateToUrl(url);
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

    // ── Build messaging style ──
    final person = Person(
      name: senderName,
      icon: largeIcon != null
          ? ByteArrayAndroidIcon(largeIcon.data) 
          : null,
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
          // ← add these for better grouped view
          subText: isGroup ? groupName : null,
          showWhen: true,
          groupKey: 'chat_$convId', // groups same-convo notifications
          setAsGroupSummary: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      // payload: 'chat:$convId',
      payload: data['url'] ?? '',
    );
  }

  static void _handleNotificationTap(RemoteMessage message) {
    print('FCM notification tapped: ${message.data}');
    _navigateToUrl(message.data['url']);
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
