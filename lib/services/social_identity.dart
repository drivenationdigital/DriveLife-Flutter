import 'dart:io' show Platform;

import 'package:drivelife/config/feature_flags.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// A verified-by-the-provider identity token, straight from the SDK.
///
/// This is the whole of what the app learns. The email in the token is
/// not read here and the name is passed through untouched — the server
/// checks the signature against Apple's or Google's published keys and
/// decides who this is, because anything this side of that check is
/// something an attacker could have typed.
class SocialToken {
  /// 'google' or 'apple', as the server's routes name them.
  final String provider;

  final String idToken;

  /// Apple only, and only ever on the FIRST authorisation for an Apple
  /// ID. See the note in [SocialIdentity.apple].
  final String? firstName;
  final String? lastName;

  /// Apple only: the single-use code the SERVER needs in order to
  /// revoke this app's Apple token.
  ///
  /// Not the same thing as [idToken]. The identity token proves who
  /// somebody is; revoking a grant at Apple's `/auth/revoke` needs a
  /// refresh token, and the only way to get one is to exchange this
  /// code. It expires in about five minutes, which is fine — it is
  /// taken at the moment of deletion and used immediately.
  ///
  /// Null for Google, which is revoked on the device instead. See
  /// [SocialIdentity.revokeGrant].
  final String? authorizationCode;

  const SocialToken({
    required this.provider,
    required this.idToken,
    this.firstName,
    this.lastName,
    this.authorizationCode,
  });
}

/// Getting an identity token out of Apple or Google.
///
/// ── WHY THIS IS NOT IN THE SIGN-IN BUTTONS ───────────────────────────
///
/// Signing in is not the only thing a provider token is for. Deleting an
/// account needs one too: an account created with Google has a random
/// password nobody has ever seen, so "type your password to confirm"
/// cannot work, and re-opening the provider's sheet is the equivalent
/// proof — the same proof Apple and Google themselves require before a
/// destructive change.
///
/// So the token-getting lives here, used by both, rather than being
/// private to a widget that draws two buttons.
class SocialIdentity {
  const SocialIdentity._();

  /// ── ANDROID RETURNS NO idToken WITHOUT THIS ────────────────────────
  ///
  /// The web client id (client_type 3 in google-services.json). Without
  /// a serverClientId the Android SDK hands back an access token and
  /// leaves `idToken` null — and an access token is not something the
  /// server can verify, so this would fail on Android while working
  /// perfectly on iOS.
  ///
  /// Passed explicitly rather than relying on the default_web_client_id
  /// resource the Gradle plugin generates, so it is visible here rather
  /// than being a side effect of a build step.
  ///
  /// On iOS this changes the token's `aud` to the web client id too —
  /// which is why BOTH ids are listed in DL_GOOGLE_CLIENT_IDS.
  static const String googleServerClientId =
      '602725811426-7s7m3vm5da463tbtcotfjdrvil4o0k39.apps.googleusercontent.com';

  /// ── iOS WOULD OTHERWISE READ A FILE THAT DOES NOT HAVE IT ──────────
  ///
  /// The iOS OAuth client (client_type 2 in google-services.json; the
  /// CLIENT_ID key in GoogleService-Info.plist).
  ///
  /// google_sign_in on iOS takes this from GoogleService-Info.plist
  /// when the constructor is given no clientId — and the plist in
  /// ios/Runner has no CLIENT_ID key at all, because it was downloaded
  /// from Firebase before the iOS OAuth client existed. Relying on it
  /// means sign-in fails on iOS while working on Android.
  ///
  /// Passed explicitly instead, for the same reason serverClientId is:
  /// the value is then visible here rather than depending on a
  /// downloaded file staying in step. It matches the REVERSED_CLIENT_ID
  /// URL scheme already in ios/Runner/Info.plist, which iOS also
  /// requires and which must keep matching this.
  static const String googleIosClientId =
      '602725811426-be5kvg7mlr0163bvt9qev4bspi3hn8rd.apps.googleusercontent.com';

  /// Whether the Apple button should be offered at all.
  ///
  /// Apple's platforms, and only once Apple's own console setup is
  /// done — see FeatureFlags.appleSignIn. Until the capability exists on
  /// the App ID the sheet throws the moment it opens.
  static bool get appleAvailable =>
      FeatureFlags.appleSignIn && (Platform.isIOS || Platform.isMacOS);

  /// One client, so a later [revokeGrant] acts on the very session that
  /// signed in rather than on a second object that may not see it.
  ///
  /// Scope is `email` and `profile`, and nothing else.
  ///
  /// ── WHY `profile` IS HERE ──────────────────────────────────────────
  ///
  /// Without it Google's identity token carries only `sub`, `email` and
  /// `email_verified` — no name — which is why accounts created through
  /// Google arrived with blank first and last names. `profile` adds
  /// `given_name`, `family_name`, `name` and `picture` to the SAME
  /// signed token, so the server reads them from something Google has
  /// signed rather than from anything this app could have typed.
  ///
  /// It is one of Google's two basic scopes: no extra consent screen,
  /// no verification review.
  ///
  /// Worth being precise about what neither scope grants: no Gmail, no
  /// Drive, no contacts, no writes of any kind. The only thing this app
  /// can ever obtain from Google is an identity token — a read-only
  /// assertion of "this is Google user <sub>". There is no credential
  /// here that could alter or delete a Google account.
  static GoogleSignIn? _googleClient;

