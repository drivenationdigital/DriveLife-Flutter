import 'package:drivelife/models/event_editor_models.dart';
import 'package:drivelife/widgets/events/editor/editor_fields.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Show cars — entry classes attendees apply to display a car in.
///
/// Mirrors `ShowCarsPanel.tsx`. The whole section is gated by one toggle,
/// matching the dashboard: an event that isn't taking show-car entries should
/// not carry half-configured categories.
class ShowCarsTab extends StatelessWidget {
  final ShowCarsConfig config;
  final ValueChanged<ShowCarsConfig> onChanged;
  final Color accent;

  const ShowCarsTab({
    super.key,
    required this.config,
    required this.onChanged,
    this.accent = kEditorGold,
  });

  Future<void> _editCategory(
    BuildContext context,
    ShowCarCategory? existing,
  ) async {
    final result = await _showCategoryEditor(
      context: context,
      accent: accent,
      original: existing ?? ShowCarCategory.blank(),
      isNew: existing == null,
    );

    if (result == null) return;

    final next = List<ShowCarCategory>.from(config.categories);
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
          title: 'Accept show car entries',
          subtitle:
              'Let attendees apply to display a car. Applications are reviewed '
              'before a place is confirmed.',
          value: config.enabled,
          accent: accent,
          onChanged: (value) => onChanged(config.copyWith(enabled: value)),
        ),

        if (!config.enabled) ...[
          const SizedBox(height: 20),
          Text(
            'Turn this on to set up entry classes and application windows.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ] else ...[
          const SizedBox(height: 22),
          _OverallLimit(config: config, onChanged: onChanged, accent: accent),
          const SizedBox(height: 24),

          const EditorSectionHeader(
            title: 'Entry classes',
            subtitle:
                'Each class has its own application window, spaces and cost — '
                'for example Modified, Classics, Show & Shine.',
          ),
          const SizedBox(height: 14),

          if (config.categories.isEmpty)
            EditorEmptyState(
              icon: Icons.directions_car_outlined,
              title: 'No entry classes',
              message:
                  'Add at least one class so entrants know what they are '
                  'applying for.',
              actionLabel: 'Add a class',
              accent: accent,
              onAction: () => _editCategory(context, null),
            )
          else ...[
            for (final category in config.categories) ...[
              _CategoryCard(
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
              label: const Text('Add another class'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],

          const SizedBox(height: 24),
          _InfoField(config: config, onChanged: onChanged),
        ],
      ],
    );
  }
}

class _OverallLimit extends StatefulWidget {
  final ShowCarsConfig config;
  final ValueChanged<ShowCarsConfig> onChanged;
  final Color accent;

  const _OverallLimit({
    required this.config,
    required this.onChanged,
    required this.accent,
  });

  @override
  State<_OverallLimit> createState() => _OverallLimitState();
}

class _OverallLimitState extends State<_OverallLimit> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.config.max?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorToggleRow(
          title: 'Cap total show cars',
          subtitle: 'A limit across every class combined.',
          value: widget.config.limitEnabled,
          accent: widget.accent,
          onChanged: (value) =>
              widget.onChanged(widget.config.copyWith(limitEnabled: value)),
        ),
        if (widget.config.limitEnabled) ...[
          const SizedBox(height: 12),
          EditorNumberField(
            label: 'Maximum show cars',
            hint: 'e.g. 150',
            controller: _controller,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => widget.onChanged(
              widget.config.copyWith(
                max: () => int.tryParse(_controller.text.trim()),
              ),
            ),
            child: const Text('Apply limit'),
          ),
        ],
      ],
    );
  }
}

class _InfoField extends StatefulWidget {
  final ShowCarsConfig config;
  final ValueChanged<ShowCarsConfig> onChanged;

  const _InfoField({required this.config, required this.onChanged});

  @override
  State<_InfoField> createState() => _InfoFieldState();
}

class _InfoFieldState extends State<_InfoField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.config.info,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionHeader(
          title: 'Information for entrants',
          subtitle: 'Shown on the application form. Arrival times, rules, what '
              'to bring.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 5,
          onChanged: (value) =>
              widget.onChanged(widget.config.copyWith(info: value)),
          decoration: const InputDecoration(
            hintText: 'Gates open at 7am for show cars…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ShowCarCategory category;
  final Color accent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({
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
      return 'Applications ${format.format(open)} – ${format.format(close)}';
    }
    return open != null
        ? 'Applications open ${format.format(open)}'
        : 'Applications close ${format.format(close!)}';
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
              Expanded(
                child: Text(
                  category.name.isEmpty ? 'Untitled class' : category.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
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
          if (category.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              category.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: kEditorMuted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: category.requireTicket
                    ? (category.ticketCost == null
                          ? 'Ticket required'
                          : '£${category.ticketCost!.toStringAsFixed(2)}')
                    : 'Free entry',
                accent: accent,
                strong: true,
              ),
              _Pill(
                label: category.spacesAvailable == null
                    ? 'Unlimited spaces'
                    : '${category.spacesAvailable} spaces',
                accent: accent,
              ),
              if (_window != null) _Pill(label: _window!, accent: accent),
              if (category.secretCode.isNotEmpty)
                _Pill(label: 'Code set', accent: accent),
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

Future<ShowCarCategory?> _showCategoryEditor({
  required BuildContext context,
  required Color accent,
  required ShowCarCategory original,
  required bool isNew,
}) {
  var draft = original;

  final nameController = TextEditingController(text: original.name);
  final descriptionController = TextEditingController(
    text: original.description,
  );
  final spacesController = TextEditingController(
    text: original.spacesAvailable?.toString() ?? '',
  );
  final costController = TextEditingController(
    text: original.ticketCost?.toString() ?? '',
  );
  final codeController = TextEditingController(text: original.secretCode);

  return showEditorSheet<ShowCarCategory>(
    context: context,
    title: isNew ? 'New entry class' : 'Edit entry class',
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
                labelText: 'Class name *',
                hintText: 'Modified',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What belongs in this class',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            const EditorSectionHeader(
              title: 'Application window',
              subtitle: 'When entrants can apply for this class.',
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
              label: 'Spaces available',
              hint: 'Leave blank for unlimited',
              controller: spacesController,
            ),
            const SizedBox(height: 20),

            EditorToggleRow(
              title: 'Charge for this class',
              subtitle:
                  'Approved entrants get a link to pay. Free classes are '
                  'confirmed on approval instead.',
              value: draft.requireTicket,
              accent: accent,
              onChanged: (value) => setSheetState(() {
                draft = draft.copyWith(requireTicket: value);
              }),
            ),
            if (draft.requireTicket) ...[
              const SizedBox(height: 12),
              EditorNumberField(
                label: 'Entry cost',
                controller: costController,
                allowDecimal: true,
                prefixText: '£ ',
              ),
            ],
            const SizedBox(height: 20),

            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Secret code (optional)',
                helperText:
                    'Gates the ticket link for this class, so each class gets '
                    'its own link',
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
                          const SnackBar(content: Text('Name the class')),
                        );
                        return;
                      }

                      Navigator.pop(
                        sheetContext,
                        draft.copyWith(
                          name: name,
                          description: descriptionController.text.trim(),
                          spacesAvailable: () =>
                              int.tryParse(spacesController.text.trim()),
                          ticketCost: () =>
                              double.tryParse(costController.text.trim()),
                          secretCode: codeController.text.trim(),
                        ),
                      );
                    },
                    child: Text(isNew ? 'Add class' : 'Save'),
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
