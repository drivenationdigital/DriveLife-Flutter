import 'dart:io';
import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/models/event_media.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

class CreateVenueScreen extends StatefulWidget {
  final Map<String, dynamic>? existingVenue; // For editing

  const CreateVenueScreen({Key? key, this.existingVenue}) : super(key: key);

  @override
  State<CreateVenueScreen> createState() => _CreateVenueScreenState();
}

class _CreateVenueScreenState extends State<CreateVenueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  // Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _facebookController = TextEditingController();
  final TextEditingController _instagramController = TextEditingController();

  final QuillController _descriptionController = QuillController.basic();

  final FocusNode _locationFocusNode = FocusNode();

  // Location data
  String _locationName = '';
  double? _lat;
  double? _lng;
  String _selectedCountry = 'gb';

  // Images
  ImageData? _logoImage;
  ImageData? _coverImage;
  bool _isLogoUploaded = false;
  bool _isCoverUploaded = false;

  // State
  bool _isLoading = false;
  bool _isPublished = false;

  // Track which tabs have been loaded
  final Set<int> _loadedTabs = {0}; // First tab loaded by default

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Load existing venue data if editing
    if (widget.existingVenue != null) {
      _loadExistingData();
    }

    _selectedCountry =
        Provider.of<UserProvider>(
          context,
          listen: false,
        ).user?.lastLocation?.country ??
        'gb';
  }

  Future<ImageData> _fileToImageData(File file) async {
    final bytes = await file.readAsBytes();
    final base64String = base64Encode(bytes);

    final lower = file.path.toLowerCase();
    String mimeType;
    String extension;

    if (lower.endsWith('.png')) {
      mimeType = 'image/png';
      extension = '.png';
    } else if (lower.endsWith('.webp')) {
      mimeType = 'image/webp';
      extension = '.webp';
    } else {
      mimeType = 'image/jpeg';
      extension = '.jpg';
    }

    return ImageData(
      file: file,
      base64: base64String,
      mimeType: mimeType,
      extension: extension,
    );
  }

  void _onTabChanged() {
    setState(() {
      // ✅ Add setState to trigger rebuild
      if (!_loadedTabs.contains(_tabController.index)) {
        _loadedTabs.add(_tabController.index);
      }
    });
  }

  void _loadExistingData() {
    final venue = widget.existingVenue!;
    _titleController.text = venue['title'] ?? '';
    _locationController.text = venue['location'] ?? '';
    _emailController.text = venue['email'] ?? '';
    _phoneController.text = venue['phone'] ?? '';
    _websiteController.text = venue['website'] ?? '';
    _facebookController.text = venue['facebook'] ?? '';
    _instagramController.text = venue['instagram'] ?? '';
    _isPublished = venue['is_published'] ?? false;
  }

  Future<void> _pickImage(bool isLogo) async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (image != null) {
      final imageData = await _fileToImageData(File(image.path));
      setState(() {
        if (isLogo) {
          _logoImage = imageData;
          _isLogoUploaded = false; // Mark as not uploaded
        } else {
          _coverImage = imageData;
          _isCoverUploaded = false; // Mark as not uploaded
        }
      });
    }
  }

  Future<void> _showUploadProgress(String venueId) async {
    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0);
    final ValueNotifier<String> statusNotifier = ValueNotifier<String>(
      'Preparing upload...',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            return ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (context, status, child) {
                return AlertDialog(
                  backgroundColor: Colors.white,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Uploading Images',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CircularProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.grey.shade200,
                        color: const Color(0xFFAE9159),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    try {
      // Upload logo (only if not already uploaded)
      if (_logoImage != null && !_isLogoUploaded) {
        statusNotifier.value = 'Uploading logo...';
        print('📤 Starting logo upload...');

        await VenueApiService.uploadVenueImages(
          venueId: venueId,
          images: [_logoImage!],
          type: 'logo',
          onProgress: (progress) {
            print('📊 Logo progress: ${progress.toStringAsFixed(1)}%');
            progressNotifier.value = progress;
          },
        );

        setState(() {
          _isLogoUploaded = true;
        });
        print('✅ Logo uploaded');
      }

      // Upload cover image (only if not already uploaded)
      if (_coverImage != null && !_isCoverUploaded) {
        statusNotifier.value = 'Uploading cover image...';
        progressNotifier.value = 0; // Reset for cover upload
        print('📤 Starting cover image upload...');

        await VenueApiService.uploadVenueImages(
          venueId: venueId,
          images: [_coverImage!],
          type: 'cover',
          onProgress: (progress) {
            print('📊 Cover progress: ${progress.toStringAsFixed(1)}%');
            progressNotifier.value = progress;
          },
        );

        setState(() {
          _isCoverUploaded = true;
        });
        print('✅ Cover image uploaded');
      }

      progressNotifier.dispose();
      statusNotifier.dispose();

      if (mounted) {
        Navigator.of(context).pop(true); // Close progress dialog

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venue saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Upload error: $e');
      progressNotifier.dispose();
      statusNotifier.dispose();

      if (mounted) {
        Navigator.of(context).pop(true); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _validateAndCreate() {
    // Validate required fields
    if (_titleController.text.trim().isEmpty) {
      _showError('Venue title is required');
      _tabController.animateTo(0);
      return;
    }

    if (_locationController.text.trim().isEmpty) {
      _showError('Venue location is required');
      _tabController.animateTo(0);
      return;
    }

    // Show publish modal
    _showPublishModal();
  }

  void _showPublishModal() {
    showDialog(
      context: context,
      builder: (context) => _PublishVenueModal(
        isPublished: _isPublished,
        onPublish: () => _saveVenue(publish: true),
        onSaveDraft: () => _saveVenue(publish: false),
        onDelete: widget.existingVenue != null ? _deleteVenue : null,
      ),
    );
  }

  String _getQuillContentAsHtml(QuillController controller) {
    try {
      final delta = controller.document.toDelta();
      final operations = delta.toJson();

      // Convert delta to HTML
      final converter = QuillDeltaToHtmlConverter(
        List.castFrom(operations),
        ConverterOptions.forEmail(), // or ConverterOptions() for default
      );

      final html = converter.convert();

      return html.trim().isEmpty ? '' : html;
    } catch (e) {
      print('Error converting Quill to HTML: $e');
      // Fallback to plain text
      final plainText = controller.document.toPlainText();
      return plainText.trim().isEmpty ? '' : '<p>${plainText.trim()}</p>';
    }
  }

  Future<void> _saveVenue({required bool publish}) async {
    setState(() => _isLoading = true);

    final description = _getQuillContentAsHtml(_descriptionController);

    try {
      // Save venue data first (without images)
      final venueData = {
        'title': _titleController.text.trim(),
        'location': {'address': _locationName, 'lat': _lat, 'lng': _lng},
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'website': _websiteController.text.trim(),
        'facebook': _facebookController.text.trim(),
        'instagram': _instagramController.text.trim(),
        'description': description,
        'status': publish ? 'publish' : 'draft',
      };

      print('💾 Saving venue data: $venueData');

      final response = await VenueApiService.saveVenue(venueData);

      if (response != null && response['success'] == true) {
        final venueId = response['venue_id'].toString();

        print(
          '🎉 Venue ${widget.existingVenue != null ? "updated" : "created"} with ID: $venueId',
        );

        if (!mounted) return;
        // Navigator.pop(context); // Close publish modal

        // Check if there are new images to upload
        bool hasNewLogoImage = _logoImage != null && !_isLogoUploaded;
        bool hasNewCoverImage = _coverImage != null && !_isCoverUploaded;

        if (hasNewLogoImage || hasNewCoverImage) {
          await _showUploadProgress(venueId);
        } else {
          if (mounted) {
            Navigator.pop(context, true); // Close publish modal
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  publish
                      ? 'Venue published successfully!'
                      : 'Venue saved as draft',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception('Failed to save venue');
      }
    } catch (e) {
      if (!mounted) return;
      // Navigator.pop(context); // Close publish modal
      _showError('Failed to save venue: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteVenue() async {
    Navigator.pop(context); // Close publish modal

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Venue'),
        content: const Text(
          'Are you sure you want to delete this venue? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        // TODO: Implement delete API call
        await Future.delayed(const Duration(seconds: 1));

        if (!mounted) return;

        Navigator.pop(context); // Return to previous screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venue deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        _showError('Failed to delete venue: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _locationController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _descriptionController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _validateAndCreate,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Create',
                    style: TextStyle(
                      color: Color(0xFFAE9159),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                Text(
                  widget.existingVenue != null ? 'EDIT VENUE' : 'CREATE VENUE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getTabTitle(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFAE9159),
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: const Color(0xFFAE9159),
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Basic Details'),
                Tab(text: 'Venue Profile'),
                Tab(text: 'Description'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Always load first tab
                _BasicDetailsTab(
                  titleController: _titleController,
                  locationController: _locationController,
                  locationFocusNode: _locationFocusNode,
                  selectedCountry: _selectedCountry,
                  onLocationSelected: (name, lat, lng) {
                    _locationName = name;
                    _lat = lat;
                    _lng = lng;
                  },
                  onNext: () => _tabController.animateTo(1),
                ),

                // Lazy load second tab
                _loadedTabs.contains(1)
                    ? _VenueProfileTab(
                        logoImage: _logoImage,
                        coverImage: _coverImage,
                        isLogoUploaded: _isLogoUploaded, // ✅ ADD THIS
                        isCoverUploaded: _isCoverUploaded, // ✅ ADD THIS
                        emailController: _emailController,
                        phoneController: _phoneController,
                        websiteController: _websiteController,
                        facebookController: _facebookController,
                        instagramController: _instagramController,
                        onPickLogo: () => _pickImage(true),
                        onPickCover: () => _pickImage(false),
                        onBack: () => _tabController.animateTo(0),
                        onNext: () => _tabController.animateTo(2),
                      )
                    : const Center(child: CircularProgressIndicator()),

                // Lazy load third tab
                _loadedTabs.contains(2)
                    ? _DescriptionTab(
                        controller: _descriptionController,
                        onBack: () => _tabController.animateTo(1),
                        onNext: _validateAndCreate,
                      )
                    : const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTabTitle() {
    switch (_tabController.index) {
      case 0:
        return 'Basic Details';
      case 1:
        return 'Your venue profile';
      case 2:
        return 'Describe your venue';
      default:
        return 'Basic Details';
    }
  }
}

// Basic Details Tab
class _BasicDetailsTab extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController locationController;
  final FocusNode locationFocusNode;
  final String selectedCountry;
  final Function(String name, double? lat, double? lng) onLocationSelected;
  final VoidCallback onNext;

  const _BasicDetailsTab({
    required this.titleController,
    required this.locationController,
    required this.locationFocusNode,
    required this.selectedCountry,
    required this.onLocationSelected,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Venue Title
          const Text(
            'Venue Title',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          const Text('*', style: TextStyle(color: Colors.red, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: titleController,
            maxLength: 80,
            decoration: InputDecoration(
              hintText: 'Enter venue title',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
              counterStyle: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Venue Location
          const Text(
            'Venue Location',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          const Text('*', style: TextStyle(color: Colors.red, fontSize: 14)),
          const SizedBox(height: 8),
          GooglePlaceAutoCompleteTextField(
            textEditingController: locationController,
            googleAPIKey: "AIzaSyDqDMSFVfl-tOgqaj4ZqA5I3HnobrIK6jg",
            focusNode: locationFocusNode,
            inputDecoration: InputDecoration(
              hintText: 'Enter venue location',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(Icons.location_on, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
            ),
            debounceTime: 400,
            countries: [selectedCountry],
            isLatLngRequired: true,
            getPlaceDetailWithLatLng: (Prediction prediction) {
              onLocationSelected(
                prediction.description ?? '',
                double.tryParse(prediction.lat ?? ''),
                double.tryParse(prediction.lng ?? ''),
              );
            },
            itemClick: (Prediction prediction) {
              locationController.text = prediction.description ?? '';
              locationFocusNode.unfocus();
            },
            isCrossBtnShown: true,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// Venue Profile Tab
class _VenueProfileTab extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController websiteController;
  final TextEditingController facebookController;
  final TextEditingController instagramController;
  final VoidCallback onPickLogo;
  final VoidCallback onPickCover;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final ImageData? logoImage; // Changed from File?
  final ImageData? coverImage; // Changed from File?
  final bool isLogoUploaded; // ✅ ADD THIS
  final bool isCoverUploaded; // ✅ ADD THIS

  const _VenueProfileTab({
    required this.logoImage,
    required this.coverImage,
    required this.emailController,
    required this.phoneController,
    required this.websiteController,
    required this.facebookController,
    required this.instagramController,
    required this.onPickLogo,
    required this.onPickCover,
    required this.onBack,
    required this.onNext,
    required this.isLogoUploaded, // ✅ ADD THIS
    required this.isCoverUploaded, // ✅ ADD THIS
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Venue Logo
          const Text(
            'Venue Logo',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Must be JPG or PNG image',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          _ImageUploadBox(
            image: logoImage,
            height: 120,
            onTap: onPickLogo,
            placeholderIcon: Icons.add_a_photo,
            isUploaded: isLogoUploaded,
          ),
          const SizedBox(height: 24),

          // Venue Cover Image
          const Text(
            'Venue Cover Image',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add an image that best represents your venue',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended size (width x height): 1200px',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          _ImageUploadBox(
            image: coverImage,
            height: 150,
            onTap: onPickCover,
            placeholderIcon: Icons.add_a_photo,
            isUploaded: isCoverUploaded,
          ),
          const SizedBox(height: 24),

          // Email Address
          const Text(
            'Venue Email Address',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A system reminder email will be sent at this email identity',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Enter email address',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Phone Number
          const Text(
            'Venue Phone Number',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'Enter phone number',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(Icons.phone_outlined, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Website
          const Text(
            'Venue Website',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: websiteController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://example.com',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(Icons.language, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Facebook Page URL
          const Text(
            'Facebook Page URL',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: facebookController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://facebook.com/yourpage',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(Icons.facebook, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Instagram Username
          const Text(
            'Instagram Username',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: instagramController,
            decoration: InputDecoration(
              hintText: '@username',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              prefixIcon: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.grey,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFAE9159)),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// Description Tab with Quill Editor
class _DescriptionTab extends StatelessWidget {
  final QuillController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _DescriptionTab({
    required this.controller,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tell us more about your venue',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),

                // Quill Toolbar
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      // Toolbar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: QuillSimpleToolbar(
                          controller: controller,
                          config: const QuillSimpleToolbarConfig(
                            showAlignmentButtons: false,
                            showBackgroundColorButton: false,
                            showCenterAlignment: false,
                            showCodeBlock: false,
                            showColorButton: false,
                            showDirection: false,
                            showDividers: false,
                            showFontFamily: false,
                            showFontSize: false,
                            showHeaderStyle: false,
                            showIndent: false,
                            showInlineCode: false,
                            showJustifyAlignment: false,
                            showLeftAlignment: false,
                            showLink: false,
                            showListCheck: false,
                            showQuote: false,
                            showRightAlignment: false,
                            showSearchButton: false,
                            showSmallButton: false,
                            showStrikeThrough: false,
                            showSubscript: false,
                            showSuperscript: false,
                          ),
                        ),
                      ),
                      // Editor
                      Container(
                        height: 300,
                        padding: const EdgeInsets.all(12),
                        child: QuillEditor.basic(
                          controller: controller,
                          config: const QuillEditorConfig(
                            placeholder: 'Enter event description...',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Image Upload Box Widget
class _ImageUploadBox extends StatelessWidget {
  final ImageData? image;
  final double height;
  final VoidCallback onTap;
  final IconData placeholderIcon;
  final bool isUploaded; // ✅ ADD THIS

  const _ImageUploadBox({
    required this.image,
    required this.height,
    required this.onTap,
    required this.placeholderIcon,
    this.isUploaded = false, // ✅ ADD THIS
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = image != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(
            color: Colors.grey.shade300,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: image!.isRemote
                        ? Image.network(
                            image!.remoteUrl!,
                            width: double.infinity,
                            height: height,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            image!.file!,
                            width: double.infinity,
                            height: height,
                            fit: BoxFit.cover,
                          ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isUploaded
                            ? Colors.green
                            : const Color(0xFFAE9159),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUploaded
                                ? Icons.check_circle
                                : Icons.cloud_upload,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isUploaded ? 'Uploaded' : 'Upload',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(placeholderIcon, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFAE9159),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Upload',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// Publish Venue Modal
class _PublishVenueModal extends StatelessWidget {
  final bool isPublished;
  final VoidCallback onPublish;
  final VoidCallback onSaveDraft;
  final VoidCallback? onDelete;

  const _PublishVenueModal({
    required this.isPublished,
    required this.onPublish,
    required this.onSaveDraft,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Dialog(
      backgroundColor: theme.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              'EDIT VENUE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Save and Publish',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),

            // Status Dropdown
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Venue Status',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isPublished
                        ? 'Published - Live on CarEvents.com'
                        : 'Unpublished',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Status Messages
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _StatusRow(
                    icon: isPublished ? Icons.check_circle : Icons.cancel,
                    iconColor: isPublished ? theme.primaryColor : Colors.grey,
                    text: isPublished
                        ? 'Your venue is currently published.'
                        : 'Your venue is currently unpublished.',
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    icon: Icons.check_circle,
                    iconColor: theme.primaryColor,
                    text: 'You will be able to view and share once it\'s live',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onSaveDraft();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Save Draft',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onPublish();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Publish Venue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Delete Button
            if (onDelete != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onDelete,
                child: const Text(
                  'DELETE VENUE',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Status Row Widget
class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
