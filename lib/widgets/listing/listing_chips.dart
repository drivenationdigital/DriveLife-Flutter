import 'package:flutter/material.dart';

/// One choice in a [ListingChips] row.
@immutable
class ListingChip {
  /// What the user reads.
  final String label;

  /// What the screen stores. Kept separate from [label] because the labels
  /// are design copy — "50 miles" — and the values are API filters.
  final String value;

  const ListingChip({required this.label, required this.value});
}

/// A scrolling row of filter pills.
///
/// Replaces the pair of dropdown buttons the listing screens used to carry.
/// A dropdown hides its options behind a tap and a sheet; a row of pills
/// shows every choice and the current one at a glance, which for four
/// distances is the whole decision.
///
/// Scrolls horizontally rather than wrapping. Wrapping would change the
/// height of the row as the labels change between screens, and everything
/// below it would move with it.
class ListingChips extends StatelessWidget {
  final List<ListingChip> chips;
  final String selected;
  final ValueChanged<String> onChanged;

  /// Matches the horizontal padding of the content around it, so the first
  /// pill lines up with the cards below.
  final double horizontalPadding;

  const ListingChips({
    super.key,
    required this.chips,
    required this.selected,
    required this.onChanged,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 38, not 42. A row of pills is a filter, not a toolbar — Instagram
      // runs its equivalent at about this and it stops the controls above
      // a list taking a tenth of the screen.
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final chip = chips[i];
          final isSelected = chip.value == selected;

          return Material(
            color: isSelected
                ? const Color(0xFF111111)
                : const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(19),
            child: InkWell(
              onTap: () => onChanged(chip.value),
              borderRadius: BorderRadius.circular(19),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    chip.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF3A3A3A),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