  static GoogleSignIn get _google =>
      _googleClient ??= GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: googleServerClientId,
        // Apple platforms only. The Android SDK takes its client from
        // google-services.json at build time and ignores this, so
        // passing it there would be noise suggesting it mattered.
        clientId: (Platform.isIOS || Platform.isMacOS)
            ? googleIosClientId
            : null,
      );

  /// Opens Google's sheet. Null means the person cancelled.
  ///
  /// Throws [SocialIdentityException] if Google returns without a
  /// usable token, which is a real failure rather than a cancellation.
  static Future<SocialToken?> google() async {
    final google = _google;

    // Signed out first, so the account chooser always appears. Without
    // it the second sign-in silently reuses the first account, which
    // looks broken to anybody with two — and for a delete confirmation
    // it would be no confirmation at all.
    await google.signOut();

    final account = await google.signIn();

    // google_sign_in reports a cancel by RETURNING NULL rather than
    // throwing, so this is the cancellation path and must stay
    // distinguishable from a failure.
    if (account == null) return null;

    final auth = await account.authentication;
    final token = auth.idToken;

    if (token == null || token.isEmpty) {
      throw const SocialIdentityException(
        'Google did not return a sign-in token.',
      );
    }

    return SocialToken(provider: 'google', idToken: token);
  }

  /// Opens Apple's sheet. Null means the person cancelled.
  static Future<SocialToken?> apple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final token = credential.identityToken;

    if (token == null || token.isEmpty) {
      throw const SocialIdentityException(
        'Apple did not return a sign-in token.',
      );
    }

    // ── THE NAME TRAVELS IN THE BODY, NOT THE TOKEN ──────────────────
    //
    // Apple sends it exactly once — on the very first authorisation for
    // this Apple ID and this app — and never again, not even if the app
    // is deleted and reinstalled. If it is not captured here it is gone
    // for good, which is why it is carried even though the server
    // trusts nothing else that did not come signed.
    return SocialToken(
      provider: 'apple',
      idToken: token,
      firstName: credential.givenName,
      lastName: credential.familyName,
      // Carried so the server can revoke the grant on deletion, which
      // App Store guideline 5.1.1(v) requires. Useless for anything
      // else — it is single-use and expires in minutes.
      authorizationCode: credential.authorizationCode,
    );
  }

  /// Gives this app's access grant back, AFTER the DriveLife account is
  /// already gone.
  ///
  /// ── WHAT THIS DOES NOT DO ──────────────────────────────────────────
  ///
  /// It does not delete, disable, or modify anybody's Google or Apple
  /// account, and it could not: revoking a grant is the same action as
  /// the person opening their Google settings and pressing "Remove
  /// access" next to DriveLife. Their provider account, its email, its
  /// password and everything in it are untouched. The only thing that
  /// changes is that DriveLife stops being listed as an app with
  /// access — which is the honest end state once their DriveLife
  /// account no longer exists.
  ///
  /// ── WHY IT IS BEST-EFFORT, AND WHY IT RUNS LAST ────────────────────
  ///
  /// The WordPress deletion is the real outcome and it has already
  /// succeeded by the time this runs. So this never throws and never
  /// reports failure: a revoke that fails must not make a completed
  /// deletion look broken, and must never be retried in a way that
  /// could re-run the delete.
  ///
  /// Running it BEFORE the deletion would be the unsafe order — a
  /// revoke followed by a failed delete would leave somebody with a
  /// live account whose sign-in they had just given away.
  static Future<void> revokeGrant(String provider) async {
    // Apple cannot be revoked from the device at all. It needs a signed
    // client secret, so the server does it with the authorizationCode —
    // see dl_social_apple_revoke() in auth-social.php.
    if (provider != 'google') return;

    try {
      // disconnect(), NOT signOut(). signOut only clears the session
      // this app holds; disconnect hands the grant back.
      await _google.disconnect();
    } catch (e) {
      // Swallowed on purpose. Their DriveLife account is already
      // deleted; the grant being left listed in their Google settings
      // is untidy, not harmful, and they can remove it themselves.
      debugPrint('[Social] google disconnect failed (harmless): $e');
    }
  }

  /// Both sheets, behind their provider name.
  static Future<SocialToken?> forProvider(String provider) {
    switch (provider) {
      case 'apple':
        return apple();
      case 'google':
        return google();
      default:
        throw SocialIdentityException('Unknown sign-in provider "$provider".');
    }
  }

  /// A cancellation, which is NOT a failure.
  ///
  /// Telling somebody their sign-in failed because they changed their
  /// mind is just wrong, so every caller checks this before showing an
  /// error.
  static bool isCancellation(Object e) {
    if (e is SignInWithAppleAuthorizationException) {
      return e.code == AuthorizationErrorCode.canceled;
    }

    // google_sign_in cancels by returning null rather than throwing, so
    // this is for the platform exceptions that still describe one.
    final text = e.toString().toLowerCase();

    return text.contains('cancel') || text.contains('aborted');
  }

  /// How a provider is named to somebody reading the screen.
  static String label(String provider) =>
      provider == 'apple' ? 'Apple' : 'Google';
}

class SocialIdentityException implements Exception {
  final String message;

  const SocialIdentityException(this.message);

  @override
  String toString() => message;
}
