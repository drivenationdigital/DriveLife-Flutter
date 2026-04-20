import 'dart:io';

import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

// Top-level function for background messages
// @pragma('vm:entry-point')
// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   print("Handling background message: ${message.messageId}");
// }
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  print('📩 Background message received: ${message.data}');
  final isGroup = data['is_group'] == 'true';
  final senderId = data['sender_id'] ?? '';
  final convId = data['conversation_id'] ?? '';
  final groupName = data['group_name'] ?? '';
  final title = message.data['title'] ?? 'New message';
  final body = message.data['body'] ?? '';

  // Init local notifications
  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings),
  );

  // Try to fetch sender avatar
  ByteArrayAndroidBitmap? largeIcon;
  final senderImageUrl = data['sender_image'] ?? '';
  if (senderImageUrl.isNotEmpty) {
    try {
      final response = await http.get(Uri.parse(senderImageUrl));
      largeIcon = ByteArrayAndroidBitmap(response.bodyBytes);
    } catch (_) {}
  }

  final person = Person(
    name: title,
    icon: largeIcon != null ? ByteArrayAndroidIcon(largeIcon!.data) : null,
    key: senderId,
  );

  final style = MessagingStyleInformation(
    const Person(name: 'You'),
    conversationTitle: isGroup ? groupName : null,
    groupConversation: isGroup,
    messages: [Message(body, DateTime.now(), person)],
  );

  await localNotifications.show(
    convId.hashCode,
    isGroup ? groupName : title,
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
         // ← add these for better grouped view
        subText: isGroup ? groupName : null,
        showWhen: true,
        groupKey: 'chat_$convId', // groups same-convo notifications
        setAsGroupSummary: false,
      ),
    ),
    payload: 'chat:$convId',
  );
}

class FirebaseMessagingService {
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
    print('Notification tapped: ${response.payload}');

    // Check if it's an action button or just a tap
    if (response.actionId == 'view_post' || response.actionId == null) {
      // Parse payload
      if (response.payload != null && response.payload!.startsWith('post:')) {
        final postId = response.payload!.replaceFirst('post:', '');
        print('Navigate to post: $postId');

        // Call the callback if set
        onNotificationTapped?.call(postId);
      }
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
    final profile = UserProfileCache.instance.getCached(senderId);
    if (profile?.imageUrl != null) {
      try {
        final response = await http.get(Uri.parse(profile!.imageUrl!));
        final imageData = response.bodyBytes;
        largeIcon = ByteArrayAndroidBitmap(imageData);
      } catch (_) {}
    }

    // ── Build messaging style ──
    final person = Person(
      name: senderName,
      icon: largeIcon != null
          ? ByteArrayAndroidIcon(largeIcon!.data) // ← wrong, use this instead:
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
      payload: 'chat:$convId',
    );
  }

  // Handle notification tap (Firebase messages)
  static void _handleNotificationTap(RemoteMessage message) {
    print('Notification tapped: ${message.messageId}');
    print(message.data);

    // Navigate based on notification data
    if (message.data.containsKey('type')) {
      String type = message.data['type'];

      // Add your navigation logic here
      switch (type) {
        case 'post':
          // Navigate to post detail
          String? postId = message.data['post_id'];
          print('Navigate to post: $postId');
          onNotificationTapped?.call(postId); // Add this line
          break;
        case 'profile':
          // Navigate to profile
          String? userId = message.data['user_id'];
          print('Navigate to profile: $userId');
          onNotificationTapped?.call(userId); // Add this line
          break;
        case 'comment':
          // Navigate to post with comments
          String? postId = message.data['post_id'];
          print('Navigate to post comments: $postId');
          onNotificationTapped?.call(postId); // Add this line
          break;
        case 'chat_message':
          final convId = message.data['conversation_id'];
          print('Navigate to chat: $convId');
          onNotificationTapped?.call('chat:$convId');
          break;
        default:
          print('Unknown notification type: $type');
      }
    }
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
