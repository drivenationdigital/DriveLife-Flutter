import 'package:drivelife/models/event_editor_models.dart';
import 'package:drivelife/widgets/events/editor/editor_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Discounts & upsells — promo codes for an event's tickets.
///
/// Mirrors `DiscountsPanel.tsx` in the dashboard. Usage figures are read-only:
/// they come from orders, so the editor shows them but never sets them.
class DiscountsTab extends StatelessWidget {
  final List<EventDiscount> discounts;
  final ValueChanged<List<EventDiscount>> onChanged;
  final Color accent;

  /// Ticket names by id, for the "applies to" picker. Empty while the app has
  /// no per-ticket model — the picker then offers "All tickets" only.
  final Map<String, String> ticketNames;

  const DiscountsTab({
    super.key,
    required this.discounts,
    required this.onChanged,
    this.accent = kEditorGold,
    this.ticketNames = const {},
  });

  Future<void> _edit(BuildContext context, EventDiscount? existing) async {
    final result = await _showDiscountEditor(
      context: context,
      accent: accent,
      ticketNames: ticketNames,
      original: existing ?? EventDiscount.blank(),
      isNew: existing == null,
    );

    if (result == null) return;

    final next = List<EventDiscount>.from(discounts);
    final index = next.indexWhere((d) => d.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    onChanged(next);
  }

  void _delete(EventDiscount discount) {
    onChanged(discounts.where((d) => d.id != discount.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const EditorSectionHeader(
          title: 'Discount codes',
          subtitle:
              'Codes buyers enter at checkout. Leave the ticket selection as '
              '"All tickets" so codes keep working when you add tickets later.',
        ),
        const SizedBox(height: 16),

        if (discounts.isEmpty)
          EditorEmptyState(
            icon: Icons.local_offer_outlined,
            title: 'No discount codes',
            message:
                'Add a code to give a percentage or fixed amount off ticket '
                'prices.',
            actionLabel: 'Add a code',
            accent: accent,
            onAction: () => _edit(context, null),
          )
        else ...[
          for (final discount in discounts) ...[
            _DiscountCard(
              discount: discount,
              accent: accent,
              ticketNames: ticketNames,
              onEdit: () => _edit(context, discount),
              onDelete: () => _delete(discount),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another code'),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ],
    );
  }
}

class _DiscountCard extends StatelessWidget {
  final EventDiscount discount;
  final Color accent;
  final Map<String, String> ticketNames;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DiscountCard({
    required this.discount,
    required this.accent,
    required this.ticketNames,
    required this.onEdit,
    required this.onDelete,
  });

  String get _value => discount.kind == DiscountKind.percentage
      ? '${_trimZeros(discount.amount)}% off'
      : '£${discount.amount.toStringAsFixed(2)} off';

  static String _trimZeros(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  String get _appliesTo {
    if (discount.appliesToAllTickets) return 'All tickets';
    final names = discount.applicableTicketIds
        .map((id) => ticketNames[id] ?? 'Ticket')
        .toList();
    return names.length <= 2
        ? names.join(', ')
        : '${names.length} selected tickets';
  }

  String? get _window {
    final from = discount.availableFrom;
    final until = discount.availableUntil;
    if (from == null && until == null) return null;

    final format = DateFormat('d MMM');
    if (from != null && until != null) {
      return '${format.format(from)} – ${format.format(until)}';
    }
    return from != null
        ? 'From ${format.format(from)}'
        : 'Until ${format.format(until!)}';
  }

  @override
  Widget build(BuildContext context) {
    final expired = discount.isExpired;
    final usedUp = discount.isUsedUp;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: expired || usedUp ? Colors.grey.shade50 : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        discount.code.isEmpty
                            ? 'Untitled code'
                            : discount.code.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: expired ? kEditorMuted : kEditorInk,
                        ),
                      ),
                    ),
                    if (expired) ...[
                      const SizedBox(width: 8),
                      const _Badge(text: 'Expired', color: Colors.redAccent),
                    ] else if (usedUp) ...[
                      const SizedBox(width: 8),
                      const _Badge(text: 'Used up', color: Colors.orange),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 19),
                color: Colors.red.shade400,
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
          if (discount.note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              discount.note,
              style: const TextStyle(fontSize: 12.5, color: kEditorMuted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(label: _value, accent: accent, strong: true),
              _Chip(label: _appliesTo, accent: accent),
              if (_window != null) _Chip(label: _window!, accent: accent),
              if (discount.usageLimit != null)
                _Chip(
                  label:
                      '${discount.usageCount}/${discount.usageLimit} used',
                  accent: accent,
                ),
              if (discount.perCustomerLimit != null)
                _Chip(
                  label: 'Max ${discount.perCustomerLimit} per customer',
                  accent: accent,
                ),
            ],
          ),
          if (discount.discountGiven > 0) ...[
            const SizedBox(height: 10),
            Text(
              '£${discount.discountGiven.toStringAsFixed(2)} given away so far',
              style: const TextStyle(fontSize: 12, color: kEditorMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color accent;
  final bool strong;

  const _Chip({required this.label, required this.accent, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: strong ? accent.withOpacity(0.12) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong ? accent : Colors.grey.shade700,
        ),
      ),
    );
  }
}

/// The add/edit form. Returns the edited discount, or null if cancelled.
Future<EventDiscount?> _showDiscountEditor({
  required BuildContext context,
  required Color accent,
  required Map<String, String> ticketNames,
  required EventDiscount original,
  required bool isNew,
}) {
  var draft = original;

  final codeController = TextEditingController(text: original.code);
  final amountController = TextEditingController(
    text: original.amount == 0 ? '' : '${original.amount}',
  );
  final noteController = TextEditingController(text: original.note);
  final usageLimitController = TextEditingController(
    text: original.usageLimit?.toString() ?? '',
  );
  final perCustomerController = TextEditingController(
    text: original.perCustomerLimit?.toString() ?? '',
  );

  return showEditorSheet<EventDiscount>(
    context: context,
    title: isNew ? 'New discount code' : 'Edit discount code',
    builder: (sheetContext, setSheetState) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Code *',
                hintText: 'SUMMER25',
                helperText: 'What the buyer types at checkout',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: SegmentedButton<DiscountKind>(
                    segments: const [
                      ButtonSegment(
                        value: DiscountKind.percentage,
                        label: Text('%'),
                      ),
                      ButtonSegment(value: DiscountKind.fixed, label: Text('£')),
                    ],
                    selected: {draft.kind},
                    onSelectionChanged: (selection) => setSheetState(() {
                      draft = draft.copyWith(kind: selection.first);
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: EditorNumberField(
                    label: draft.kind == DiscountKind.percentage
                        ? 'Percent off'
                        : 'Amount off',
                    controller: amountController,
                    allowDecimal: true,
                    prefixText: draft.kind == DiscountKind.fixed ? '£ ' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const EditorSectionHeader(
              title: 'Availability',
              subtitle: 'Leave either date unset for no limit on that side.',
            ),
            const SizedBox(height: 12),
            EditorDateField(
              label: 'Available from',
              value: draft.availableFrom,
              accent: accent,
              onChanged: (date) => setSheetState(() {
                draft = draft.copyWith(availableFrom: () => date);
              }),
            ),
            const SizedBox(height: 12),
            EditorDateField(
              label: 'Available until',
              value: draft.availableUntil,
              accent: accent,
              firstDate: draft.availableFrom,
              onChanged: (date) => setSheetState(() {
                draft = draft.copyWith(availableUntil: () => date);
              }),
            ),
            const SizedBox(height: 20),

            const EditorSectionHeader(
              title: 'Limits',
              subtitle: 'Leave blank for unlimited.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: EditorNumberField(
                    label: 'Total uses',
                    hint: 'Unlimited',
                    controller: usageLimitController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EditorNumberField(
                    label: 'Per customer',
                    hint: 'Unlimited',
                    controller: perCustomerController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Club members only',
                border: OutlineInputBorder(),
              ),
            ),

            if (draft.usageCount > 0) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Used ${draft.usageCount} time'
                  '${draft.usageCount == 1 ? '' : 's'}, giving away '
                  '£${draft.discountGiven.toStringAsFixed(2)}.',
                  style: const TextStyle(fontSize: 12.5, color: kEditorMuted),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: () {
                      final code = codeController.text.trim();
                      if (code.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Enter a code')),
                        );
                        return;
                      }

                      Navigator.pop(
                        sheetContext,
                        draft.copyWith(
                          code: code.toUpperCase(),
                          amount:
                              double.tryParse(amountController.text.trim()) ?? 0,
                          usageLimit: () =>
                              int.tryParse(usageLimitController.text.trim()),
                          perCustomerLimit: () =>
                              int.tryParse(perCustomerController.text.trim()),
                          note: noteController.text.trim(),
                        ),
                      );
                    },
                    child: Text(isNew ? 'Add code' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
