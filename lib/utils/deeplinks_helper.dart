import 'package:app_links/app_links.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../routes.dart';
import '../main.dart';
import '../api/qr_code_api.dart';
import '../widgets/qr_scanner_modal.dart';
import 'dart:async';

class DeepLinkHandler {
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Uri? _pendingDeepLink;
  bool _isAppInitialized = false;
  bool _isHandlingWarmStart = false;

  void initialize() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('🔗 [DeepLink] Received while app running: $uri');
        _isHandlingWarmStart = true;

        if (_isAppInitialized) {
          _handleDeepLink(uri);
        } else {
          _pendingDeepLink = uri;
        }
      },
      onError: (err) {
        debugPrint('❌ [DeepLink] Error: $err');
      },
    );

    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('🔗 [DeepLink] Initial link detected (cold start): $uri');
        _pendingDeepLink = uri;
        _isHandlingWarmStart = false;
      }
    });
  }

  bool get isHandlingWarmStart => _isHandlingWarmStart;

  void markAppAsInitialized() {
    _isAppInitialized = true;

    if (_pendingDeepLink != null) {
      debugPrint('🔗 [DeepLink] App initialized, handling pending link');
      final uri = _pendingDeepLink!;
      _pendingDeepLink = null;

      Future.delayed(const Duration(milliseconds: 500), () {
        _handleDeepLink(uri);
      });
    }

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

      // ⭐ Handle QR code: https://app.mydrivelife.com/?qr=0C013CE0
      if (params.containsKey('qr')) {
        final qrCodeParam = params['qr']!;
        debugPrint('🔗 [DeepLink] QR code param: $qrCodeParam');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in for QR');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        // Parse and verify QR code
        _handleQrCode(navContext, qrCodeParam, currentUser.id);
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

        navigatorKey.currentState?.pushNamed(
          AppRoutes.postDetail,
          arguments: {'postId': postId},
        );
        return;
      }

      // Handle password reset: https://app.mydrivelife.com/?reset=KEY
      if (params.containsKey('reset')) {
        final resetKey = params['reset']!;
        debugPrint('🔗 [DeepLink] Password reset key: $resetKey');

        navigatorKey.currentState?.pushNamed(
          AppRoutes.resetPassword,
          arguments: {'resetKey': resetKey},
        );
        return;
      }

      if (params.containsKey('dl-profile')) {
        final profileId = params['dl-profile']!;
        debugPrint('🔗 [DeepLink] Profile ID: $profileId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        navigatorKey.currentState?.pushNamed(
          AppRoutes.viewProfile,
          arguments: {'username': profileId},
        );
        return;
      }

      if (params.containsKey('dl-event')) {
        final eventId = params['dl-event']!;
        debugPrint('🔗 [DeepLink] Event ID: $eventId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        navigatorKey.currentState?.pushNamed(
          AppRoutes.eventDetail,
          arguments: {'event': {'id': eventId}},
        );
        return;
      }

      // email verification link: https://app.mydrivelife.com/?verifyToken=token_here
      if (params.containsKey('verifyToken')) {
        final token = params['verifyToken']!;
        debugPrint('🔗 [DeepLink] Email verification token: $token');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        // ✅ Pass the token as an argument to verify email screen
        navigatorKey.currentState?.pushNamed(
          AppRoutes.verifyEmail,
          arguments: {'token': token},
        );
        return;
      }
      debugPrint('⚠️ [DeepLink] No handler for URL: $uri');
    } catch (e) {
      debugPrint('❌ [DeepLink] Error: $e');
    }
  }

  // ⭐ Handle QR Code Deep Link
  Future<void> _handleQrCode(
    BuildContext context,
    String qrCodeParam,
    int userId,
  ) async {
    try {
      final theme = Provider.of<ThemeProvider>(context, listen: false);
      debugPrint('📱 [DeepLink] Verifying QR code: $qrCodeParam');

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            Center(child: CircularProgressIndicator(color: theme.primaryColor)),
      );

      // Verify the QR code
      final response = await QrCodeAPI.verifyScan(qrCodeParam, userId);

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        QrScannerService.handleScanResult(context, response);
      }
    } catch (e) {
      debugPrint('❌ [DeepLink] Error verifying QR code: $e');

      // Close loading dialog if still showing
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show scanner modal on error
      if (context.mounted) {
        _showQrScannerModal(context);
      }
    }
  }

  // Show QR Scanner Modal
  void _showQrScannerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QrScannerModal(),
    ).then((result) {
      if (result != null) {
        debugPrint('✅ [DeepLink] QR scanned from modal: $result');

        // Handle the scanned result
        final entityType = result['entity_type'];
        final entityId = result['entity_id'];

        if (entityType == 'profile') {
          navigatorKey.currentState?.pushNamed(
            AppRoutes.viewProfile,
            arguments: {'userId': entityId},
          );
        } else if (entityType == 'vehicle') {
          navigatorKey.currentState?.pushNamed(
            AppRoutes.vehicleDetail,
            arguments: {'garageId': entityId.toString()},
          );
        }
      }
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
