import 'dart:convert';
import 'dart:io';
import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class AddModificationScreen extends StatefulWidget {
  final String garageId;
  final Map<String, dynamic>? mod; // For edit mode

  const AddModificationScreen({Key? key, required this.garageId, this.mod})
    : super(key: key);

  @override
  State<AddModificationScreen> createState() => _AddModificationScreenState();
}

class _AddModificationScreenState extends State<AddModificationScreen> {
  final _formKey = GlobalKey<FormState>();

  File? _imageFile;
  String? _base64Image;
  String? _existingImageUrl;

  String? _modType;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  bool _saving = false;

  // ADD: Upload progress tracking
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  static const List<String> _modTypes = [
    'Engine',
    'Exhaust',
    'Suspension',
    'Brakes',
    'Interior',
    'Exterior',
    'Wheels',
    'Electronics',
    'Other',
  ];

  bool get _isEditMode => widget.mod != null;

  @override
  void initState() {
    super.initState();
    _loadModData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  void _loadModData() {
    if (!_isEditMode) return;

    final m = widget.mod!;

    setState(() {
      _modType = m['mod_type']?.toString();
      _titleCtrl.text = m['title']?.toString() ?? '';
      _descCtrl.text = m['description']?.toString() ?? '';
      _linkCtrl.text = m['product_link']?.toString() ?? '';
      _existingImageUrl = m['image']?.toString();
    });
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
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final picker = ImagePicker();
    final x = await picker.pickImage(source: source, imageQuality: 85);
    if (!mounted) return;
    if (x == null) return;

    await _setImage(File(x.path));
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Select Image Source',
          style: TextStyle(color: Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  void _removeImage() {
    setState(() {
      _imageFile = null;
      _base64Image = null;
      _existingImageUrl = null;
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

  // UPDATE: _onSave with upload progress tracking
  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    if (_modType == null || _modType!.isEmpty) {
      _toast('Please select a modification type');
      return;
    }

    if (_titleCtrl.text.trim().isEmpty) {
      _toast('Please enter a modification title');
      return;
    }

    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser == null) {
      _toast('User not logged in');
      return;
    }

    final payload = <String, dynamic>{
      'garage_id': widget.garageId,
      'mod_type': _modType,
      'mod_title': _titleCtrl.text.trim(),
      'mod_description': _descCtrl.text.trim(),
      'product_link': _linkCtrl.text.trim(),
    };

    // Check if we're uploading a new image (base64) or using existing URL
    final willUploadNewImage = _base64Image != null && _base64Image!.isNotEmpty;

    if (willUploadNewImage) {
      payload['mod_image'] = _base64Image;
    } else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      payload['mod_image'] = _existingImageUrl;
    }

    print('Payload: $payload');

    setState(() {
      _saving = true;
      // Only show upload progress if we're actually uploading a new image
      _isUploading = willUploadNewImage;
      _uploadProgress = 0.0;
      _uploadStatus = willUploadNewImage ? 'Preparing upload...' : '';
    });

    try {
      final dynamic res;

      if (_isEditMode) {
        res = await GarageAPI.updateVehicleMod(
          payload,
          widget.mod!['id'].toString(),
          currentUser['id'].toString(),
          onUploadProgress: (current, total, percentage) {
            if (mounted && willUploadNewImage) {
              setState(() {
                _uploadProgress = percentage;
                _uploadStatus = 'Uploading ${current + 1}/$total chunks';
              });
            }
          },
        );
      } else {
        res = await GarageAPI.addVehicleMod(
          payload,
          currentUser['id'].toString(),
          onUploadProgress: (current, total, percentage) {
            if (mounted && willUploadNewImage) {
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
          _isEditMode
              ? 'Failed to update modification'
              : 'Failed to add modification',
        );
      }

      _toast(
        _isEditMode
            ? 'Modification updated successfully'
            : 'Modification added successfully',
      );

      Navigator.pop(context, _isEditMode ? 'updated' : 'added');
    } catch (e) {
      if (!mounted) return;

      final msg = (e is Map && e['message'] != null)
          ? e['message'].toString()
          : (e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : (_isEditMode
                      ? 'Failed to update modification'
                      : 'Failed to add modification'));

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

  Future<void> _deleteMod() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Modification'),
        content: const Text(
          'Are you sure you want to delete this modification?',
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
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final res = await GarageAPI.deleteVehicleMod(
        widget.mod!['id'].toString(),
        currentUser['id'].toString(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // hide loader

      final success = (res is Map) ? (res?['success'] == true) : false;
      if (!success) {
        throw Exception('Failed to delete modification');
      }

      _toast('Modification deleted successfully');
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final msg = (e is Map && e['message'] != null)
          ? e['message'].toString()
          : (e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : 'Failed to delete modification');

      _toast(msg);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: InputBorder.none,
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFEFEFEF));

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
          _isEditMode ? 'Edit Modification' : 'Add Modification',
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
                  _sectionTitle('Modification Image'),
                  _buildImageSection(),

                  _sectionTitle('Modification Details'),
                  _card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _modType,
                            decoration: _dec(
                              'Modification Type *',
                              hint: 'Please Select',
                            ),
                            items: _modTypes
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Please select a type';
                              }
                              return null;
                            },
                            onChanged: (v) => setState(() => _modType = v),
                          ),
                        ),
                        _divider(),
                        TextFormField(
                          controller: _titleCtrl,
                          decoration: _dec(
                            'Modification Title *',
                            hint: 'e.g. K&N Air Filter',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Title is required'
                              : null,
                        ),
                        _divider(),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: _dec(
                            'Description',
                            hint: 'Add details about this modification',
                          ),
                          maxLines: 3,
                          maxLength: 500,
                        ),
                        _divider(),
                        TextFormField(
                          controller: _linkCtrl,
                          decoration: _dec(
                            'Link to buy product',
                            hint: 'https://example.com/product',
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ],
                    ),
                  ),

                  // Delete button for edit mode
                  if (_isEditMode) ...[
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _saving ? null : _deleteMod,
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
                                  'Delete Modification',
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
                          '${(_uploadProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _uploadStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
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
