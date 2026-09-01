import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Shared building blocks for the event-editor tabs.
///
/// The dashboard's panels lean on a small set of repeated controls — a section
/// header, a toggle row, a date field, a numeric field, an empty state. Pulling
/// them out here keeps each tab about its own content rather than about layout,
/// and keeps the four tabs visually consistent with each other.

const Color kEditorGold = Color(0xFFC4A062);
const Color kEditorInk = Color(0xFF0B0B0B);
const Color kEditorMuted = Color(0xFF8A8A8A);

/// Title + optional explanation, above a group of fields.
class EditorSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const EditorSectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 13, color: kEditorMuted),
          ),
        ],
      ],
    );
  }
}

/// A switch with a label and explanation, used to gate a whole section.
class EditorToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  const EditorToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.accent = kEditorGold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: kEditorMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged, activeThumbColor: accent),
        ],
      ),
    );
  }
}

/// Read-only text field that opens a date picker.
///
/// Nullable throughout: an application window with no close date is a real
/// state ("open until we say otherwise"), so the field offers a clear action
/// rather than forcing a date once one has been set.
class EditorDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final Color accent;

  const EditorDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.accent = kEditorGold,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = value == null
        ? 'Not set'
        : DateFormat('d MMM yyyy').format(value!);

    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: firstDate ?? DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          formatted,
          style: TextStyle(
            fontSize: 15,
            color: value == null ? kEditorMuted : kEditorInk,
          ),
        ),
      ),
    );
  }
}

/// Numeric text field where empty means "unset", not zero.
///
/// That distinction carries meaning in these forms — an unset space limit is
/// unlimited, whereas zero would mean nobody can apply.
class EditorNumberField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool allowDecimal;
  final String? prefixText;

  const EditorNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.allowDecimal = false,
    this.prefixText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Placeholder shown where a list has nothing in it yet.
class EditorEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final Color accent;

  const EditorEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.accent = kEditorGold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: kEditorMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard bottom-sheet shell for the "edit one row" forms.
///
/// Scroll-aware and keyboard-aware: these forms are long enough to need it, and
/// a date or money field with the keyboard up must still be reachable.
Future<T?> showEditorSheet<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext context, StateSetter setSheetState)
  builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(child: builder(context, setSheetState)),
            ],
          ),
        ),
      ),
    ),
  );
}
