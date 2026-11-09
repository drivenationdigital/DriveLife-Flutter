import 'package:flutter/material.dart';

const Color _gold = Color(0xFFAE9159);

/// What somebody chose in [SetPasswordSheet].
class PasswordSetup {
  final String password;

  /// The login email, or null if they left it alone.
  ///
  /// Null rather than the unchanged value, so "they did not touch it"
  /// stays distinguishable from "they retyped the same thing" — the
  /// server only writes an address when one actually changed.
  final String? email;

  const PasswordSetup(this.password, this.email);
}

/// Giving an account its own password, so a provider can be
/// disconnected without losing it.
///
/// ── A SHEET, NOT A DIALOG ──────────────────────────────────────────
///
/// There is too much here for an AlertDialog: a reason, the login
/// address with an edit affordance, a warning that applies to some
/// people, two password fields and a note about what happens next. In
/// a dialog that reads as clutter, and the keyboard covers half of it.
/// A sheet has the room, scrolls under the keyboard, and gives the
/// primary action a full-width button instead of a cramped text one.
///
/// ── WHY THE EMAIL IS SHOWN AT ALL ──────────────────────────────────
///
/// It is the thing most likely to go wrong and the last thing anybody
/// would think to check. An Apple Hide My Email account's login is an
/// @privaterelay.appleid.com address its owner has probably never seen,
/// and Apple stops forwarding to it unless the sending domain is
/// registered with them. Disconnect without showing it and the first
/// they learn is a password reset that never arrives.
class SetPasswordSheet extends StatefulWidget {
  /// 'Apple' or 'Google', for the copy.
  final String providerLabel;

  /// Why this is being asked, in the server's own words where it came
  /// from there.
  final String reason;

  final String currentEmail;

  const SetPasswordSheet({
    super.key,
    required this.providerLabel,
    required this.reason,
    required this.currentEmail,
  });

  /// Opens it. Null means they backed out.
  static Future<PasswordSetup?> show(
    BuildContext context, {
    required String providerLabel,
    required String reason,
    required String currentEmail,
  }) {
    return showModalBottomSheet<PasswordSetup>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Dismissing by tapping away is fine — nothing has happened yet,
      // and the account is untouched either way.
      builder: (context) => SetPasswordSheet(
        providerLabel: providerLabel,
        reason: reason,
        currentEmail: currentEmail,
      ),
    );
  }

  @override
  State<SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<SetPasswordSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _email = TextEditingController();

  bool _obscure = true;
  bool _editingEmail = false;
  String? _error;

  /// Apple's private relay.
  bool get _isRelay =>
      widget.currentEmail.toLowerCase().contains('@privaterelay.appleid.com');

  @override
  void initState() {
    super.initState();

    _email.text = widget.currentEmail;

    // Open for editing from the start for a relay address, because for
    // those LEAVING it is the choice that needs thinking about — the
    // opposite of everybody else, who should not be nudged into
    // changing an address that works.
    _editingEmail = _isRelay;
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    final confirm = _confirm.text;
    final email = _email.text.trim();

    // Checked here as well as on the server, so nobody is sent through
    // a provider sheet only to be told their password was too short.
    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }

    if (password != confirm) {
      setState(() => _error = 'Those passwords do not match.');
      return;
    }

    // Shape only. Whether it is already taken is the server's call, and
    // it checks that before writing anything.
    if (_editingEmail) {
      final looksValid =
          email.isNotEmpty &&
          !email.contains(' ') &&
          email.contains('@') &&
          email.contains('.') &&
          !email.startsWith('@') &&
          !email.endsWith('@') &&
          !email.endsWith('.');

      if (!looksValid) {
        setState(() => _error = 'Enter a valid email address.');
        return;
      }
    }

    Navigator.pop(
      context,
      PasswordSetup(
        password,
        (_editingEmail && email != widget.currentEmail) ? email : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // viewInsets, so the content lifts above the keyboard rather than
    // sitting behind it. With isScrollControlled this is what makes the
    // fields reachable.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        // Never taller than most of the screen, so the sheet still
        // reads as a sheet and the page behind stays visible.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const Text(
                    'Keep your account',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.reason,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your account and everything in it stays exactly as it is.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade700,
                    ),
                  ),

                  const SizedBox(height: 22),
                  _label('You will sign in with'),
                  const SizedBox(height: 8),

                  if (_editingEmail)
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      style: const TextStyle(color: Colors.black),
                      decoration: _field('Email address'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.currentEmail.isEmpty
                                  ? '—'
                                  : widget.currentEmail,
                              style: const TextStyle(
                                fontSize: 14.5,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _editingEmail = true),
                            style: TextButton.styleFrom(
                              foregroundColor: _gold,
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),

                  if (_isRelay) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF5DDBA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.brown.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This is a private Apple address. Once '
                              '${widget.providerLabel} is disconnected, '
                              'emails we send — including password resets — '
                              'may stop reaching you. We strongly recommend '
                              'using your own email address.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: Colors.brown.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),
                  _label('Choose a password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofocus: !_isRelay,
                    autofillHints: const [AutofillHints.newPassword],
                    style: const TextStyle(color: Colors.black),
                    decoration: _field(
                      'New password',
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey.shade600,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    style: const TextStyle(color: Colors.black),
                    decoration: _field('Confirm password'),
                    onSubmitted: (_) => _submit(),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Set password & disconnect '
                        '${widget.providerLabel}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'You will confirm with ${widget.providerLabel} once '
                      'more, so we know it is really you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    ),
  );

  InputDecoration _field(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400),
    filled: true,
    fillColor: Colors.grey.shade100,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _gold, width: 1.5),
    ),
    suffixIcon: suffix,
  );
}
