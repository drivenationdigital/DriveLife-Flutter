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

        print('✅ [SplashScreen] User loaded, navigating to home');

        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      } else {
        print('📱 [SplashScreen] Not logged in, navigating to welcome');

        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.welcome);
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
