import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/api/social_api.dart';
import 'package:drivelife/models/user_model.dart';
import 'package:drivelife/services/social_identity.dart';
import 'package:drivelife/widgets/auth/privacy_modal.dart';
import 'package:drivelife/widgets/auth/set_password_sheet.dart';
import 'package:drivelife/widgets/auth/terms_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

/// How somebody proves the delete is really them.
///
/// Not a bool, because "cancelled" is a third answer and the dialog has
/// to be able to say it — a bool would collapse "I'd rather type my
/// password" into "no".
enum _DeleteProof { password, provider }

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _isDeleting = false;

  /// Which provider is mid-unlink, so only its row spins and a second
  /// tap cannot fire a second request.
  String? _unlinking;

  final _passwordController = TextEditingController();

  /// Separate from [_passwordController] on purpose. Sharing one would
  /// let a password typed to disconnect Google survive into the delete
  /// dialog, which is exactly the sort of thing that goes wrong once
  /// and is then impossible to reproduce.
  final _unlinkPasswordController = TextEditingController();

  // The new-password, confirmation and email fields live in
  // SetPasswordSheet with their own controllers, so there is nothing
  // here to keep in step with them.

  @override
  void dispose() {
    _passwordController.dispose();
    _unlinkPasswordController.dispose();
    super.dispose();
  }

  /// Which provider sheet can prove who this is, or null for a password
  /// account.
  ///
  /// Prefers Apple where the account has it AND the platform can open
  /// it, because an Apple account on Android has no sheet to open. That
  /// combination cannot arise in practice — the Apple button never
  /// renders on Android, so such an account could not have signed in
  /// there to begin with — but falling through to the password dialog
  /// is better than offering a button that throws.
  String? _confirmProvider(List<String> linked) {
    if (linked.contains('apple') && SocialIdentity.appleAvailable) {
      return 'apple';
    }

    if (linked.contains('google')) return 'google';

    return null;
  }

  /// ── WHAT PROVES THIS IS YOU ────────────────────────────────────────
  ///
  /// A password account types its password. An account created with
  /// Apple or Google has a random password that has never been shown to
  /// anybody — see wp_insert_user() in auth-social.php — so asking for
  /// one was asking for something that does not exist. Those accounts
  /// re-open the provider's sheet instead, which is the same proof
  /// Apple and Google require before a destructive change.
  ///
  /// Either way SOMETHING is required. The app's own token is not
  /// enough on its own: this is irreversible and takes the posts, the
  /// garage and the messages with it, so an unlocked phone in somebody
  /// else's hand must not be able to do it.
  ///
  /// The warning comes FIRST now, before either proof. Making somebody
  /// type a password and only then asking "are you sure?" is the wrong
  /// way round, and opening Google's account chooser before the warning
  /// would be worse.
  Future<void> _showDeleteConfirmation() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    final provider = _confirmProvider(user?.socialProviders ?? const []);

    final choice = await _showFinalConfirmation(provider);

    if (choice == null || !mounted) return;

    if (choice == _DeleteProof.provider && provider != null) {
      await _deleteWithProvider(provider);
      return;
    }

    final password = await _showPasswordDialog();

    if (password == null || password.isEmpty || !mounted) return;

    await _deleteAccount(password: password);
  }

  /// The warning, and which proof they want to give.
  ///
  /// Null means they backed out.
  ///
  /// ── WHY THE PASSWORD IS STILL OFFERED ──────────────────────────────
  ///
  /// Having a provider linked does not mean the account was created
  /// with one. dl_social_find_user() links an existing account to
  /// Google on an email match, so somebody who has had a password for
  /// years and once tapped "Continue with Google" has both. Forcing
  /// them through Google would lock them out of deleting their own
  /// account if they have since lost that Google account — so the
  /// provider is the offered route, not the only one.
  Future<_DeleteProof?> _showFinalConfirmation(String? provider) {
    final next = provider == null
        ? 'You will be asked for your password next.'
        : 'You will be asked to confirm with '
              '${SocialIdentity.label(provider)} next.';

    return showDialog<_DeleteProof>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        scrollable: true,
        title: const Text(
          'Delete Account?',
          style: TextStyle(color: Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your account? This action '
              'cannot be undone.\n\n$next',
              style: const TextStyle(color: Colors.black87),
            ),
            if (provider != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: () =>
                      Navigator.pop(context, _DeleteProof.password),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.grey.shade700,
                  ),
                  child: const Text(
                    'Use my password instead',
                    style: TextStyle(
                      fontSize: 13.5,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              provider == null ? _DeleteProof.password : _DeleteProof.provider,
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Opens the provider's sheet, then deletes with the token it hands
  /// back.
  ///
  /// The token is never inspected here. The server verifies it against
  /// Apple's or Google's published keys and checks that its subject is
  /// the one stored against this account, so a token for a different
  /// account — or for a different app — gets nowhere.
  Future<void> _deleteWithProvider(String provider) async {
    setState(() => _isDeleting = true);

    SocialToken? token;

    try {
      token = await SocialIdentity.forProvider(provider);
    } catch (e) {
      debugPrint('❌ [Delete] $provider re-auth threw: $e');

      if (!mounted) return;

      setState(() => _isDeleting = false);

      // Changing their mind is not a failure, and must not be reported
      // as one.
      if (SocialIdentity.isCancellation(e)) return;

      _showError(
        'Could not confirm with ${SocialIdentity.label(provider)}. '
        'Please try again.',
      );
      return;
    }

    if (!mounted) return;

    // Cancelled at the sheet. google_sign_in reports that by returning
    // null rather than throwing, so this is not dead code.
    if (token == null) {
      setState(() => _isDeleting = false);
      return;
    }

    await _deleteAccount(
      provider: provider,
      idToken: token.idToken,
      authorizationCode: token.authorizationCode,
    );
  }

  Future<String?> _showPasswordDialog() async {
    _passwordController.clear();
    bool obscureText = true;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          // The field autofocuses, so the keyboard is up the moment
          // this opens and the dialog has less room than it measured
          // itself for — which is the 91px bottom overflow.
          //
          // scrollable wraps the content in a vertical
          // SingleChildScrollView, which is safe here: a Column asked
          // for its intrinsic height inside an AlertDialog is fine,
          // whereas a ListView in the same place throws.
          scrollable: true,
          title: const Text(
            'Confirm Password',
            style: TextStyle(color: Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please enter your password to continue',
                style: TextStyle(color: Colors.black87, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: obscureText,
                autofocus: true,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureText ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        obscureText = !obscureText;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final password = _passwordController.text.trim();
                if (password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter your password'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, password);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteAccount({
    String? password,
    String? provider,
    String? idToken,
    String? authorizationCode,
  }) async {
    setState(() => _isDeleting = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        throw Exception('User not found');
      }

      debugPrint('🗑️ [Delete] deleting account ${user.id}...');

      final result = await ProfileAPI.deleteUserAccount(
        userId: user.id,
        password: password,
        provider: provider,
        idToken: idToken,
        authorizationCode: authorizationCode,
      );

      if (!mounted) return;

      if (result?['success'] != true) {
        throw Exception(result?['message'] ?? 'Failed to delete account');
      }

      debugPrint('✅ [Delete] account deleted');

      // ── ONLY NOW, AND ONLY EVER AFTER THIS LINE ────────────────────
      //
      // The DriveLife account is confirmed gone, so handing the Google
      // grant back is the honest end state. Deliberately AFTER the
      // delete and after the success check: doing it earlier would mean
      // a failed delete had already given away somebody's sign-in to a
      // live account.
      //
      // This cannot touch their Google account itself — it is the same
      // action as "Remove access" in their own Google settings. It also
      // cannot fail loudly; see SocialIdentity.revokeGrant.
      if (provider != null) {
        await SocialIdentity.revokeGrant(provider);
      }

      if (!mounted) return;

      await userProvider.logout();

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ [Delete] $e');

      if (!mounted) return;

      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  // ── CONNECTED ACCOUNTS ─────────────────────────────────────────────

  /// Disconnects a provider, or explains why it cannot be.
  ///
  /// The "created with this provider" case is settled on the SERVER,
  /// not here — the app only uses [User.socialCreatedWith] to word
  /// the row up front. If a stale profile says otherwise, the server
  /// still refuses and the app offers deletion from the refusal, so the
  /// two cannot disagree about what actually happens.
  Future<void> _disconnect(
    String provider, {
    required bool isOnlyWayIn,
  }) async {
    final label = SocialIdentity.label(provider);

    // ── ASK FOR A PASSWORD ONLY IF ONE CAN EXIST ─────────────────────
    //
    // An earlier version asked unconditionally and let the server
    // correct it, which meant an account with no password was shown a
    // password box, told nothing was wrong with what it typed, and THEN
    // asked to choose a password. Two prompts for one decision, the
    // first of them unanswerable.
    //
    // The screen already knows — socialCreatedWith comes back on the
    // profile — so it branches here instead. The server still decides
    // the outcome, and the stale-profile path below still works.
    if (isOnlyWayIn) {
      await _setPasswordThenUnlink(
        provider,
        '$label is currently your only way to sign in. Choose a password '
        'and we will keep your account, so you can sign in with your '
        'email address instead.',
      );
      return;
    }

    final password = await _showUnlinkDialog(label);

    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _unlinking = provider);

    final result = await SocialApi.unlink(
      provider: provider,
      password: password,
    );

    if (!mounted) return;

    setState(() => _unlinking = null);

    if (result.success) {
      // The grant goes back too, now the link on our side is gone.
      // Google can be done on the device; Apple needs a signed request
      // the server makes only when it has a fresh authorization code,
      // which an unlink does not collect — so Apple users are told
      // where to finish it.
      await SocialIdentity.revokeGrant(provider);

      if (!mounted) return;

      await Provider.of<UserProvider>(context, listen: false).refreshUser();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider == 'apple'
                ? '$label disconnected. To finish, remove DriveLife under '
                      'Settings → Apple ID → Sign in with Apple.'
                : '$label disconnected.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Not an error — this provider is simply the only way in, so a
    // password has to exist before it can go. The ACCOUNT IS KEPT;
    // this is not a route to deletion.
    if (result.needsPasswordFirst) {
      await _setPasswordThenUnlink(provider, result.message);
      return;
    }

    _showError(result.message);
  }

  /// Gives the account a password of its own, then drops the provider.
  ///
  /// ── WHY THE PROVIDER SHEET OPENS AGAIN ─────────────────────────────
  ///
  /// There is no old password to confirm against, so without a fresh
  /// provider token the app's own session would be enough to set one —
  /// and anybody with an unlocked phone could set a password, unlink,
  /// and own the account outright, because the real owner's Google
  /// would no longer open it.
  ///
  /// The server sets the password BEFORE removing the link, so a
  /// failure part-way leaves both ways in rather than none.
  Future<void> _setPasswordThenUnlink(String provider, String why) async {
    final label = SocialIdentity.label(provider);
    final currentEmail =
        Provider.of<UserProvider>(context, listen: false).user?.email ?? '';

    final chosen = await SetPasswordSheet.show(
      context,
      providerLabel: label,
      reason: why,
      currentEmail: currentEmail,
    );

    if (chosen == null || !mounted) return;

    setState(() => _unlinking = provider);

    SocialToken? token;

    try {
      token = await SocialIdentity.forProvider(provider);
    } catch (e) {
      debugPrint('❌ [Unlink] $provider re-auth threw: $e');

      if (!mounted) return;

      setState(() => _unlinking = null);

      if (SocialIdentity.isCancellation(e)) return;

      _showError('Could not confirm with $label. Please try again.');
      return;
    }

    if (!mounted) return;

    if (token == null) {
      setState(() => _unlinking = null);
      return;
    }

    final result = await SocialApi.unlink(
      provider: provider,
      newPassword: chosen.password,
      newEmail: chosen.email,
      idToken: token.idToken,
    );

    if (!mounted) return;

    setState(() => _unlinking = null);

    if (!result.success) {
      _showError(result.message);
      return;
    }

    // Nothing to revoke on the device here: the account now signs in
    // with a password, and handing the grant back is still the honest
    // end state for a link they have just removed.
    await SocialIdentity.revokeGrant(provider);

    if (!mounted) return;

    await Provider.of<UserProvider>(context, listen: false).refreshUser();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// Password and confirmation, with the reason stated above them.
  ///
  /// Deliberately says the account is kept — somebody told their only
  /// login is about to be removed will assume the worst otherwise.
  // REMOVED: _showSetPasswordDialog + _passwordField.
  //
  // Replaced by SetPasswordSheet. There was too much in it for an
  // AlertDialog -- a reason, the login address with an edit
  // affordance, a warning that applies to some people, two password
  // fields and a note about what happens next -- so it read as
  // clutter and the keyboard covered half of it. See
  // widgets/auth/set_password_sheet.dart.


  /// Asks for the password, and says plainly why it is wanted.
  Future<String?> _showUnlinkDialog(String label) async {
    _unlinkPasswordController.clear();
    bool obscureText = true;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          scrollable: true,
          title: Text(
            'Disconnect $label',
            style: const TextStyle(color: Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You will still be able to sign in with your email and '
                'password. Enter your password to confirm.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _unlinkPasswordController,
                obscureText: obscureText,
                autofocus: true,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureText ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscureText = !obscureText),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = _unlinkPasswordController.text.trim();
                if (value.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter your password'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  /// For an account that exists only because of this provider.
  ///
  /// Disconnecting is genuinely impossible — there is no password to
  /// fall back on — so the only honest offer is deletion, and it hands
  /// straight over to the flow that already does it properly.
  // REMOVED: a "cannot disconnect, delete instead?" dialog.
  //
  // Offering deletion as the answer to "I want rid of Google" was
  // wrong. Unlinking is not a deletion, and the right answer is to give
  // the account a password so it has a second way in — which is what
  // _setPasswordThenUnlink() does. Deleting stays where it belongs: the
  // delete section below, chosen deliberately.

  Widget _connectedAccounts(User? user) {
    final linked = user?.socialProviders ?? const <String>[];

    // Nothing connected: the whole section would be a heading over an
    // empty space, so it is not drawn at all.
    if (linked.isEmpty) return const SizedBox.shrink();

    final createdWith = user?.socialCreatedWith;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Connected accounts',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sign-in services connected to your DriveLife account.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        for (final provider in linked) ...[
          _providerRow(provider, isOnlyWayIn: createdWith == provider),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 24),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _providerRow(String provider, {required bool isOnlyWayIn}) {
    final label = SocialIdentity.label(provider);
    final busy = _unlinking == provider;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          provider == 'apple'
              ? const Icon(Icons.apple, size: 22, color: Colors.black)
              : SvgPicture.asset('assets/google-g.svg', width: 20, height: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                ),
                // Said here rather than only in a dialog, so the reason
                // is visible before anything is tapped — and phrased as
                // the extra step it is, not as a refusal. Disconnecting
                // is available to these accounts too; it just collects
                // a password on the way.
                if (isOnlyWayIn)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Your only sign-in — you will set a password first',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              // Still tappable when it is the only way in: it opens the
              // explanation and the offer to delete, which is more use
              // than a dead grey button somebody cannot ask about.
              onPressed: _unlinking != null || _isDeleting
                  ? null
                  : () => _disconnect(provider, isOnlyWayIn: isOnlyWayIn),
              style: TextButton.styleFrom(
                foregroundColor: isOnlyWayIn
                    ? Colors.grey.shade600
                    : Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Disconnect'),
            ),
        ],
      ),
    );
  }

  /// Both policies open the same way they do at sign-up — the same
  /// widgets, in the same sheet — so there is one copy of each document
  /// rather than a second that drifts out of step with it.
  void _showPolicy(Widget modal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => modal,
    );
  }

  Widget _policyLink({required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
      ),
      // Scrollable so the long policy copy plus the delete section
      // cannot overflow on a short screen — the Column had no escape
      // before, which is the other half of the overflow on this screen.
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First, because it is the only section somebody arrives
              // here to CHANGE rather than read. Draws nothing when no
              // provider is connected.
              _connectedAccounts(
                context.watch<UserProvider>().user,
              ),

              // Above the delete section, not below it: somebody who has come
              // here to read a policy should not have to scroll past a red
              // button to find it, and somebody who has come to delete their
              // account is not going to be stopped by two extra rows.
              const Text(
                'Privacy',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'How we handle your data, and the terms you agreed to when you '
                'signed up.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              _policyLink(
                label: 'Privacy Policy',
                onTap: () => _showPolicy(const PrivacyModal()),
              ),
              const SizedBox(height: 8),
              _policyLink(
                label: 'Terms & Conditions',
                onTap: () => _showPolicy(const TermsModal()),
              ),
              const SizedBox(height: 32),
              Divider(color: Colors.grey.shade200, height: 1),
              const SizedBox(height: 32),

              const Text(
                'Delete your account',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'If you would like to completely remove your account, please click below. Please note, it is not possible to restore an account once it has been deleted.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isDeleting ? null : _showDeleteConfirmation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBackgroundColor: Colors.grey,
                  ),
                  child: _isDeleting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFAE9159),
                          ),
                        )
                      : const Text(
                          'DELETE ACCOUNT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
