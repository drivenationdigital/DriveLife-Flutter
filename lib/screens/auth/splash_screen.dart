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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

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
            // Continue anyway - user can try again from home
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

      // On error, go to welcome screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.welcome);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _opacity,
        child: Center(child: Image.asset('assets/splash-dark.png')),
      ),
    );
  }
}
