import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/brands_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Pick the marques you are into.
///
/// ── ONE WIDGET, THREE PLACES ─────────────────────────────────────────
///
/// Signup asks this, the prompt asks anybody who signed up before the
/// question existed, and the account screen lets it be changed. All
/// three are the same list with the same rules, so they are the same
/// widget — three copies would be three sets of wording to keep in
/// step and three places to forget that unticking has to save.
///
/// It owns the loading and the selection, and hands the chosen ids up
/// through [onChanged]. Saving is the caller's, because the three
/// surfaces save at different moments: signup on Next, the prompt on
/// Done, the account screen as you go.
class BrandPicker extends StatefulWidget {
  /// Ticked when it opens. Usually what the server already has.
  final Set<int> initial;

  /// Called on every change, with the full current selection.
  final ValueChanged<Set<int>> onChanged;

  /// Shown above the grid. Null for no heading — the prompt draws its
  /// own.
  final String? title;

  const BrandPicker({
    super.key,
    this.initial = const <int>{},
    required this.onChanged,
    this.title,
  });

  @override
  State<BrandPicker> createState() => BrandPickerState();
}

class BrandPickerState extends State<BrandPicker> {
  List<Brand> _brands = const [];
  late Set<int> _chosen;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _chosen = {...widget.initial};
    _load();
  }

  Future<void> _load() async {
    final options = await BrandsAPI.load();

    if (!mounted) return;

    setState(() {
      _brands = options.brands;

      // The server's answer wins over what the caller guessed, unless
      // the caller has been given something explicitly. Signup passes
      // nothing and wants the server's; the account screen passes what
      // it already drew and wants to keep it.
      if (widget.initial.isEmpty && options.selected.isNotEmpty) {
        _chosen = {...options.selected};
      }

      _loading = false;
    });

    // So a caller that opened with nothing knows what was already there
    // — otherwise its Save would wipe an existing answer.
    widget.onChanged({..._chosen});
  }

  void _toggle(Brand brand) {
    setState(() {
      if (!_chosen.remove(brand.id)) _chosen.add(brand.id);
    });

    widget.onChanged({..._chosen});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    if (_brands.isEmpty) {
      // Nothing to pick. Said plainly rather than drawn as an empty
      // grid, which reads as still loading.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Text(
          'No brands to choose from yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.subtextColor, fontSize: 14.5),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null) ...[
          Text(
            widget.title!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: theme.textColor,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Wrap, not a grid. Marque names run from "BMW" to
        // "4x4 & Overlanding", and a fixed column width would either
        // clip the long ones or leave the short ones swimming.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _brands.map((brand) => _chip(theme, brand)).toList(),
        ),
      ],
    );
  }

  Widget _chip(ThemeProvider theme, Brand brand) {
    final on = _chosen.contains(brand.id);

    return InkWell(
      onTap: () => _toggle(brand),
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logo(theme, brand, on),
            const SizedBox(width: 8),
            Text(
              brand.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                color: on ? theme.primaryColor : theme.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo(ThemeProvider theme, Brand brand, bool on) {
    const size = 26.0;

    if (brand.logo == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.subtextColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          // Guarded: a group with an empty title would be a RangeError
          // here, and the list is maintained by hand.
          brand.name.isNotEmpty ? brand.name.characters.first.toUpperCase() : '?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: theme.subtextColor,
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: brand.logo!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Small and many: decoding these at full size would be a lot of
        // memory for a 26pt circle.
        memCacheWidth: 80,
        placeholder: (_, _) => Container(
          width: size,
          height: size,
          color: theme.subtextColor.withValues(alpha: 0.12),
        ),
        errorWidget: (_, _, _) => Container(
          width: size,
          height: size,
          color: theme.subtextColor.withValues(alpha: 0.12),
          child: Icon(Icons.directions_car, size: 14, color: theme.subtextColor),
        ),
      ),
    );
  }
}
