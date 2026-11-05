import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/auth/register/step_three.dart'
    show RegisterStepThreeScreen;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Asks somebody what they are into, if they never said.
///
/// Registration asks this, and the answer is the only thing the app
/// knows about a person before they have added a car, liked anything or
/// pressed Interested on a suggestion — which is exactly the moment
/// recommendations are worst. Accounts that predate the question, or
/// that skipped it, have nothing recorded and get nothing useful.
///
/// So they are asked again, once, here.
///
/// ── WHY A SHEET AND NOT A DIALOG ────────────────────────────────────
///
/// Nine chips do not fit in an AlertDialog without scrolling it, and a
/// dialog that scrolls is a form wearing the wrong clothes. A sheet is
/// also dismissible by dragging, which matters: this is a question, not
/// a gate, and somebody who does not want to answer should be able to
/// get past it without hunting for a button.
///
/// ── WHY THE LABELS LIVE IN step_three ───────────────────────────────
///
/// They are read from RegisterStepThreeScreen.interestOptions rather than
/// copied. The ids are stored against the user and the server mirrors
/// the same list again in endpoints/interests.php, so there are already
/// two copies of this to keep in step. A third, in the app, in a file
/// that could drift from the registration screen showing the same
/// words, would be one too many.
class InterestsPrompt extends StatefulWidget {
  const InterestsPrompt({super.key});

  /// Show it, unless they have already answered.
  ///
  /// Returns true when something was saved.
  ///
  /// The decision is here rather than at the call site so there is one
  /// definition of "needs asking" — a second screen deciding for itself
  /// is how somebody ends up being asked twice.
  static Future<bool> maybeShow(BuildContext context) async {
    final user = context.read<UserProvider>().user;

    // Null means the profile has not loaded. Not "no interests" — ask
    // nobody on the strength of a request that has not finished.
    if (user == null || user.interests.isNotEmpty) return false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const InterestsPrompt(),
    );

    return saved == true;
  }

  @override
  State<InterestsPrompt> createState() => _InterestsPromptState();
}

class _InterestsPromptState extends State<InterestsPrompt> {
  final Set<int> _picked = {};
  bool _saving = false;

  Future<void> _save() async {
    final user = context.read<UserProvider>().user;

    if (user == null || _picked.isEmpty || _saving) return;

    setState(() => _saving = true);

    final result = await ProfileAPI.updateContentIds(
      contentIds: _picked.toList()..sort(),
      userId: user.id,
    );

    if (!mounted) return;

    if (result == null || result['success'] != true) {
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that. Try again?')),
      );

      return;
    }

    // Held locally too, so nothing asks again before the next profile
    // fetch. Without this the prompt reappears on the next screen that
    // calls maybeShow.
    context.read<UserProvider>().setInterests(_picked.toList()..sort());

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final options = RegisterStepThreeScreen.interestOptions;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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

            Text(
              'What are you into?',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: theme.textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pick a few and we will point you at the groups, clubs and '
              'events worth your time.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: theme.subtextColor,
              ),
            ),

            const SizedBox(height: 18),

            // Bounded and scrollable: nine chips is two or three rows on
            // a phone and more if the list grows, and a sheet that
            // cannot be dismissed because its button is off-screen is
            // worse than no prompt.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.38,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.entries.map((entry) {
                    final selected = _picked.contains(entry.key);

                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _picked.remove(entry.key);
                        } else {
                          _picked.add(entry.key);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.primaryColor
                              : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : theme.textColor,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                TextButton(
                  // Not a gate. Somebody who does not want to answer
                  // should be able to say so once rather than dodge the
                  // sheet every time they open the app — the server
                  // records nothing, so this is only for now, and that
                  // is the honest trade for not nagging.
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Not now',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.subtextColor,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _picked.isEmpty || _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 13,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _picked.isEmpty
                              ? 'Pick at least one'
                              : 'Save ${_picked.length}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
