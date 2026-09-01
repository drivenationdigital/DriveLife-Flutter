import 'package:drivelife/models/event_editor_models.dart';
import 'package:drivelife/widgets/events/editor/editor_fields.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Traders — pitches for food, apparel, parts and sponsors.
///
/// Mirrors `TradersPanel.tsx`. The one structural difference from show cars:
/// a trader pitch is never free. It is either paid online at checkout or
/// settled in person, so the editor asks which rather than whether.
class TradersTab extends StatelessWidget {
  final TradersConfig config;
  final ValueChanged<TradersConfig> onChanged;
  final Color accent;

  const TradersTab({
    super.key,
    required this.config,
    required this.onChanged,
    this.accent = kEditorGold,
  });

  Future<void> _editCategory(
    BuildContext context,
    TraderCategory? existing,
  ) async {
    final result = await _showTraderEditor(
      context: context,
      accent: accent,
      original: existing ?? TraderCategory.blank(),
      isNew: existing == null,
    );

    if (result == null) return;

    final next = List<TraderCategory>.from(config.categories);
    final index = next.indexWhere((c) => c.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    onChanged(config.copyWith(categories: next));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        EditorToggleRow(
          title: 'Accept trader applications',
          subtitle:
              'Let traders apply for a pitch. Applications are reviewed before '
              'a pitch is confirmed.',
          value: config.enabled,
          accent: accent,
          onChanged: (value) => onChanged(config.copyWith(enabled: value)),
        ),

        if (!config.enabled) ...[
          const SizedBox(height: 20),
          Text(
            'Turn this on to set up pitch types and application windows.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ] else ...[
          const SizedBox(height: 24),
          const EditorSectionHeader(
            title: 'Pitch types',
            subtitle:
                'Each type has its own window, price and space count — for '
                'example food, apparel, parts, sponsors.',
          ),
          const SizedBox(height: 14),

          if (config.categories.isEmpty)
            EditorEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No pitch types',
              message:
                  'Add at least one type so traders know what they are '
                  'applying for.',
              actionLabel: 'Add a pitch type',
              accent: accent,
              onAction: () => _editCategory(context, null),
            )
          else ...[
            for (final category in config.categories) ...[
              _TraderCard(
                category: category,
                accent: accent,
                onEdit: () => _editCategory(context, category),
                onDelete: () => onChanged(
                  config.copyWith(
                    categories: config.categories
                        .where((c) => c.id != category.id)
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _editCategory(context, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add another pitch type'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _TraderCard extends StatelessWidget {
  final TraderCategory category;
  final Color accent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TraderCard({
    required this.category,
    required this.accent,
    required this.onEdit,
    required this.onDelete,
  });

  String? get _window {
    final open = category.applicationsOpen;
    final close = category.applicationsClose;
    if (open == null && close == null) return null;

    final format = DateFormat('d MMM');
    if (open != null && close != null) {
      return '${format.format(open)} – ${format.format(close)}';
    }
    return open != null
        ? 'Opens ${format.format(open)}'
        : 'Closes ${format.format(close!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(category.icon.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name.isEmpty ? 'Untitled pitch' : category.name,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      category.icon.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: kEditorMuted,
                      ),
                    ),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: category.ticketCost == null
                    ? 'Price not set'
                    : '£${category.ticketCost!.toStringAsFixed(2)}',
                accent: accent,
                strong: true,
              ),
              _Pill(label: category.paymentMode.label, accent: accent),
              _Pill(
                label: category.spacesAvailable == null
                    ? 'Unlimited pitches'
                    : '${category.spacesAvailable} pitches',
                accent: accent,
              ),
              if (_window != null) _Pill(label: _window!, accent: accent),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color accent;
  final bool strong;

  const _Pill({required this.label, required this.accent, this.strong = false});

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

Future<TraderCategory?> _showTraderEditor({
  required BuildContext context,
  required Color accent,
  required TraderCategory original,
  required bool isNew,
}) {
  var draft = original;

  final nameController = TextEditingController(text: original.name);
  final infoController = TextEditingController(text: original.info);
  final costController = TextEditingController(
    text: original.ticketCost?.toString() ?? '',
  );
  final spacesController = TextEditingController(
    text: original.spacesAvailable?.toString() ?? '',
  );
  final codeController = TextEditingController(text: original.secretCode);

  return showEditorSheet<TraderCategory>(
    context: context,
    title: isNew ? 'New pitch type' : 'Edit pitch type',
    builder: (sheetContext, setSheetState) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Pitch name *',
                hintText: 'Food & drink',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            const EditorSectionHeader(title: 'Icon'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final icon in TraderIcon.values)
                  _IconChoice(
                    icon: icon,
                    selected: draft.icon == icon,
                    accent: accent,
                    onTap: () =>
                        setSheetState(() => draft = draft.copyWith(icon: icon)),
                  ),
              ],
            ),
            const SizedBox(height: 22),

            const EditorSectionHeader(
              title: 'Payment',
              subtitle:
                  'Pitches are never free. Online takes payment at checkout; '
                  'in person is invoice or pay on the day.',
            ),
            const SizedBox(height: 12),
            SegmentedButton<TraderPaymentMode>(
              segments: const [
                ButtonSegment(
                  value: TraderPaymentMode.online,
                  label: Text('Pay online'),
                ),
                ButtonSegment(
                  value: TraderPaymentMode.inPerson,
                  label: Text('In person'),
                ),
              ],
              selected: {draft.paymentMode},
              onSelectionChanged: (selection) => setSheetState(() {
                draft = draft.copyWith(paymentMode: selection.first);
              }),
            ),
            const SizedBox(height: 16),
            EditorNumberField(
              label: 'Pitch fee',
              controller: costController,
              allowDecimal: true,
              prefixText: '£ ',
            ),
            const SizedBox(height: 20),

            const EditorSectionHeader(
              title: 'Application window',
              subtitle: 'When traders can apply for this pitch type.',
            ),
            const SizedBox(height: 12),
            EditorDateField(
              label: 'Applications open',
              value: draft.applicationsOpen,
              accent: accent,
              onChanged: (date) => setSheetState(() {
                draft = draft.copyWith(applicationsOpen: () => date);
              }),
            ),
            const SizedBox(height: 12),
            EditorDateField(
              label: 'Applications close',
              value: draft.applicationsClose,
              accent: accent,
              firstDate: draft.applicationsOpen,
              onChanged: (date) => setSheetState(() {
                draft = draft.copyWith(applicationsClose: () => date);
              }),
            ),
            const SizedBox(height: 20),

            EditorNumberField(
              label: 'Pitches available',
              hint: 'Leave blank for unlimited',
              controller: spacesController,
            ),
            const SizedBox(height: 20),

            TextField(
              controller: infoController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Information for traders',
                hintText: 'Pitch size, power, setup times…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Secret code (optional)',
                helperText: 'Gates the online payment link for this pitch type',
                border: OutlineInputBorder(),
              ),
            ),

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
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Name the pitch type')),
                        );
                        return;
                      }

                      Navigator.pop(
                        sheetContext,
                        draft.copyWith(
                          name: name,
                          info: infoController.text.trim(),
                          ticketCost: () =>
                              double.tryParse(costController.text.trim()),
                          spacesAvailable: () =>
                              int.tryParse(spacesController.text.trim()),
                          secretCode: codeController.text.trim(),
                        ),
                      );
                    },
                    child: Text(isNew ? 'Add pitch type' : 'Save'),
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

class _IconChoice extends StatelessWidget {
  final TraderIcon icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : Colors.white,
          border: Border.all(
            color: selected ? accent : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon.icon,
              size: 17,
              color: selected ? accent : Colors.grey.shade600,
            ),
            const SizedBox(width: 7),
            Text(
              icon.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
