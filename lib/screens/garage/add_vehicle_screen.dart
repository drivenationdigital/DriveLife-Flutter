import 'dart:convert';
import 'dart:io';
import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class AddVehicleScreen extends StatefulWidget {
  final Map<String, dynamic>? vehicle;

  const AddVehicleScreen({Key? key, this.vehicle}) : super(key: key);

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();

  File? _imageFile;
  String? _base64Image;
  bool _lookingUp = false;

  String _ownership = 'current';
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

  // ADD: Upload progress tracking
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  bool get _isEditMode => widget.vehicle != null;
  String? _existingImageUrl;

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
    _loadVehicleData();
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

    final lower = file.path.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';

    if (!mounted) return;
    setState(() {
      _imageFile = file;
      _base64Image = 'data:$mime;base64,$b64';
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
    // final initial = (isFrom ? _ownedFrom : _ownedTo) ?? DateTime.now();
    final initial = isFrom
        ? (_ownedFrom ?? DateTime.now())
        : (_ownedTo ??
              _ownedFrom ??
              DateTime.now()); // prefer _ownedFrom as fallback
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
      selectableDayPredicate: (d) {
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
    return '$day/$m/$y';
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

  void _loadVehicleData() {
    if (!_isEditMode) return;

    final v = widget.vehicle!;

    setState(() {
      _make = v['make']?.toString();
      _modelCtrl.text = v['model']?.toString() ?? '';
      _variantCtrl.text = v['variant']?.toString() ?? '';
      _regCtrl.text = v['registration']?.toString() ?? '';
      _colourCtrl.text = v['colour']?.toString() ?? '';
      _descCtrl.text = v['short_description']?.toString() ?? '';

      _bhpCtrl.text = v['vehicle_bhp']?.toString() ?? '';
      _zero62Ctrl.text = v['vehicle_062']?.toString() ?? '';
      _topSpeedCtrl.text = v['vehicle_top_speed']?.toString() ?? '';

      final primaryCar = v['primary_car']?.toString();
      if (primaryCar == '1') {
        _ownership = 'current';
      } else if (primaryCar == '2') {
        _ownership = 'dream_car';
      } else {
        _ownership = 'past';
      }

      _taggingEnabled = (v['allow_tagging']?.toString() == '1');

      _ownedFrom = _parseDate(v['owned_since']);
      _ownedTo = _parseDate(v['owned_until']);

      _existingImageUrl = v['cover_photo']?.toString();
    });
  }

  void _removeImage() {
    setState(() {
      _imageFile = null;
      _base64Image = null;
      _existingImageUrl = null;
    });
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;

    final dateStr = dateValue.toString().trim();
    if (dateStr.isEmpty) return null;

    try {
      if (dateStr.contains('T') || dateStr.contains('-')) {
        return DateTime.parse(dateStr);
      }

      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          return DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      }
    } catch (e) {
      print('Error parsing date "$dateStr": $e');
    }

    return null;
  }

  void _onSave() async {
    FocusScope.of(context).unfocus(); // 👈 dismisses keyboard
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

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

      // if (_ownership == 'past' && _ownedTo == null) {
      //   _toast('Please enter the date you owned the vehicle to');
      //   return;
      // }
    }

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

    if (_base64Image != null && _base64Image!.isNotEmpty) {
      payload['cover_photo'] = _base64Image;
    } else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      payload['cover_photo'] = _existingImageUrl;
    }

    setState(() {
      _saving = true;
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStatus = 'Preparing upload...';
    });

    try {
      final dynamic res;

      if (_isEditMode) {
        res = await GarageAPI.updateVehicle(
          widget.vehicle!['id'].toString(),
          payload,
          currentUser.id.toString(),
          onUploadProgress: (current, total, percentage) {
            if (mounted) {
              setState(() {
                _uploadProgress = percentage;
                _uploadStatus = 'Uploading ${current + 1}/$total chunks';
              });
            }
          },
        );
      } else {
        res = await GarageAPI.addVehicleToGarage(
          payload,
          currentUser.id.toString(),
          onUploadProgress: (current, total, percentage) {
            if (mounted) {
              setState(() {
                _uploadProgress = percentage;
                _uploadStatus = 'Uploading ${current + 1}/$total chunks';
              });
            }
          },
        );
      }

      if (!mounted) return;

      final success = (res is Map) ? (res['success'] == true) : false;
      if (!success) {
        throw Exception(
          _isEditMode ? 'Failed to update vehicle' : 'Failed to add vehicle',
        );
      }

      _toast(
        _isEditMode
            ? 'Vehicle updated successfully'
            : 'Vehicle added successfully',
      );

      final vehicleId = (res is Map) ? res['id'] : widget.vehicle?['id'];

      Navigator.pop(context, _isEditMode ? 'updated' : vehicleId);
    } catch (e) {
      if (!mounted) return;

      final msg = (e is Map && e['message'] != null)
          ? e['message'].toString()
          : (e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : (_isEditMode
                      ? 'Failed to update vehicle'
                      : 'Failed to add vehicle'));

      _toast(msg);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadStatus = '';
        });
      }
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
      // Pin the label colour in ALL states — stops the purple flash
      labelStyle: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: TextStyle(
        color:
            Colors.grey.shade600, // ← same grey when floated (was theme purple)
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(color: Colors.grey.shade400),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // ... keep whatever else you already have in here
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFEFEFEF));

  /// Dropdowns get the field decoration's own padding rather than a wrapper of
  /// their own, so their caret lines up with the rows above and below.
  static const Widget _caret = Icon(
    Icons.keyboard_arrow_down_rounded,
    size: 22,
    color: Color(0xFF9A9A9A),
  );

  /// A date row built to read like the text fields around it: small grey label,
  /// value beneath, same 14px inset.
  Widget _dateRow({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmtDate(date),
                    style: TextStyle(
                      fontSize: 16,
                      color: date == null
                          ? Colors.grey.shade500
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Colors.grey.shade500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoFillButton() {
    const gold = Color(0xFFC4A062);

    return Tooltip(
      message: 'Auto fill from registration',
      child: Material(
        color: gold.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _lookingUp ? null : _handleRegLookup,
          child: SizedBox(
            width: 36,
            height: 36,
            child: _lookingUp
                ? CircularProgressIndicator(
                      padding: EdgeInsets.all(14),
                      strokeWidth: 2,
                      color: gold,
                    )
                : const Icon(
                    Icons.auto_fix_high_rounded,
                    size: 18,
                    color: gold,
                  ),
          ),
        ),
      ),
    );
  }

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
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _removeImage,
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
        currentUser.id.toString(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();

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

  Future<void> _handleRegLookup() async {
    final reg = _regCtrl.text.trim().toUpperCase().replaceAll(' ', '');

    if (reg.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a registration first')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _lookingUp = true);

    final res = await GarageAPI.lookupVehicleByReg(reg);

    if (!mounted) return;
    setState(() => _lookingUp = false);

    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle not found — check the reg and try again'),
        ),
      );
      return;
    }

    final data = _unwrapLookup(res);

    // The spec provider returns the same field in several places with varying
    // quality (ModelData is properly cased, DVLA/SMMT are SHOUTED), so each of
    // these reads the best source first and degrades to the rougher ones.
    final make = _lookupString(data, const [
      'ModelData.Make',
      'SmmtDetails.Marque',
      'VehicleIdentification.DvlaMake',
      'make',
    ]);
    final range = _lookupString(data, const [
      'ModelData.Range',
      'SmmtDetails.Range',
      'VehicleIdentification.DvlaModel',
      'model',
    ]);
    final fullModel = _lookupString(data, const ['ModelData.Model']);
    final variantBadge = _lookupString(data, const [
      'ModelData.ModelVariant',
      'SmmtDetails.Variant',
    ]);
    final colourRaw = _lookupString(data, const [
      'ColourDetails.CurrentColour',
      'ColourDetails.OriginalColour',
      'colour',
    ]);
    final fuelRaw = _lookupString(data, const [
      'ModelData.FuelType',
      'VehicleIdentification.DvlaFuelType',
      'SmmtDetails.FuelType',
      'fuel_type',
    ]);
    final aspiration = _lookupString(data, const [
      'PowerSource.IceDetails.Aspiration',
      'SmmtDetails.Aspiration',
    ]);
    final year = _lookupString(data, const [
      'VehicleIdentification.YearOfManufacture',
      'year_of_manufacture',
    ]);
    final bhp = _lookupString(data, const [
      'Performance.Power.Bhp',
      'SmmtDetails.PowerBhp',
    ]);
    final zeroToSixty = _lookupString(data, const [
      'Performance.Statistics.ZeroToSixtyMph',
    ]);
    final topSpeed = _lookupString(data, const [
      'Performance.Statistics.MaxSpeedMph',
      'SmmtDetails.MaxSpeedMph',
    ]);

    final isElectric =
        _lookupString(data, const ['PowerSource.VehicleType']).toUpperCase() ==
        'BEV';

    final model = _titleCase(range);
    final colour = _titleCase(colourRaw);
    final fuel = isElectric && fuelRaw.isEmpty ? 'Electric' : _titleCase(fuelRaw);

    // Engine size, e.g. "1.4L". Electric cars have none.
    final engine = isElectric
        ? ''
        : _engineLitres(
            _lookupString(data, const [
              'PowerSource.IceDetails.EngineCapacityLitres',
              'DvlaTechnicalDetails.EngineCapacityCc',
              'PowerSource.IceDetails.EngineCapacityCc',
              'SmmtDetails.EngineCapacity',
              'engine_capacity',
            ]),
          );

    // Trim — "Astra SRi T" minus the range gives "SRi T". Falls back to the
    // SHOUTED badge ("SRI"), which is left as-is: trim names are acronyms and
    // title-casing them reads worse than leaving them alone.
    var trim = '';
    if (fullModel.isNotEmpty &&
        range.isNotEmpty &&
        fullModel.toLowerCase().startsWith(range.toLowerCase())) {
      trim = fullModel.substring(range.length).trim();
    }
    if (trim.isEmpty) trim = variantBadge;

    final spec = [
      trim,
      engine,
      if (aspiration.toLowerCase().contains('turbo') &&
          !trim.toLowerCase().contains('turbo'))
        'Turbo',
      fuel,
    ].where((p) => p.isNotEmpty).join(' ');

    setState(() {
      // Make — match against the dropdown list (case-insensitive). A make the
      // list doesn't carry clears the field, so it can't keep showing the make
      // of the reg looked up before this one.
      final match = _makes.firstWhere(
        (m) => m.toLowerCase() == make.toLowerCase(),
        orElse: () => '',
      );
      _make = match.isEmpty ? null : match;

      _applyLookup(_modelCtrl, model);
      _applyLookup(_colourCtrl, colour);
      _applyLookup(_variantCtrl, spec);

      _applyLookup(_bhpCtrl, _fmtNum(bhp));
      _applyLookup(_zero62Ctrl, _fmtNum(zeroToSixty));
      _applyLookup(_topSpeedCtrl, _fmtNum(topSpeed));

      // Short description — year / make / model / spec / colour summary
      final summary = [
        if (year.isNotEmpty) year,
        if (_make != null) _make!,
        if (model.isNotEmpty) model,
        if (spec.isNotEmpty) spec,
      ].join(' ').trim();
      _applyLookup(
        _descCtrl,
        summary.isEmpty
            ? ''
            : (colour.isNotEmpty ? '$summary in $colour' : summary),
      );

      // Owned from — seed with the date the vehicle was first registered.
      // Only a starting point: a second-hand car was first registered long
      // before this owner got it, so the user can still change it.
      final firstRegistered = _parseFirstRegistered(
        _lookupString(data, const [
          'VehicleIdentification.DateFirstRegistered',
          'VehicleIdentification.DateFirstRegisteredInUk',
          'month_first_registered',
        ]),
        year,
      );
      if (_ownership != 'dream_car') {
        _ownedFrom = firstRegistered;
        if (firstRegistered != null &&
            _ownedTo != null &&
            _ownedTo!.isBefore(firstRegistered)) {
          _ownedTo = null;
        }
      }

      // Normalise the reg field itself
      _regCtrl.text = reg;
    });

    final found = [
      year,
      _titleCase(make),
      model,
      spec,
    ].where((p) => p.isNotEmpty).join(' ');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(found.isEmpty ? 'Vehicle found' : 'Found: $found'),
        backgroundColor: Colors.green.shade600,
      ),
    );
  }

  /// The spec document is sometimes handed back wrapped in another envelope.
  Map<String, dynamic> _unwrapLookup(Map<String, dynamic> res) {
    for (final key in const ['data', 'Data', 'vehicle', 'result']) {
      final inner = res[key];
      if (inner is Map &&
          (inner.containsKey('VehicleIdentification') ||
              inner.containsKey('ModelData'))) {
        return inner.cast<String, dynamic>();
      }
    }
    return res;
  }

  /// First non-empty value among [paths], each a dot-separated path into the
  /// nested lookup document, e.g. "Performance.Power.Bhp".
  String _lookupString(Map<String, dynamic> data, List<String> paths) {
    for (final path in paths) {
      dynamic node = data;
      for (final key in path.split('.')) {
        node = (node is Map && node.containsKey(key)) ? node[key] : null;
        if (node == null) break;
      }
      final value = node?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// 148.0 -> "148", 7.8 -> "7.8", 0 / junk -> "" so it never autofills a zero.
  String _fmtNum(String raw) {
    final n = double.tryParse(raw);
    if (n == null || n <= 0) return '';
    return n == n.roundToDouble() ? n.round().toString() : n.toString();
  }

  /// Write a looked-up [value] into [ctrl]. Tapping Auto fill means "fill this
  /// form from this reg", so it overwrites whatever is there — including an
  /// earlier reg's answer, and including an empty [value], which clears the
  /// field rather than leaving a figure that belongs to a different vehicle.
  void _applyLookup(TextEditingController ctrl, String value) {
    ctrl.text = value;
  }

  /// "2017-06-19T00:00:00Z" -> 19 Jun 2017, "2022-10" -> 1 Oct 2022, falling
  /// back to 1 Jan of [year].
  DateTime? _parseFirstRegistered(dynamic firstRegistered, dynamic year) {
    final raw = firstRegistered?.toString().trim() ?? '';

    final iso = DateTime.tryParse(raw);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final parts = raw.split('-');
    if (parts.length >= 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null && m >= 1 && m <= 12) {
        return DateTime(y, m, 1);
      }
    }

    final fallbackYear = int.tryParse(year?.toString().trim() ?? '');
    if (fallbackYear != null && fallbackYear > 1900) {
      return DateTime(fallbackYear, 1, 1);
    }

    return null;
  }

  /// 1399 (cc) or 1.4 (litres) -> "1.4L". '' when missing or unusable.
  String _engineLitres(dynamic capacity) {
    final value = double.tryParse(capacity?.toString().trim() ?? '');
    if (value == null || value <= 0) return '';
    final litres = value >= 100 ? value / 1000 : value;
    return '${litres.toStringAsFixed(1)}L';
  }

  String _titleCase(String input) {
    return input
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
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
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          _isEditMode ? 'Edit Vehicle' : 'Add Vehicle',
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
      body: Stack(
        children: [
          SafeArea(
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
                        DropdownButtonFormField<String>(
                          value: _ownership,
                          dropdownColor: Colors.white,
                          isExpanded: true,
                          icon: _caret,
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
                        if (_ownership != 'dream_car') ...[
                          _divider(),
                          _dateRow(
                            label: 'Owned From',
                            date: _ownedFrom,
                            onTap: () => _pickDate(isFrom: true, theme: theme),
                          ),
                        ],
                        if (_showOwnedTo) ...[
                          _divider(),
                          _dateRow(
                            label: 'Owned To',
                            date: _ownedTo,
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
                        DropdownButtonFormField<String>(
                          dropdownColor: theme.cardColor,
                          focusColor: theme.primaryColor,
                          value: _make,
                          isExpanded: true,
                          icon: _caret,
                          decoration: _dec(
                            'Vehicle Make *',
                            hint: 'Please Select',
                          ),
                          items: _makes
                              .map(
                                (m) =>
                                    DropdownMenuItem(value: m, child: Text(m)),
                              )
                              .toList(),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please select a make';
                            }
                            return null;
                          },
                          onChanged: (v) => setState(() => _make = v),
                        ),
                        _divider(),
                        TextFormField(
                          controller: _modelCtrl,
                          decoration: _dec(
                            'Model *',
                            hint: 'Your vehicle model',
                          ),
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
                          textCapitalization: TextCapitalization.characters,
                          decoration:
                              _dec(
                                'Registration',
                                hint: 'Your vehicle reg',
                              ).copyWith(
                                suffixIcon: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _autoFillButton(),
                                ),
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                              ),
                        ),
                        _divider(),
                        TextFormField(
                          controller: _colourCtrl,
                          decoration: _dec(
                            'Colour',
                            hint: 'Your vehicle colour',
                          ),
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
                      activeThumbColor: theme.primaryColor,
                      onChanged: (v) => setState(() => _taggingEnabled = v),
                    ),
                  ),

                  if (_isEditMode) ...[
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _deleteVehicle(theme),
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

          // ADD: Upload progress overlay
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          value: _uploadProgress,
                          strokeWidth: 6,
                          color: theme.primaryColor,
                          backgroundColor: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Uploading ${(_uploadProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Text(
                        //   _uploadStatus,
                        //   textAlign: TextAlign.center,
                        //   style: const TextStyle(
                        //     fontSize: 14,
                        //     color: Colors.grey,
                        //   ),
                        // ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.grey[300],
                          color: theme.primaryColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
