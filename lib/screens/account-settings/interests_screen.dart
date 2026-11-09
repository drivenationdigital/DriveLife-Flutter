import 'package:drivelife/api/brands_api.dart';
import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/auth/register/step_three.dart';
import 'package:drivelife/widgets/interests/brand_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "Interests & Notifications" — change what signup asked.
///
/// ── WHY BOTH QUESTIONS ON ONE SCREEN ─────────────────────────────────
///
/// Signup asks them one after the other and they feed the same thing:
/// what turns up in the feed and what gets pushed. Splitting them into
/// two account screens would make somebody hunt for the one they meant,
/// and neither is long enough to deserve a screen of its own.
///
/// ── WHY IT SAVES ON LEAVING, NOT ON EVERY TAP ────────────────────────
///
/// Each tap would be a request, and a quick run through twelve brands
/// would be twelve of them racing — with the last one to arrive, not
/// the last one tapped, deciding the answer.
class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  late Set<int> _interests;
  Set<int> _brands = const <int>{};

  /// What they arrived with, so leaving without changing anything
  /// writes nothing.
  late Set<int> _interestsWere;
  Set<int>? _brandsWere;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final user = context.read<UserProvider>().user;

    _interests = {...?user?.interests};
    _interestsWere = {..._interests};
  }

  bool get _changed =>
      !_setEquals(_interests, _interestsWere) ||
      (_brandsWere != null && !_setEquals(_brands, _brandsWere!));

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.every(b.contains);

  Future<void> _save() async {
    if (_saving || !_changed) return;

    final user = context.read<UserProvider>().user;
    if (user == null) return;

    setState(() => _saving = true);

    var ok = true;

    if (!_setEquals(_brands, _brandsWere ?? _brands)) {
      ok = await BrandsAPI.save(_brands);
    }

    if (ok && !_setEquals(_interests, _interestsWere)) {
      final result = await ProfileAPI.updateContentIds(
        contentIds: _interests.toList()..sort(),
        userId: user.id,
      );

      ok = result != null && result['success'] == true;
    }

    if (!mounted) return;

    setState(() => _saving = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that. Try again?')),
      );
      return;
    }

    final provider = context.read<UserProvider>()
      ..setInterests(_interests.toList()..sort())
      ..setBrands(_brands.toList()..sort());

    // Read back so the next comparison is against what was saved.
    _interestsWere = {..._interests};
    _brandsWere = {..._brands};

    if (!mounted) return;

    // Unused beyond the cascade, but reading it keeps the intent clear
    // that both setters are on the same provider instance.
    assert(provider.user != null || provider.user == null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return PopScope(
      // Saves on the way out rather than needing a button pressed. The
      // alternative is somebody changing three things, pressing back
      // and losing all of them.
      canPop: !_changed || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        final navigator = Navigator.of(context);
        await _save();

        if (mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: AppBar(
          backgroundColor: theme.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: theme.textColor, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            'Interests & Notifications',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: theme.textColor,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_saving)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              'These decide what we put in your feed and what we send you.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: theme.subtextColor,
              ),
            ),
            const SizedBox(height: 26),

            _heading(theme, 'What you are into'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: RegisterStepThreeScreen.interestOptions.entries
                  .map((e) => _interestChip(theme, e.key, e.value))
                  .toList(),
            ),

            const SizedBox(height: 32),

            _heading(theme, 'Brands'),
            const SizedBox(height: 12),
            BrandPicker(
              onChanged: (ids) => setState(() {
                _brands = ids;
                // The first callback is the picker reporting what the
                // server already had, not a change by the user — so it
                // becomes the baseline rather than a pending edit.
                _brandsWere ??= {...ids};
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(ThemeProvider theme, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: theme.textColor,
    ),
  );

  Widget _interestChip(ThemeProvider theme, int id, String label) {
    final on = _interests.contains(id);

    return InkWell(
      onTap: () => setState(() {
        if (!_interests.remove(id)) _interests.add(id);
      }),
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? theme.primaryColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: on
                ? theme.primaryColor
                : theme.subtextColor.withValues(alpha: 0.35),
            width: on ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            color: on ? theme.primaryColor : theme.textColor,
          ),
        ),
      ),
    );
  }
}
