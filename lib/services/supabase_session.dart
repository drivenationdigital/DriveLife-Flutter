import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:flutter/foundation.dart';

/// Making sure Supabase knows who is signed in.
///
/// Supabase is initialised in main() with the publishable key, which is
/// the anonymous role. The user's own JWT — the one the WordPress bridge
/// mints, which PostgREST and the realtime socket both check against row
/// level security — is a separate step, and until now the only thing
/// that took it was ChatList._connect.
///
/// That was invisible while the inbox was a section of Home, because a
/// section is built at launch and stays built: opening the app
/// established the session as a side effect. Once the inbox became a
/// pushed screen, the session was only established if you went and
/// looked at it — so anything else that talks to Supabase was running as
/// anon, seeing nothing, and saying nothing about it.
///
/// Realtime is the clearest casualty: an anonymous socket is subscribed
/// and silent, which looks exactly like a message that never arrived.
class SupabaseSession {
  SupabaseSession._();

  /// Which account the current token belongs to.
  static int? _for;

  /// Whether a call is already running, so several screens asking at
  /// once cost one exchange.
  static Future<void>? _inFlight;

  /// Whether Supabase currently has a user token applied.
  static bool get isReady => _for != null;

  /// Give Supabase the active account's identity.
  ///
  /// Safe to call repeatedly and from anywhere: it returns immediately
  /// once the active account's token is already applied, and shares one
  /// exchange between concurrent callers.
  ///
  /// Returns false when there is nothing to apply — signed out, or the
  /// exchange failed.
  static Future<bool> ensure(AccountManager accounts) async {
    final account = accounts.activeAccount;

    if (account == null || account.token.isEmpty) {
      _for = null;
      return false;
    }

    final id = account.user.id;
    if (_for == id) return true;

    await (_inFlight ??= _establish(account.token, id));
    _inFlight = null;

    return _for == id;
  }

  /// Forget the current session, so the next [ensure] exchanges again.
  ///
  /// For a sign-out or an account switch: the token names a user, and
  /// carrying one account's into another's requests is worse than
  /// having none.
  static void clear() {
    _for = null;
  }

  static Future<void> _establish(String wordpressToken, int id) async {
    try {
      await SupabaseConfig.initialize();

      // The cached one first. It is good for an hour and costs a disk
      // read against a round trip to WordPress, which matters because
      // this now runs on every cold start rather than only when
      // somebody opens their messages.
      //
      // Only trusted when it belongs to this account — restoreSession
      // reads whatever was last stored, and after a switch that is the
      // previous user.
      final cachedId = await SupabaseTokenManager.currentUserId;

      if ('$id' == cachedId && await SupabaseTokenManager.restoreSession()) {
        _for = id;
        return;
      }

      await SupabaseTokenManager.fetchAndStore(wordpressToken);
      _for = id;
    } catch (e) {
      debugPrint('[SupabaseSession] could not establish: $e');
      _for = null;
    }
  }
}
