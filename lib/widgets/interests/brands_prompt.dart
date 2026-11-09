import 'package:drivelife/api/brands_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/widgets/interests/brand_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "Which brands are you into?", for people who signed up before the
/// question existed.
///
/// The same shape as InterestsPrompt, deliberately: the two ask about
/// adjacent things and should not feel like two different features.
class BrandsPrompt extends StatefulWidget {
  const BrandsPrompt({super.key});

  /// Show it, unless they have already answered.
  ///
  /// Returns true when something was saved.
  ///
  /// The decision lives here rather than at the call site so there is
  /// one definition of "needs asking" — a second screen deciding for
  /// itself is how somebody gets asked twice.
  ///
  /// Keys off brandsAnswered, NOT an empty list. Somebody who looked at
  /// the brands and picked none has answered, and asking them again
  /// every launch would be a popup they can never get rid of.
  static Future<bool> maybeShow(BuildContext context) async {
    final user = context.read<UserProvider>().user;

    // Null means the profile has not loaded. Ask nobody on the strength
    // of a request that has not finished.
    if (user == null || user.brandsAnswered) return false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BrandsPrompt(),
    );

    return saved == true;
  }

  @override
  State<BrandsPrompt> createState() => _BrandsPromptState();
}

class _BrandsPromptState extends State<BrandsPrompt> {
  Set<int> _picked = const <int>{};
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    final ok = await BrandsAPI.save(_picked);

    if (!mounted) return;

    if (!ok) {
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that. Try again?')),
      );

      return;
    }

    // Held locally too, so nothing asks again before the next profile
    // fetch. Without this the prompt reappears on the next screen that
    // calls maybeShow.
    context.read<UserProvider>().setBrands(_picked.toList()..sort());

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.subtextColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  children: [
                    Text(
                      'Which brands are you into?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: theme.textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We will use these to show you more of what you '
                      'actually want to see. You can change them any time '
                      'in your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: theme.subtextColor,
                      ),
                    ),
                    const SizedBox(height: 22),

                    BrandPicker(
                      onChanged: (ids) => setState(() => _picked = ids),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      // "Not now" closes WITHOUT saving, so brandsAnswered
                      // stays false and they are asked again next launch.
                      //
                      // Deliberate: the alternative is recording an empty
                      // answer, which would silently mean "never ask me",
                      // and nobody tapping "not now" means that.
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: Text(
                          'Not now',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.subtextColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
                                  _picked.isEmpty ? 'Skip' : 'Save',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
