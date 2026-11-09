import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/services/social_identity.dart';
import 'package:drivelife/widgets/auth/privacy_modal.dart';
import 'package:drivelife/widgets/auth/terms_modal.dart';
import 'package:flutter/material.dart';
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
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
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
