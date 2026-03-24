import 'package:drivelife/api/garage_reminders_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddReminderScreen extends StatefulWidget {
  final String garageId;
  final Map<String, dynamic>? reminder; // For edit mode

  const AddReminderScreen({Key? key, required this.garageId, this.reminder})
    : super(key: key);

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _reminderType;
  final _customTypeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _reminderDate;

  bool _saving = false;

  static const List<String> _reminderTypes = [
    'MOT',
    'Service',
    'Insurance Renewal',
    'Other',
    'Warranty',
  ];

  bool get _isEditMode => widget.reminder != null;
  bool get _isOtherType => _reminderType == 'Other';

  @override
  void initState() {
    super.initState();
    _loadReminderData();
  }

  @override
  void dispose() {
    _customTypeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _loadReminderData() {
    if (!_isEditMode) return;

    final r = widget.reminder!;

    setState(() {
      _reminderType = r['reminder_type']?.toString();
      _notesCtrl.text = r['notes']?.toString() ?? '';

      if (_reminderType != null && !_reminderTypes.contains(_reminderType)) {
        _customTypeCtrl.text = _reminderType!;
        _reminderType = 'Other';
      }

      final dateStr = r['reminder_date']?.toString();
      if (dateStr != null) {
        _reminderDate = DateTime.tryParse(dateStr);
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _reminderDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      builder: (context, child) {
        final theme = Provider.of<ThemeProvider>(context, listen: false);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: theme.primaryColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _reminderDate = picked);
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    if (_reminderType == null) {
      _toast('Please select a reminder type');
      return;
    }

    if (_isOtherType && _customTypeCtrl.text.trim().isEmpty) {
      _toast('Please enter a reminder type');
      return;
    }

    if (_reminderDate == null) {
      _toast('Please select a reminder date');
      return;
    }

    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser == null) {
      _toast('User not logged in');
      return;
    }

    final payload = <String, dynamic>{
      'garage_id': widget.garageId,
      'reminder_type': _isOtherType
          ? _customTypeCtrl.text.trim()
          : _reminderType,
      'reminder_date': _reminderDate!.toIso8601String(),
      'notes': _notesCtrl.text.trim(),
    };

    setState(() => _saving = true);

    try {
      // TODO: API call here
      if (_isEditMode) {
        await ReminderApiService.updateReminder(payload, widget.reminder!['id'].toString(), currentUser.id.toString());
      } else {
        await ReminderApiService.addReminder(payload, currentUser.id.toString());
      }

      await Future.delayed(const Duration(seconds: 1)); // placeholder

      if (!mounted) return;

      _toast(
        _isEditMode
            ? 'Reminder updated successfully'
            : 'Reminder added successfully',
      );

      Navigator.pop(context, _isEditMode ? 'updated' : 'added');
    } catch (e) {
      if (!mounted) return;
      _toast(
        _isEditMode ? 'Failed to update reminder' : 'Failed to add reminder',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteReminder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure you want to delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser == null) {
      _toast('User not logged in');
      return;
    }

    setState(() => _saving = true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFAE9159)),
        ),
      );

      await ReminderApiService.deleteReminder(widget.reminder!['id'].toString(), currentUser.id.toString());
      await Future.delayed(const Duration(seconds: 1)); // placeholder

      if (!mounted) return;
      Navigator.of(context).pop(); // hide loader

      _toast('Reminder deleted successfully');
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast('Failed to delete reminder');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Helpers (mirrored from AddModificationScreen) ──────────────────────────

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE9E9E9)),
        ),
        child: child,
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: InputBorder.none,
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFEFEFEF));

  // ── Date field ─────────────────────────────────────────────────────────────

  Widget _buildDateField() {
    final hasDate = _reminderDate != null;
    final displayText = hasDate
        ? '${_reminderDate!.day.toString().padLeft(2, '0')}/'
              '${_reminderDate!.month.toString().padLeft(2, '0')}/'
              '${_reminderDate!.year}'
        : null;

    return InkWell(
      onTap: _pickDate,
      child: InputDecorator(
        decoration: _dec('Reminder Date *', hint: 'DD/MM/YYYY').copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(
          displayText ?? 'DD/MM/YYYY',
          style: TextStyle(
            fontSize: 16,
            color: hasDate ? Colors.black87 : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          _isEditMode ? 'Edit Reminder' : 'Add Reminder',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _onSave,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFAE9159),
                    ),
                  )
                : Text(
                    _isEditMode ? 'Update' : 'Save',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _sectionTitle('Reminder Details'),
              _card(
                child: Column(
                  children: [
                    // Reminder type dropdown
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _reminderType,
                        dropdownColor: Colors.white,
                        decoration: _dec(
                          'Reminder Type *',
                          hint: 'Please Select',
                        ),
                        items: _reminderTypes
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Please select a reminder type'
                            : null,
                        onChanged: (v) => setState(() {
                          _reminderType = v;
                          if (v != 'Other') _customTypeCtrl.clear();
                        }),
                      ),
                    ),

                    // "Other" free-text — animates in/out
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: _isOtherType
                          ? Column(
                              children: [
                                _divider(),
                                TextFormField(
                                  controller: _customTypeCtrl,
                                  decoration: _dec(
                                    'Specify Type *',
                                    hint: 'e.g. Tax, Breakdown Cover',
                                  ),
                                  validator: (v) =>
                                      (_isOtherType &&
                                          (v == null || v.trim().isEmpty))
                                      ? 'Please specify the reminder type'
                                      : null,
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),

                    _divider(),

                    // Date picker row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _buildDateField(),
                    ),

                    _divider(),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: _dec(
                        'Notes',
                        hint: 'Any additional notes about this reminder',
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),
                  ],
                ),
              ),

              // Delete button — edit mode only
              if (_isEditMode) ...[
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _deleteReminder,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: const BorderSide(color: Colors.red),
                        foregroundColor: Colors.red,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.red,
                              ),
                            )
                          : const Text(
                              'Delete Reminder',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
