import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../routes.dart';
import '../main.dart';
import 'dart:async';

class DeepLinkHandler {
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Uri? _pendingDeepLink;
  bool _isAppInitialized = false;
  bool _isHandlingWarmStart = false; // ⭐ NEW

  void initialize() {
    // ⭐ Listen for deep links when app is already running (warm start)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('🔗 [DeepLink] Received while app running: $uri');

        // ⭐ Mark that we're handling a warm start link
        _isHandlingWarmStart = true;

        if (_isAppInitialized) {
          // App is already initialized, handle immediately
          _handleDeepLink(uri);
        } else {
          // App still initializing, store for later
          _pendingDeepLink = uri;
        }
      },
      onError: (err) {
        debugPrint('❌ [DeepLink] Error: $err');
      },
    );

    // ⭐ Get initial deep link (cold start)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('🔗 [DeepLink] Initial link detected (cold start): $uri');
        _pendingDeepLink = uri;
        _isHandlingWarmStart = false; // This is a cold start
      }
    });
  }

  // ⭐ Check if currently handling a warm start
  bool get isHandlingWarmStart => _isHandlingWarmStart;

  void markAppAsInitialized() {
    _isAppInitialized = true;

    // Handle pending deep link if any
    if (_pendingDeepLink != null) {
      debugPrint('🔗 [DeepLink] App initialized, handling pending link');
      final uri = _pendingDeepLink!;
      _pendingDeepLink = null;

      // Small delay to ensure navigation is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleDeepLink(uri);
      });
    }

    // Reset warm start flag after handling
    _isHandlingWarmStart = false;
  }

  void _handleDeepLink(Uri uri) {
    final navContext = navigatorKey.currentContext;
    if (navContext == null) {
      debugPrint('⚠️ [DeepLink] Navigator not ready');
      _pendingDeepLink = uri;
      return;
    }

    try {
      final userProvider = Provider.of<UserProvider>(navContext, listen: false);
      final currentUser = userProvider.user;

      debugPrint('👤 [DeepLink] User logged in: ${currentUser != null}');

      final params = uri.queryParameters;

      // Handle QR code
      if (params.containsKey('qr')) {
        final qrCode = params['qr']!;
        debugPrint('🔗 [DeepLink] QR code: $qrCode');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        navigatorKey.currentState?.pushNamed(
          '/qr-result',
          arguments: {'qrCode': qrCode},
        );
        return;
      }

      // Handle post share
      if (params.containsKey('dl-postv')) {
        final postId = params['dl-postv']!;
        debugPrint('🔗 [DeepLink] Post ID: $postId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        // Navigate to post detail
        navigatorKey.currentState?.pushNamed(
          AppRoutes.postDetail,
          arguments: {'postId': postId},
        );
        return;
      }

      debugPrint('⚠️ [DeepLink] No handler for URL: $uri');
    } catch (e) {
      debugPrint('❌ [DeepLink] Error: $e');
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
