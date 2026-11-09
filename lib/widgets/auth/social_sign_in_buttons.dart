import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/services/social_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// "Continue with Apple" and "Continue with Google".
///
/// ── NOTHING IS DECIDED HERE ──────────────────────────────────────────
///
/// Both buttons do the same thing: open the provider's own sheet, take
/// the identity token it returns, and hand it to the server. The server
/// verifies it against Apple's or Google's published keys and answers
/// with the app's own token. This widget never learns who anybody is,
/// and never sees an email it could be fooled by.
///
/// ── THE PAIR IS NOT OPTIONAL ─────────────────────────────────────────
///
/// App Store guideline 4.8: an app offering a third-party sign-in must
/// also offer Sign in with Apple. So Google never appears on iOS
/// without Apple beside it — which is why both come from one flag
/// rather than two, and why the Apple button is unconditional on iOS.
///
/// Apple's button is hidden on Android, where it would be a web
/// redirect for no benefit.
class SocialSignInButtons extends StatefulWidget {
  /// Called after a successful sign-in, so the screen can navigate.
  ///
  /// Handed the whole result rather than nothing, because where to go
  /// next depends on it: a brand-new account has answered none of the
  /// signup questions and belongs in those, not on the home feed.
  final ValueChanged<LoginResult> onSignedIn;

  const SocialSignInButtons({super.key, required this.onSignedIn});

  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  final AuthService _auth = AuthService();

  /// Which provider is mid-flight, so only one spinner shows and a
  /// second tap cannot open a second sheet.
  String? _busy;

  /// Apple's platforms, and only once Apple's own setup is done.
  ///
  /// FeatureFlags.appleSignIn is the temporary half — see the warning
  /// on it. Until the capability exists on the App ID, the sheet throws
  /// as soon as it opens, and a button that does that is worse than no
  /// button.
  bool get _showApple => SocialIdentity.appleAvailable;

  Future<void> _run(String provider, Future<LoginResult?> Function() go) async {
    if (_busy != null) return;

    setState(() => _busy = provider);

    LoginResult? result;

    try {
      result = await go();
    } catch (e) {
      debugPrint('[Social] $provider threw: $e');

      // A cancellation is not a failure. Both SDKs report it by
      // throwing, and telling somebody their sign-in failed because
      // they changed their mind is just wrong.
      if (SocialIdentity.isCancellation(e)) {
        if (mounted) setState(() => _busy = null);
        return;
      }

      result = LoginResult(LoginOutcome.networkError, e.toString());
    }

    if (!mounted) return;

    setState(() => _busy = null);

    // Cancelled. Nothing happened, so nothing is said — a snackbar
    // here would be telling somebody off for changing their mind.
    if (result == null) return;

    if (result.outcome == LoginOutcome.success) {
      widget.onSignedIn(result);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.detail ?? 'Could not sign in. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// The provider sheet, then the server.
  ///
  /// Both buttons run through here: the only difference between them is
  /// which sheet opens, and [SocialIdentity] owns that. Null means the
  /// person cancelled, which travels all the way back up so nothing is
  /// said about it.
  Future<LoginResult?> _signIn(String provider) async {
    final token = await SocialIdentity.forProvider(provider);

    if (token == null) return null;

    return _auth.loginWithProvider(
      provider: token.provider,
      idToken: token.idToken,
      firstName: token.firstName,
      lastName: token.lastName,
      // Apple only, and the ONLY moment it can be used: the code is
      // single-use and expires in minutes. The server trades it for a
      // refresh token so a later disconnect can hand the grant back
      // without re-opening Apple's sheet.
      authorizationCode: token.authorizationCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.socialSignIn) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE0E0E0))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFE0E0E0))),
          ],
        ),
        const SizedBox(height: 18),

        if (_showApple) ...[
          _button(
            label: 'Continue with Apple',
            // Apple's guidelines: their mark, their wording, black on
            // white or white on black. A custom icon fails review.
            icon: const Icon(Icons.apple, size: 22, color: Colors.white),
            background: Colors.black,
            foreground: Colors.white,
            busy: _busy == 'apple',
            onTap: () => _run('apple', () => _signIn('apple')),
          ),
          const SizedBox(height: 10),
        ],

        _button(
          label: 'Continue with Google',
          icon: _googleMark(),
          background: Colors.white,
          foreground: const Color(0xFF1F1F1F),
          border: const Color(0xFFDADCE0),
          busy: _busy == 'google',
          onTap: () => _run('google', () => _signIn('google')),
        ),
      ],
    );
  }

  /// Google's own four-colour mark.
  ///
  /// Their branding guidelines require the real thing, unaltered, and
  /// forbid recolouring or redrawing it — so this is their published
  /// geometry shipped as an asset rather than anything approximated
  /// here. See assets/google-g.svg.
  ///
  /// 20px against a 50px button, which keeps Google's own 18-against-40
  /// ratio. Sized explicitly rather than left to the SVG's own 48px, or
  /// it would fill the button.
  Widget _googleMark() => SvgPicture.asset(
    'assets/google-g.svg',
    width: 20,
    height: 20,
    // No colorFilter, deliberately: tinting it would flatten four
    // brand colours into one and is exactly what the guidelines
    // prohibit.
  );

  Widget _button({
    required String label,
    required Widget icon,
    required Color background,
    required Color foreground,
    required bool busy,
    required VoidCallback onTap,
    Color? border,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        // Disabled while ANY provider is running, not just this one:
        // two sheets at once is a crash on both platforms.
        onPressed: _busy != null ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: border != null
                ? BorderSide(color: border)
                : BorderSide.none,
          ),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
