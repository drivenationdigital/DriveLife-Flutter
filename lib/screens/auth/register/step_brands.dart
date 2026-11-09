import 'package:drivelife/api/brands_api.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/widgets/interests/brand_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "Which brands are you into?" — signup, straight after the interests.
///
/// ── WHY IT IS NOT 'register-step-4' ──────────────────────────────────
///
/// It sits between step three and step four, and the obvious way to do
/// that is to renumber everything from four up. The numbers are in
/// route names, in RegistrationProvider's step counter and in whatever
/// is already in flight for somebody mid-signup when the build ships —
/// so renumbering is a lot of edges for a screen that only needs to be
/// in the right place.
///
/// It has a name instead, and the order comes from the navigation
/// rather than the numbering.
///
/// ── AND WHY IT CAN BE SKIPPED ────────────────────────────────────────
///
/// Picking nothing is a real answer and is saved as one: the empty list
/// records that they were asked, which is what stops the prompt asking
/// again. See dl_user_has_brands_answer().
class RegisterBrandsScreen extends StatefulWidget {
  const RegisterBrandsScreen({super.key});

  @override
  State<RegisterBrandsScreen> createState() => _RegisterBrandsScreenState();
}

class _RegisterBrandsScreenState extends State<RegisterBrandsScreen> {
  Set<int> _chosen = const <int>{};
  bool _saving = false;

  Future<void> _continue() async {
    if (_saving) return;

    setState(() => _saving = true);

    final ok = await BrandsAPI.save(_chosen);

    if (!mounted) return;

    setState(() => _saving = false);

    if (!ok) {
      // Not moved on. Signup is the one chance to collect this, and a
      // silent failure here is somebody who gets prompted for it the
      // next time they open the app for no reason they can see.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;

    context.read<RegistrationProvider>().nextStep();
    Navigator.pushNamed(context, '/register-step-4');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final isDark = theme.isDarkMode;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),
                        Center(
                          child: Text(
                            'About You',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Which brands are you into?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            'Tick all that apply',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        BrandPicker(
                          onChanged: (ids) => setState(() => _chosen = ids),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB8966B),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            // Says what it will do. "Continue" on an
                            // empty selection looks like it is refusing
                            // to let you past.
                            _chosen.isEmpty ? 'Skip' : 'Continue',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
