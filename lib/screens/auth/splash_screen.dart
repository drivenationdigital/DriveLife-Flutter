import 'package:drivelife/utils/deeplinks_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../providers/user_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // ⭐ Check if this is a warm start deep link
    final isWarmStart = DeepLinkHandler().isHandlingWarmStart;

    if (isWarmStart) {
      debugPrint(
        '🔥 [SplashScreen] Warm start detected, marking initialized without navigation',
      );
      // Just mark as initialized, don't navigate anywhere
      await Future.delayed(const Duration(milliseconds: 300));
      DeepLinkHandler().markAppAsInitialized();
      return;
    }

    // ⭐ Cold start - normal flow
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      print('🚀 [SplashScreen] Checking login status...');

      final loggedIn = await _auth.isLoggedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ [SplashScreen] Auth check timed out');
          return false;
        },
      );

      print('✅ [SplashScreen] Logged in: $loggedIn');

      if (loggedIn && mounted) {
        print('🔄 [SplashScreen] Loading user data...');

        final userProvider = Provider.of<UserProvider>(context, listen: false);

        await userProvider.loadUser().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ [SplashScreen] User load timed out');
          },
        );

        print('✅ [SplashScreen] User loaded: ${userProvider.user != null}');

        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);

          Future.delayed(const Duration(milliseconds: 500), () {
            debugPrint('✅ [SplashScreen] Marking app as initialized');
            DeepLinkHandler().markAppAsInitialized();
          });
        }
      } else {
        print('📱 [SplashScreen] Not logged in, navigating to welcome');

        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.welcome);

          Future.delayed(const Duration(milliseconds: 500), () {
            DeepLinkHandler().markAppAsInitialized();
          });
        }
      }
    } catch (e) {
      print('❌ [SplashScreen] Error during init: $e');

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.welcome);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: Image.asset('assets/splash1.png')),
    );
  }
}
