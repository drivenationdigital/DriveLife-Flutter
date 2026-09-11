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

  /// The gallery id in a link, or null if it is not a gallery link.
  ///
  /// Accepts both shapes the app uses: `/gallery/123` and `?dl-gallery=123`.
  /// Pulled out as a pure function because deep links are otherwise only
  /// testable by installing the app and tapping a link.
  static String? galleryIdFrom(Uri uri) {
    final param = uri.queryParameters['dl-gallery'];
    if (param != null && param.trim().isNotEmpty) return param.trim();

    final segments = uri.pathSegments;
    if (segments.length != 2 || segments[0] != 'gallery') return null;

    // A path can carry trailing params when the link was built by hand.
    final id = segments[1].split('&').first.trim();
    return id.isEmpty ? null : id;
  }

  /// The photo a gallery link points at, if it names one.
  ///
  /// `/gallery/12?photo=345` opens the gallery AND that photo, so closing the
  /// photo lands on the gallery rather than wherever the recipient started.
  static String? galleryPhotoIdFrom(Uri uri) {
    final photo = uri.queryParameters['photo'];
    if (photo == null) return null;

    final id = photo.trim();
    return id.isEmpty ? null : id;
  }

  /// Folds a custom-scheme link into the https shape every branch below reads.
  ///
  /// `drivelife://vehicle/123` and `https://app.mydrivelife.com/vehicle/123`
  /// mean the same thing, but they parse differently: with a custom scheme the
  /// entity type lands in `host` and only the id is in `pathSegments`, so a
  /// handler matching `pathSegments[0] == 'vehicle'` never fires.
  ///
  /// That is why the website's "Open in app" button did nothing. It emits the
  /// custom scheme for every entity — venue, club, post, profile — so this was
  /// never about one page.
  Uri _normalise(Uri uri) {
    if (uri.scheme == 'http' || uri.scheme == 'https') return uri;
    if (uri.host.isEmpty) return uri;

    return uri.replace(
      scheme: 'https',
      host: 'app.mydrivelife.com',
      pathSegments: [uri.host, ...uri.pathSegments],
    );
  }

  void _handleDeepLink(Uri incoming) {
    final uri = _normalise(incoming);

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

      // Handle post share if dl-postv OR /post/:id is present: https://app.mydrivelife.com/?dl-postv=123 OR https://app.mydrivelife.com/post/123
      if (params.containsKey('dl-postv') ||
          (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'post')) {
        var uriID =
            (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'post')
            ? uri.pathSegments[1]
            : null;
        uriID = uriID
            ?.split('&')
            .first; // Handle potential extra params in path
        final postId =
            params['dl-postv'] ?? uriID; // Handle potential extra params
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

      // EVENT — extend existing handler to also catch /event/:id
      if (params.containsKey('dl-event') ||
          (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'event')) {
        var uriID =
            (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'event')
            ? uri.pathSegments[1]
            : null;
        uriID = uriID?.split('&').first;
        final eventId = params['dl-event'] ?? uriID;
        debugPrint('🔗 [DeepLink] Event ID: $eventId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        navigatorKey.currentState?.pushNamed(
          AppRoutes.eventDetail,
          arguments: {
            'event': {'id': eventId},
          },
        );
        return;
      }

      // CLUB — new, /club/:id or ?dl-club=:id
      if (params.containsKey('dl-club') ||
          (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'club')) {
        var uriID =
            (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'club')
            ? uri.pathSegments[1]
            : null;
        uriID = uriID?.split('&').first;
        final clubId = params['dl-club'] ?? uriID;
        debugPrint('🔗 [DeepLink] Group ID: $clubId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        navigatorKey.currentState?.pushNamed(
          AppRoutes.clubDetail, // ← confirm route name
          arguments: {'clubId': clubId}, // ← confirm arg shape
        );
        return;
      }

      // VENUE — new, /venue/:id or ?dl-venue=:id
      if (params.containsKey('dl-venue') ||
          (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'venue')) {
        var uriID =
            (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'venue')
            ? uri.pathSegments[1]
            : null;
        uriID = uriID?.split('&').first;
        final venueId = params['dl-venue'] ?? uriID;
        debugPrint('🔗 [DeepLink] Venue ID: $venueId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        navigatorKey.currentState?.pushNamed(
          AppRoutes.venueDetails, // ← confirm route name
          arguments: {'venueId': venueId}, // ← confirm arg shape
        );
        return;
      }

      // GALLERY — /gallery/:id or ?dl-gallery=:id
      final galleryId = galleryIdFrom(uri);
      if (galleryId != null) {
        debugPrint('🔗 [DeepLink] Gallery ID: $galleryId');

        if (currentUser == null) {
          debugPrint('⚠️ [DeepLink] User not logged in');
          navigatorKey.currentState?.pushNamed(AppRoutes.login);
          return;
        }

        final photoId = galleryPhotoIdFrom(uri);

        navigatorKey.currentState?.pushNamed(
          AppRoutes.galleryDetail,
          // The title is unknown from a link — the screen fetches the gallery
          // and fills its own header in.
          arguments: {
            'galleryId': galleryId,
            if (photoId != null) 'photoId': photoId,
          },
        );
        return;
      }

      // VEHICLE — /vehicle/:garageId, the link the share button sends.
      //
      // Unlike the others this one does not require a session. A shared car is
      // the most likely thing to reach somebody who has never opened the app,
      // which is the whole point of sharing it — the screen itself decides
      // what a signed-out visitor may see.
      if (params.containsKey('dl-vehicle') ||
          (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'vehicle')) {
        final fromPath = uri.pathSegments.length == 2
            ? uri.pathSegments[1].split('&').first.trim()
            : null;

        final garageId = params['dl-vehicle'] ?? fromPath;
        debugPrint('🔗 [DeepLink] Vehicle ID: $garageId');

        if (garageId == null || garageId.isEmpty) return;

        navigatorKey.currentState?.pushNamed(
          AppRoutes.vehicleDetail,
          arguments: {'garageId': garageId},
        );
        return;
      }

      // PROFILE — extend existing handler to also catch /user/:username
      if (params.containsKey('dl-profile') ||
          (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'profile')) {
        var uriUsername =
            (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'user')
            ? uri.pathSegments[1]
            : null;
        uriUsername = uriUsername?.split('&').first;
        final profileId = params['dl-profile'] ?? uriUsername;
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
