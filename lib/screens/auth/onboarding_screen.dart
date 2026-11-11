import 'package:flutter/gestures.dart';
import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/widgets/auth/privacy_modal.dart';
import 'package:drivelife/widgets/auth/social_sign_in_buttons.dart';
import 'package:drivelife/widgets/auth/terms_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../routes.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late VideoPlayerController _controller;
  bool _isVideoInitialized = false;

  /// Held rather than built inside build().
  ///
  /// A TapGestureRecognizer has to be disposed, and one created in
  /// build() is leaked on every repaint -- which here is every frame of
  /// the background video.
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();

    _termsTap = TapGestureRecognizer()
      ..onTap = () => _showSheet(const TermsModal());
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _showSheet(const PrivacyModal());

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.asset('assets/video01.mp4')
      ..initialize()
          .then((_) {
            if (mounted) {
              setState(() {
                _isVideoInitialized = true;
              });
              _controller.setLooping(true);
              _controller.setVolume(0); // Muted
              _controller.play();
            }
          })
          .catchError((error) {
            print('Error initializing video: $error');
            // Video failed to load, show fallback gradient
            if (mounted) {
              setState(() {
                _isVideoInitialized = false;
              });
            }
          });
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: _isVideoInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller.value.size.width,
                      height: _controller.value.size.height,
                      child: VideoPlayer(_controller),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1a1a1a), Color(0xFF000000)],
                      ),
                    ),
                  ),
          ),

          // Black Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The provider row added roughly 150px of fixed height
                // to a column that was already close to full on a small
                // phone. Spacer gives way first, and once it is at zero
                // the next pixel overflows -- so the logo gives way too
                // rather than the layout breaking.
                //
                // 700 is about an iPhone SE or a short Android: above
                // it nothing changes and the screen looks as it always
                // has.
                final tight = constraints.maxHeight < 700;
                final logoHeight = tight ? 110.0 : 180.0;
                final devicePixelRatio = MediaQuery.of(
                  context,
                ).devicePixelRatio;

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: tight ? 20 : 40,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: tight ? 16 : 54),

                      // Logo.
                      //
                      // Bounded on BOTH axes, with contain, rather than
                      // given a height alone. The artwork is 16:9, and
                      // at 180 high that is 320 wide -- more than a
                      // 360dp phone has between the 32pt margins, so a
                      // height-only Image would overflow sideways.
                      // Letting it shrink to whichever axis binds keeps
                      // that true whatever the next logo's shape is.
                      //
                      // cacheHeight because the source is 4920x2768:
                      // decoded at full size that is ~54MB of bitmap
                      // for something drawn 180pt tall. This decodes it
                      // at roughly the size it is actually painted.
                      SizedBox(
                        height: logoHeight,
                        width: double.infinity,
                        child: Image.asset(
                          'assets/landing-logo.png',
                          fit: BoxFit.contain,
                          cacheHeight: (logoHeight * devicePixelRatio).round(),
                        ),
                      ),

                      const Spacer(),

                      // Buttons
                      Column(
                        children: [
                          // Sign Up Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  AppRoutes.register,
                                  (route) => false,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'SIGN UP',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Log In Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  AppRoutes.login,
                                  (route) => false,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'LOG IN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          // Apple and Google.
                          //
                          // One tap, and which of the two things it does is
                          // never a question anybody is asked: the server
                          // decides by whether the provider's identity
                          // already belongs to an account. An existing user
                          // lands home, a new one lands in the signup
                          // questions. See continueAfterSocialSignIn, which
                          // the login screen shares.
                          //
                          // Draws nothing at all while
                          // FeatureFlags.socialSignIn is false, so the
                          // divider cannot strand itself above an empty
                          // space.
                          SocialSignInButtons(
                            layout: SocialButtonsLayout.compact,
                            dividerLabel: 'or continue with',
                            onSignedIn: (result) {
                              if (!mounted) return;

                              continueAfterSocialSignIn(context, result);
                            },
                          ),

                          if (FeatureFlags.socialSignIn) ...[
                            const SizedBox(height: 18),
                            _legalLine(),
                          ],
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The consent line under the provider buttons.
  ///
  /// ── WHY IT IS HERE AND NOT ON THE SIGNUP FORM ────────────────────
  ///
  /// The password signup asks for Terms and Privacy as two tick boxes
  /// in step one. A provider sign-in never goes through step one -- the
  /// account already exists by the time we know anything -- so without
  /// this, somebody could create an account having been shown neither.
  ///
  /// Both open the same modals the signup uses, so there is one copy of
  /// the wording rather than a second that drifts.
  Widget _legalLine() {
    const link = TextStyle(
      color: Colors.white,
      fontSize: 11.5,
      height: 1.4,
      decoration: TextDecoration.underline,
      decorationColor: Colors.white54,
    );

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 11.5,
          height: 1.4,
        ),
        children: [
          const TextSpan(text: 'By continuing you agree to our '),
          TextSpan(text: 'Terms', style: link, recognizer: _termsTap),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: link,
            recognizer: _privacyTap,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  void _showSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => child,
    );
  }
}
