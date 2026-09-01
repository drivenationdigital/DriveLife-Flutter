import 'package:drivelife/models/event_editor_models.dart';
import 'package:drivelife/widgets/events/editor/editor_fields.dart';
import 'package:flutter/material.dart';

/// Car clubs — stand applications from clubs who want to pitch up together.
///
/// Mirrors `CarClubsPanel.tsx`. Unlike show cars and traders there are no
/// categories: a club either gets a stand or it doesn't, so this is one set of
/// settings.
class CarClubsTab extends StatefulWidget {
  final CarClubsConfig config;
  final ValueChanged<CarClubsConfig> onChanged;
  final Color accent;

  const CarClubsTab({
    super.key,
    required this.config,
    required this.onChanged,
    this.accent = kEditorGold,
  });

  @override
  State<CarClubsTab> createState() => _CarClubsTabState();
}

class _CarClubsTabState extends State<CarClubsTab> {
  late final TextEditingController _maxController;
  late final TextEditingController _costController;
  late final TextEditingController _infoController;

  @override
  void initState() {
    super.initState();
    _maxController = TextEditingController(
      text: widget.config.max?.toString() ?? '',
    );
    _costController = TextEditingController(
      text: widget.config.ticketCost?.toString() ?? '',
    );
    _infoController = TextEditingController(text: widget.config.info);
  }

  @override
  void dispose() {
    _maxController.dispose();
    _costController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  CarClubsConfig get _config => widget.config;

  /// Pushes the free-text and numeric fields up alongside a structural change.
  ///
  /// The controllers are the source of truth while typing; folding them in on
  /// every change keeps the parent's copy current without a listener per field.
  void _emit(CarClubsConfig next) {
    widget.onChanged(
      next.copyWith(
        max: () => int.tryParse(_maxController.text.trim()),
        ticketCost: () => double.tryParse(_costController.text.trim()),
        info: _infoController.text,
      ),
    );
  }

  Future<void> _pickTime({
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    final hour = picked.hour.toString().padLeft(2, '0');
    final minute = picked.minute.toString().padLeft(2, '0');
    onPicked('$hour:$minute');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        EditorToggleRow(
          title: 'Accept car club stands',
          subtitle:
              'Let clubs apply for a stand so their members can park together.',
          value: _config.enabled,
          accent: widget.accent,
          onChanged: (value) => _emit(_config.copyWith(enabled: value)),
        ),

        if (!_config.enabled) ...[
          const SizedBox(height: 20),
          Text(
            'Turn this on to set an application window and stand limits.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ] else ...[
          const SizedBox(height: 24),
          const EditorSectionHeader(
            title: 'Application window',
            subtitle: 'When clubs can apply. Leave a date unset for no limit.',
          ),
          const SizedBox(height: 12),

          EditorDateField(
            label: 'Applications open',
            value: _config.applicationsOpen,
            accent: widget.accent,
            onChanged: (date) =>
                _emit(_config.copyWith(applicationsOpen: () => date)),
          ),
          const SizedBox(height: 12),
          _TimeField(
            label: 'Opening time',
            value: _config.applicationsOpenTime,
            onTap: () => _pickTime(
              current: _config.applicationsOpenTime,
              onPicked: (time) =>
                  _emit(_config.copyWith(applicationsOpenTime: time)),
            ),
          ),
          const SizedBox(height: 16),
          EditorDateField(
            label: 'Applications close',
            value: _config.applicationsClose,
            accent: widget.accent,
            firstDate: _config.applicationsOpen,
            onChanged: (date) =>
                _emit(_config.copyWith(applicationsClose: () => date)),
          ),
          const SizedBox(height: 12),
          _TimeField(
            label: 'Closing time',
            value: _config.applicationsCloseTime,
            onTap: () => _pickTime(
              current: _config.applicationsCloseTime,
              onPicked: (time) =>
                  _emit(_config.copyWith(applicationsCloseTime: time)),
            ),
          ),

          const SizedBox(height: 24),
          EditorToggleRow(
            title: 'Cap the number of clubs',
            subtitle: 'How many club stands you have room for.',
            value: _config.limitEnabled,
            accent: widget.accent,
            onChanged: (value) => _emit(_config.copyWith(limitEnabled: value)),
          ),
          if (_config.limitEnabled) ...[
            const SizedBox(height: 12),
            EditorNumberField(
              label: 'Maximum clubs',
              hint: 'e.g. 20',
              controller: _maxController,
            ),
          ],

          const SizedBox(height: 24),
          EditorToggleRow(
            title: 'Charge for a stand',
            subtitle:
                'Approved clubs get a link to pay. Free stands are confirmed '
                'on approval instead.',
            value: _config.requireTicket,
            accent: widget.accent,
            onChanged: (value) => _emit(_config.copyWith(requireTicket: value)),
          ),
          if (_config.requireTicket) ...[
            const SizedBox(height: 12),
            EditorNumberField(
              label: 'Stand cost',
              controller: _costController,
              allowDecimal: true,
              prefixText: '£ ',
            ),
          ],

          const SizedBox(height: 24),
          const EditorSectionHeader(
            title: 'Information for clubs',
            subtitle:
                'Shown on the application form. Stand size, arrival, what is '
                'included.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _infoController,
            maxLines: 5,
            onChanged: (value) => widget.onChanged(_config.copyWith(info: value)),
            decoration: const InputDecoration(
              hintText: 'Stands are 6x6m, arrive before 8am…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// Read-only field that opens a time picker. Paired with a date field, since
/// the dashboard stores the window as separate date and time values.
class _TimeField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.schedule, size: 18),
        ),
        child: Text(value, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
