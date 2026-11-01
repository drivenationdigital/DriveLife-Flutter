import 'package:drivelife/utils/deeplinks_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  /// How long the flag takes to paint in, and how long it sits finished
  /// before we move on. Both come from the supplied SVG: its `<animate>`
  /// ran the clip height 0 → full over the first 62% of a 3.2s cycle and
  /// held for the rest. Shortened here, because a splash that outstays
  /// the work it is covering stops reading as a splash and starts
  /// reading as a hang.
  static const Duration _reveal = Duration(milliseconds: 1250);
  static const Duration _hold = Duration(milliseconds: 350);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _reveal,
  )..forward();

  /// The easing from the SVG's keySplines (0.35 0 0.2 1): slow to start,
  /// quick through the middle, settling rather than stopping.
  late final Animation<double> _paint = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.35, 0, 0.2, 1),
  );

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

    // ⭐ Cold start - normal flow.
    //
    // Long enough for the flag to finish painting in. A reveal cut off
    // halfway by a fast auth check looks like a glitch, not a splash —
    // and the auth check below usually resolves well inside this, so in
    // practice this is the whole cost, not an addition to it.
    await Future.delayed(_reveal + _hold);

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
    final width = MediaQuery.of(context).size.width;

    // Proportional, but capped: on a tablet a logo at 46% of the width
    // is a billboard.
    final logoWidth = (width * 0.46).clamp(140.0, 260.0).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light icons: the only screen in the app with a near-black
      // background, so it has to say so itself.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _ink,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _ink,
        body: Center(
          child: SizedBox(
            width: logoWidth,
            // The flag's own aspect ratio, from the SVG viewBox. Fixing
            // the height here is what gives the clip something stable to
            // cut against — against an intrinsic height the reveal would
            // be clipping a box that is itself still being measured.
            height: logoWidth * (170.4 / 210.4),
            child: AnimatedBuilder(
              animation: _paint,
              builder: (context, child) =>
                  ClipRect(clipper: _TopDownReveal(_paint.value), child: child),
              child: SvgPicture.asset(
                'assets/intro-logo.svg',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const Color _ink = Color(0xFF151515);
}

/// Uncovers its child from the top down, which is the reveal the
/// supplied SVG described — the flag paints on as if being drawn,
/// rather than fading or scaling in.
class _TopDownReveal extends CustomClipper<Rect> {
  const _TopDownReveal(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height * progress);

  @override
  bool shouldReclip(_TopDownReveal oldClipper) =>
      oldClipper.progress != progress;
}
