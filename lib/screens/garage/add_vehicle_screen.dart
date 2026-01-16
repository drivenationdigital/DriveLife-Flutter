import 'dart:convert';
import 'dart:io';

import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class AddVehicleScreen extends StatefulWidget {
  final Map<String, dynamic>? vehicle; // ADD THIS

  const AddVehicleScreen({
    Key? key,
    this.vehicle, // ADD THIS
  }) : super(key: key);

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();

  File? _imageFile;
  String? _base64Image;

  String _ownership = 'current'; // current | past | dream_car
  DateTime? _ownedFrom;
  DateTime? _ownedTo;

  String? _make;
  final _modelCtrl = TextEditingController();
  final _variantCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  final _colourCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final _bhpCtrl = TextEditingController();
  final _zero62Ctrl = TextEditingController();
  final _topSpeedCtrl = TextEditingController();

  bool _taggingEnabled = false;

  bool _saving = false;

  bool get _isEditMode => widget.vehicle != null; // ADD THIS
  String? _existingImageUrl; // ADD THIS for keeping track of original image

  static const List<String> _makes = [
    'Abarth',
    'AC',
    'AK',
    'Alfa Romeo',
    'Alpine',
    'Alvis',
    'Ariel',
    'Aston Martin',
    'Audi',
    'Austin',
    'BAC',
    'Beauford',
    'Bentley',
    'BMW',
    'Bowler',
    'Bramwith',
    'Bugatti',
    'Buick',
    'BYD',
    'Cadillac',
    'Caterham',
    'Chesil',
    'Chevrolet',
    'Chrysler',
    'Citroen',
    'Corbin',
    'Corvette',
    'CUPRA',
    'Dacia',
    'Daewoo',
    'Daihatsu',
    'Daimler',
    'Datsun',
    'Dax',
    'Dodge',
    'DS AUTOMOBILES',
    'E-COBRA',
    'Ferrari',
    'Fiat',
    'Fisker',
    'Ford',
    'Gardner Douglas',
    'Genesis',
    'GMC',
    'Great Wall',
    'GWM ORA',
    'Hillman',
    'Honda',
    'Hummer',
    'Hyundai',
    'INEOS',
    'Infiniti',
    'ISO',
    'Isuzu',
    'Iveco',
    'JAECOO',
    'Jaguar',
    'Jeep',
    'Jensen',
    'KGM',
    'Kia',
    'KTM',
    'Lada',
    'Lamborghini',
    'Lancia',
    'Land Rover',
    'Leapmotor',
    'LEVC',
    'Lexus',
    'Leyland',
    'Lincoln',
    'Lotus',
    'Mahindra',
    'Marcos',
    'Maserati',
    'MAXUS',
    'Maybach',
    'Mazda',
    'McLaren',
    'Mercedes-Benz',
    'Mercury',
    'MG',
    'Micro',
    'MINI',
    'Mitsubishi',
    'Mitsuoka',
    'MK',
    'MOKE',
    'Morgan',
    'Morris',
    'Nardini',
    'NG',
    'Nissan',
    'Noble',
    'Omoda',
    'Opel',
    'Perodua',
    'Peugeot',
    'PGO',
    'Pilgrim',
    'Plymouth',
    'Polestar',
    'Pontiac',
    'Porsche',
    'Proton',
    'Radical',
    'Rage',
    'Ram',
    'Rayvolution',
    'RCR',
    'Reliant',
    'Renault',
    'Replica',
    'Riley',
    'Robin Hood',
    'Rolls-Royce',
    'Rover',
    'Saab',
    'SEAT',
    'Shelby',
    'Skoda',
    'Skywell',
    'Smart',
    'SsangYong',
    'Subaru',
    'Suzuki',
    'Tesla',
    'Tiger',
    'Toyota',
    'Triumph',
    'TVR',
    'Ultima',
    'Vauxhall',
    'Volkswagen',
    'Volvo',
    'VRS',
    'Westfield',
    'Yamaha',
    'Zenos',
    'Other / Not Listed',
  ];

  @override
  void initState() {
    super.initState();
    _loadVehicleData(); // ADD THIS
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _variantCtrl.dispose();
    _regCtrl.dispose();
    _colourCtrl.dispose();
    _descCtrl.dispose();
    _bhpCtrl.dispose();
    _zero62Ctrl.dispose();
    _topSpeedCtrl.dispose();
    super.dispose();
  }

  Future<void> _setImage(File file) async {
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);

    // Detect mime from extension (good enough for jpg/png)
    final lower = file.path.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';

    if (!mounted) return;
    setState(() {
      _imageFile = file;
      _base64Image = 'data:$mime;base64,$b64'; // ✅ matches JS
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (!mounted) return;
    if (x == null) return;

    await _setImage(File(x.path));
    setState(() => _imageFile = File(x.path));
  }

  Future<void> _pickDate({
    required bool isFrom,
    required ThemeProvider theme,
  }) async {
    final initial = (isFrom ? _ownedFrom : _ownedTo) ?? DateTime.now();
    final picked = await showDatePicker(
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: theme.primaryColor,
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: theme.primaryColor),
          ),
        ),
        child: child!,
      ),
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
      helpText: isFrom ? 'Select Owned From Date' : 'Select Owned To Date',
      confirmText: 'Select Date',
      // optional: restrict "Owned To" to be after "Owned From"
      selectableDayPredicate: (d) {
        // if picking owned from, then restrict dates after today
        if (!isFrom && _ownedFrom != null) {
          return d.isAfter(_ownedFrom!) || d.isAtSameMomentAs(_ownedFrom!);
        }
        return true;
      },
    );
    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      if (isFrom) {
        _ownedFrom = picked;
        // If "Owned To" exists and is now before "Owned From", clear it
        if (_ownedTo != null && _ownedTo!.isBefore(picked)) _ownedTo = null;
      } else {
        _ownedTo = picked;
      }
    });
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Select date';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day-$m-$y';
  }

  bool get _showOwnedTo => _ownership == 'past';

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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // UPDATE: _loadVehicleData method
  void _loadVehicleData() {
    if (!_isEditMode) return;

    final v = widget.vehicle!;

    print(v);

    setState(() {
      _make = v['make']?.toString();
      _modelCtrl.text = v['model']?.toString() ?? '';
      _variantCtrl.text = v['variant']?.toString() ?? '';
      _regCtrl.text = v['registration']?.toString() ?? '';
      _colourCtrl.text = v['colour']?.toString() ?? '';
      _descCtrl.text =
          v['short_description']?.toString() ?? ''; // FIX: short_description

      _bhpCtrl.text = v['vehicle_bhp']?.toString() ?? '';
      _zero62Ctrl.text = v['vehicle_062']?.toString() ?? '';
      _topSpeedCtrl.text = v['vehicle_top_speed']?.toString() ?? '';

      // FIX: Map primary_car to ownership
      final primaryCar = v['primary_car']?.toString();
      if (primaryCar == '1') {
        _ownership = 'current';
      } else if (primaryCar == '2') {
        _ownership = 'dream_car';
      } else {
        _ownership = 'past';
      }

      // FIX: allow_tagging is string "0" or "1"
      _taggingEnabled = (v['allow_tagging']?.toString() == '1');

      _ownedFrom = _parseDate(v['owned_since']);
      _ownedTo = _parseDate(v['owned_until']);

      // FIX: Store existing image URL
      _existingImageUrl = v['cover_photo']?.toString();
    });
  }

  // ADD THIS METHOD - remove image
  void _removeImage() {
    setState(() {
      _imageFile = null;
      _base64Image = null;
      _existingImageUrl = null;
    });
  }

  // ADD THIS HELPER METHOD
  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;

    final dateStr = dateValue.toString().trim();
    if (dateStr.isEmpty) return null;

    try {
      // Try ISO format first (2026-01-14T00:00:00.000)
      if (dateStr.contains('T') || dateStr.contains('-')) {
        return DateTime.parse(dateStr);
      }

      // Try dd/mm/yyyy format (16/01/2026)
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          return DateTime(
            int.parse(parts[2]), // year
            int.parse(parts[1]), // month
            int.parse(parts[0]), // day
          );
        }
      }
    } catch (e) {
      print('Error parsing date "$dateStr": $e');
    }

    return null;
  }

  // UPDATE: validation for images
  void _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    // Basic validations
    if (_make == null || _make!.isEmpty) {
      _toast('Please select a vehicle make');
      return;
    }

    if (_modelCtrl.text.trim().isEmpty) {
      _toast('Please enter a vehicle model');
      return;
    }

    final _isDream = _ownership == 'dream_car';

    if (!_isDream) {
      if (_ownedFrom != null && _ownedTo != null) {
        final from = _dateOnly(_ownedFrom!);
        final to = _dateOnly(_ownedTo!);
        if (to.isBefore(from)) {
          _toast('Owned to date cannot be less than owned from date');
          return;
        }
      }

      if (_ownership == 'past' && _ownedTo == null) {
        _toast('Please enter the date you owned the vehicle to');
        return;
      }
    }

    // UPDATE: Check for image - allow existing image in edit mode
    if (!_isEditMode &&
        (_imageFile == null || _base64Image == null || _base64Image!.isEmpty)) {
      _toast('Please upload a cover image');
      return;
    }

    final currentUser = Provider.of<UserProvider>(context, listen: false).user;

    if (currentUser == null) {
      _toast('User not logged in');
      return;
    }

    // Build payload
    final payload = <String, dynamic>{
      'make': _make,
      'model': _modelCtrl.text.trim(),
      'variant': _variantCtrl.text.trim(),
      'registration': _regCtrl.text.trim(),
      'colour': _colourCtrl.text.trim(),
      'ownedFrom': _ownedFrom?.toIso8601String() ?? '',
      'ownedTo': _ownedTo?.toIso8601String() ?? '',
      'primary_car': _ownership,
      'allow_tagging': _taggingEnabled ? 1 : 0,
      'vehicle_period': _ownership,
      'description': _descCtrl.text.trim(),
      'vehicle_bhp': int.tryParse(_bhpCtrl.text.trim()) ?? 0,
      'vehicle_062': double.tryParse(_zero62Ctrl.text.trim()) ?? 0,
      'vehicle_top_speed': double.tryParse(_topSpeedCtrl.text.trim()) ?? 0,
    };

    // UPDATE: Only include cover_photo if changed
    if (_base64Image != null && _base64Image!.isNotEmpty) {
      payload['cover_photo'] = _base64Image;
    } else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      payload['cover_photo'] = _existingImageUrl; // Keep existing
    }

    setState(() => _saving = true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final dynamic res;

      // UPDATE: Call different API based on mode
      if (_isEditMode) {
        res = await GarageAPI.addVehicleToGarage(
          // widget.vehicle!['id'].toString(),
          payload,
          currentUser['id'].toString(),
        );
      } else {
        res = await GarageAPI.addVehicleToGarage(
          payload,
          currentUser['id'].toString(),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // hide loader

      final success = (res is Map) ? (res['success'] == true) : false;
      if (!success) {
        throw Exception(
          _isEditMode ? 'Failed to update vehicle' : 'Failed to add vehicle',
        );
      }

      // After successful save/update
      _toast(
        _isEditMode
            ? 'Vehicle updated successfully'
            : 'Vehicle added successfully',
      );

      final vehicleId = (res is Map) ? res['id'] : widget.vehicle?['id'];

      // Return 'updated' for edit, vehicleId for add
      Navigator.pop(context, _isEditMode ? 'updated' : vehicleId);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final msg = (e is Map && e['message'] != null)
          ? e['message'].toString()
          : (e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : (_isEditMode
                      ? 'Failed to update vehicle'
                      : 'Failed to add vehicle'));

      _toast(msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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

  // UPDATE: Image section with remove button
  Widget _buildImageSection() {
    final hasImage =
        _imageFile != null ||
        (_existingImageUrl != null && _existingImageUrl!.isNotEmpty);

    return _card(
      child: InkWell(
        onTap: _pickImage,
        child: Container(
          height: 120,
          alignment: Alignment.center,
          child: !hasImage
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 32,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 6),
                    Text('Tap to Upload', style: TextStyle(color: Colors.grey)),
                  ],
                )
              : Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _imageFile != null
                          ? Image.file(
                              _imageFile!,
                              width: double.infinity,
                              height: 120,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              _existingImageUrl!,
                              width: double.infinity,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                    ),
                    // Remove button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () {
                          _removeImage();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    // Change indicator
                    if (_imageFile != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'New',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // ADD TO _AddVehicleScreenState
  Future<void> _deleteVehicle(ThemeProvider theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'Delete Vehicle',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete this vehicle? This action cannot be undone.',
        ),
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
        builder: (_) =>
            Center(child: CircularProgressIndicator(color: theme.primaryColor)),
      );

      final res = await GarageAPI.deleteVehicle(
        widget.vehicle!['id'].toString(),
        currentUser['id'].toString(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // hide loader

      final success = (res is Map) ? (res?['success'] == true) : false;
      if (!success) {
        throw Exception('Failed to delete vehicle');
      }

      _toast('Vehicle deleted successfully');
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final msg = (e is Map && e['message'] != null)
          ? e['message'].toString()
          : (e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : 'Failed to delete vehicle');

      _toast(msg);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          _isEditMode ? 'Edit Vehicle' : 'Add Vehicle', // UPDATE THIS
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditMode ? 'Update' : 'Save', // UPDATE THIS
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
              _sectionTitle('Vehicle Image'),
              _buildImageSection(),

              _sectionTitle('Ownership Type'),
              _card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: DropdownButtonFormField<String>(
                        value: _ownership,
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        decoration: _dec('Ownership *'),
                        items: const [
                          DropdownMenuItem(
                            value: 'current',
                            child: Text('Current Vehicle'),
                          ),
                          DropdownMenuItem(
                            value: 'past',
                            child: Text('Past Vehicle'),
                          ),
                          DropdownMenuItem(
                            value: 'dream_car',
                            child: Text('Dream Vehicle'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _ownership = v;
                            if (_ownership != 'past') _ownedTo = null;
                          });
                        },
                      ),
                    ),
                    _divider(),
                    if (_ownership != 'dream_car') ...[
                      ListTile(
                        title: const Text('Owned From'),
                        subtitle: Text(_fmtDate(_ownedFrom)),
                        trailing: const Icon(Icons.arrow_drop_down),
                        onTap: () => _pickDate(isFrom: true, theme: theme),
                      ),
                    ],
                    if (_showOwnedTo) ...[
                      _divider(),
                      ListTile(
                        title: const Text('Owned To'),
                        subtitle: Text(_fmtDate(_ownedTo)),
                        trailing: const Icon(Icons.arrow_drop_down),
                        onTap: () => _pickDate(isFrom: false, theme: theme),
                      ),
                    ],
                  ],
                ),
              ),

              _sectionTitle('Vehicle Details'),
              _card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: DropdownButtonFormField<String>(
                        dropdownColor: theme.cardColor,
                        focusColor: theme.primaryColor,
                        value: _make,
                        decoration: _dec(
                          'Vehicle Make *',
                          hint: 'Please Select',
                        ),
                        items: _makes
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Please select a make';
                          return null;
                        },
                        onChanged: (v) => setState(() => _make = v),
                      ),
                    ),
                    _divider(),
                    TextFormField(
                      controller: _modelCtrl,
                      decoration: _dec('Model *', hint: 'Your vehicle model'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Model is required'
                          : null,
                    ),
                    _divider(),
                    TextFormField(
                      controller: _variantCtrl,
                      decoration: _dec(
                        'Variant',
                        hint: 'Add any vehicle variant info',
                      ),
                    ),
                    _divider(),
                    TextFormField(
                      controller: _regCtrl,
                      decoration: _dec(
                        'Registration',
                        hint: 'Your vehicle reg',
                      ),
                    ),
                    _divider(),
                    TextFormField(
                      controller: _colourCtrl,
                      decoration: _dec('Colour', hint: 'Your vehicle colour'),
                    ),
                    _divider(),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: _dec(
                        'Short Description',
                        hint: 'Add a short description of your vehicle',
                      ),
                      maxLength: 200,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              _sectionTitle('Vehicle Stats'),
              _card(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _bhpCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _dec('Power (BHP)', hint: 'Enter BHP'),
                    ),
                    _divider(),
                    TextFormField(
                      controller: _zero62Ctrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _dec(
                        '0 - 62mph time',
                        hint: 'Enter 0-62 time',
                      ),
                    ),
                    _divider(),
                    TextFormField(
                      controller: _topSpeedCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _dec(
                        'Top Speed (MPH)',
                        hint: 'Enter top speed',
                      ),
                    ),
                  ],
                ),
              ),

              _sectionTitle('Vehicle Tagging'),
              _card(
                child: SwitchListTile(
                  title: const Text(
                    "Allow this vehicle to be discovered & tagged via it's registration",
                  ),
                  value: _taggingEnabled,
                  onChanged: (v) => setState(() => _taggingEnabled = v),
                ),
              ),

              // DELETE BUTTON - only in edit mode
              if (_isEditMode) ...[
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _deleteVehicle(theme),
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
                              'Delete Vehicle',
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
