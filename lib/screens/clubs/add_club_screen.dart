import 'dart:convert';
import 'dart:io';
import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/models/club_api_models.dart';
import 'package:drivelife/models/event_media.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:http/http.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:shimmer/shimmer.dart';

class CreateClubScreen extends StatefulWidget {
  final String? existingClubId; // CHANGE: from ClubDetail? to String?

  const CreateClubScreen({Key? key, this.existingClubId}) : super(key: key);

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen>
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
  final TextEditingController _merchandiseController = TextEditingController();

  final QuillController _descriptionController = QuillController.basic();
  final QuillController _termsController = QuillController.basic();

  final FocusNode _locationFocusNode = FocusNode();

  String? _clubId;
  String? _clubType;
  bool _isLoadingClub = false;

  // Location data
  String _locationName = '';
  String _latitude = '';
  String _longitude = '';
  String _selectedCountry = 'gb';

  // Images
  ImageData? _logoImage;
  ImageData? _coverImage;
  bool _isLogoUploaded = false;
  bool _isCoverUploaded = false;

  List<ClubCategory> _availableCategories = [];
  bool _isLoadingCategories = true;
  final Set<int> _selectedCategoryIds = {}; // Store term IDs instead of names

  // Location Type
  int _locationType = 2; // 1 = National, 2 = Local

  // Membership Questions
  final List<TextEditingController> _questionControllers = [];

  // Club Administrators
  final List<ClubAdministrator> _administrators = [];
  final TextEditingController _adminEmailController = TextEditingController();

  // State
  bool _isLoading = false;
  bool _isPublished = false;

  // Track which tabs have been loaded
  final Set<int> _loadedTabs = {0}; // First tab loaded by default

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);

    if (widget.existingClubId != null) {
      _clubId = widget.existingClubId;
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
      if (!_loadedTabs.contains(_tabController.index)) {
        _loadedTabs.add(_tabController.index);
      }
    });
  }

  Future<void> _loadExistingData() async {
    print('🔍 Loading club data for ID: $_clubId');
    setState(() => _isLoadingClub = true);
    try {
      // Fetch club details using the new API service
      final response = await ClubApiService.getClubEditData(_clubId!);

      if (!response.success || response.data == null) {
        throw Exception(response.message ?? 'Failed to load club data');
      }

      final club = response.data!;

      // ✅ Load available categories from API response
      _availableCategories = club.categories.available
          .map(
            (cat) => ClubCategory(
              termId: cat.termId,
              name: cat.name,
              slug: cat.slug,
            ),
          )
          .toList();

      // Basic details
      _titleController.text = club.clubTitle;
      _selectedCategoryIds.clear();
      _selectedCategoryIds.addAll(club.categories.selected);
      _locationType = club.clubLocationType;

      // Location details
      _locationController.text = club.clubLocation;
      _latitude = club.latitude;
      _longitude = club.longitude;
      _locationName = club.clubLocation;

      // Contact & Social details
      _emailController.text = club.clubEmail;
      _websiteController.text = club.website;
      _facebookController.text = club.facebook;
      _instagramController.text = club.instagram;
      _merchandiseController.text = club.merchandiseLink;

      // Load description (convert HTML to Quill Delta)
      if (club.description.isNotEmpty) {
        try {
          final delta = HtmlToDelta().convert(club.description);
          _descriptionController.document = Document.fromDelta(delta);
        } catch (e) {
          print('Error converting description HTML to Quill: $e');
          _descriptionController.document = Document()
            ..insert(0, club.description);
        }
      }

      // Load terms (convert HTML to Quill Delta)
      if (club.clubTerms.isNotEmpty) {
        try {
          final delta = HtmlToDelta().convert(club.clubTerms);
          _termsController.document = Document.fromDelta(delta);
        } catch (e) {
          print('Error converting terms HTML to Quill: $e');
          _termsController.document = Document()..insert(0, club.clubTerms);
        }
      }

      // Load membership questions
      _questionControllers.clear();
      for (var question in club.membershipQuestions) {
        final controller = TextEditingController(text: question);
        _questionControllers.add(controller);
      }

      // Ensure at least one question controller exists
      if (_questionControllers.isEmpty) {
        _questionControllers.add(TextEditingController());
      }

      // Load administrators
      _administrators.clear();
      _administrators.addAll(club.administrators);

      // Load cover image
      if (club.coverImage != null && club.coverImage!.isNotEmpty) {
        _coverImage = ImageData(
          file: File(''),
          base64: '',
          mimeType: '',
          extension: '',
          isUploaded: true,
          remoteUrl: club.coverImage!,
        );
        _isCoverUploaded = true;
      }

      // Load logo image
      if (club.logo != null && club.logo!.isNotEmpty) {
        _logoImage = ImageData(
          file: File(''),
          base64: '',
          mimeType: '',
          extension: '',
          isUploaded: true,
          remoteUrl: club.logo!,
        );
        _isLogoUploaded = true;
      }

      // ✅ Mark categories as loaded
      _isLoadingCategories = false;

      setState(() {});
    } catch (e) {
      _showError('Failed to load club: $e');
    } finally {
      setState(() {
        _isLoadingClub = false;
        _isLoadingCategories = false; // ✅ Stop loading categories on error too
      });
    }
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
          _isLogoUploaded = false;
        } else {
          _coverImage = imageData;
          _isCoverUploaded = false;
        }
      });
    }
  }

  void _addMembershipQuestion() {
    setState(() {
      _questionControllers.add(TextEditingController());
    });
  }

  void _removeMembershipQuestion(int index) {
    setState(() {
      _questionControllers[index].dispose();
      _questionControllers.removeAt(index);
    });
  }

  Future<void> _addAdministrator() async {
    final email = _adminEmailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ClubApiService.inviteClubAdmin(_clubId!, email);

      if (response.success && response.data != null) {
        setState(() {
          _administrators.add(response.data!);
          _adminEmailController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Administrator invited successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response.message ?? 'Failed to invite administrator');
      }
    } catch (e) {
      _showError('Failed to invite administrator: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeAdministrator(int index) async {
    final admin = _administrators[index];

    setState(() => _isLoading = true);

    try {
      final response = await ClubApiService.removeClubAdmin(
        _clubId!,
        userId: admin.userId,
        invitationId: admin.invitationId,
      );

      if (response.success) {
        setState(() {
          _administrators.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Administrator removed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response.message ?? 'Failed to remove administrator');
      }
    } catch (e) {
      _showError('Failed to remove administrator: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _validateAndCreate() {
    // Validate required fields
    if (_titleController.text.trim().isEmpty) {
      _showError('Club title is required');
      _tabController.animateTo(0);
      return;
    }

    if (_selectedCategoryIds.isEmpty) {
      // ✅ Changed
      _showError('Please select at least one category');
      _tabController.animateTo(0);
      return;
    }

    if (_locationType == 2) {
      // ✅ Changed from 'local' to 2
      if (_locationController.text.trim().isEmpty &&
          widget.existingClubId == null) {
        _showError('Club location is required');
        _tabController.animateTo(0);
        return;
      }
    }

    // Show publish modal
    _showPublishModal();
  }

  void _showPublishModal() {
    showDialog(
      context: context,
      builder: (context) => _PublishClubModal(
        isPublished: _isPublished,
        onPublish: () => _saveClub(publish: true),
        onSaveDraft: () => _saveClub(publish: false),
        onDelete: widget.existingClubId != null ? _deleteClub : null,
      ),
    );
  }

  String _getQuillContentAsHtml(QuillController controller) {
    try {
      final delta = controller.document.toDelta();
      final operations = delta.toJson();

      final converter = QuillDeltaToHtmlConverter(
        List.castFrom(operations),
        ConverterOptions.forEmail(),
      );

      final html = converter.convert();

      return html.trim().isEmpty ? '' : html;
    } catch (e) {
      print('Error converting Quill to HTML: $e');
      final plainText = controller.document.toPlainText();
      return plainText.trim().isEmpty ? '' : '<p>${plainText.trim()}</p>';
    }
  }

  Future<void> _showUploadProgress(String clubId) async {
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

        await ClubApiService.uploadClubImages(
          clubId: clubId,
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
        progressNotifier.value = 0;
        print('📤 Starting cover image upload...');

        await ClubApiService.uploadClubImages(
          clubId: clubId,
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
        Navigator.of(context).pop(); // Close progress dialog

        Navigator.of(context).pop(true); // Close screen

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Club saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Upload error: $e');
      progressNotifier.dispose();
      statusNotifier.dispose();

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveClub({required bool publish}) async {
    setState(() => _isLoading = true);

    final description = _getQuillContentAsHtml(_descriptionController);
    final terms = _getQuillContentAsHtml(_termsController);

    try {
      // Prepare update request
      final updateRequest = ClubUpdateRequest(
        status: publish ? 'publish' : 'draft',
        clubTitle: _titleController.text.trim(),
        categories: _selectedCategoryIds.toList(),
        clubLocationType: _locationType,
        clubLocation: _locationName,
        latitude: _latitude,
        longitude: _longitude,
        clubEmail: _emailController.text.trim(),
        website: _websiteController.text.trim(),
        facebook: _facebookController.text.trim(),
        instagram: _instagramController.text.trim(),
        merchandiseLink: _merchandiseController.text.trim(),
        description: description,
        clubTerms: terms,
        membershipQuestions: _questionControllers
            .map((c) => c.text.trim())
            .where((q) => q.isNotEmpty)
            .toList(),
      );

      print('💾 Updating club: $_clubId');
      print('📋 Update Request: ${updateRequest.toJson()}');

      final response = await ClubApiService.updateClubData(
        _clubId!,
        updateRequest,
      );

      if (!mounted) return;

      if (response.success) {
        print('🎉 Club data saved successfully');

        // Check if there are new images to upload
        bool hasNewLogoImage = _logoImage != null && !_isLogoUploaded;
        bool hasNewCoverImage = _coverImage != null && !_isCoverUploaded;

        if (hasNewLogoImage || hasNewCoverImage) {
          await _showUploadProgress(_clubId!);
        } else {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                publish ? 'Club updated successfully!' : 'Club saved as draft',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(response.message ?? 'Failed to update club');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save club: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteClub() async {
    Navigator.pop(context);
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: const Text('Delete Club'),
        content: const Text(
          'Are you sure you want to delete this club? This action cannot be undone.',
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
        final response = await ClubApiService.deleteClub(
          clubId: widget.existingClubId.toString(),
          site: _selectedCountry,
        );

        if (response == null || response['success'] != true) {
          throw Exception('Failed to delete club');
        }

        if (!mounted) return;

        Navigator.pop(context, 'deleted');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Club deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        _showError('Failed to delete club: $e');
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
    _merchandiseController.dispose();
    _descriptionController.dispose();
    _termsController.dispose();
    _locationFocusNode.dispose();
    _adminEmailController.dispose();
    for (var controller in _questionControllers) {
      controller.dispose();
    }
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
        // title: Image.asset('assets/logo-dark.png', height: 18),
        title: Column(
          children: [
            Text(
              widget.existingClubId != null ? 'EDIT CLUB' : 'CREATE CLUB',
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
                : Text(
                    widget.existingClubId != null ? 'Update' : 'Create',
                    style: const TextStyle(
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
          // Container(
          //   padding: const EdgeInsets.symmetric(vertical: 16),
          //   decoration: BoxDecoration(
          //     color: Colors.white,
          //     border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          //   ),
          //   child: Column(
          //     children: [
          //       Text(
          //         widget.existingClubId != null ? 'EDIT CLUB' : 'CREATE CLUB',
          //         style: TextStyle(
          //           fontSize: 12,
          //           fontWeight: FontWeight.w600,
          //           color: Colors.grey.shade600,
          //           letterSpacing: 1.2,
          //         ),
          //       ),
          //       const SizedBox(height: 4),
          //       Text(
          //         _getTabTitle(),
          //         style: const TextStyle(
          //           fontSize: 20,
          //           fontWeight: FontWeight.w600,
          //           color: Colors.black87,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),

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
              isScrollable: true,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Basic Details'),
                Tab(text: 'Club Profile'),
                Tab(text: 'Description'),
                Tab(text: 'Membership Questions'),
                Tab(text: 'Club Terms'),
                Tab(text: 'Administrators'),
                // Tab(text: 'Publish'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Basic Details
                _BasicDetailsTab(
                  titleController: _titleController,
                  locationController: _locationController,
                  locationFocusNode: _locationFocusNode,
                  selectedCountry: _selectedCountry,
                  selectedCategoryIds: _selectedCategoryIds,
                  availableCategories: _availableCategories,
                  isLoadingCategories: _isLoadingCategories,
                  locationType: _locationType,
                  onLocationSelected: (name, lat, lng) {
                    _locationName = name;
                    _latitude = lat?.toString() ?? '';
                    _longitude = lng?.toString() ?? '';
                  },
                  onLocationTypeChanged: (type) {
                    print('Location type changed to: $type');
                    setState(() => _locationType = type);
                  },
                  onCategoryToggled: (categoryId) {
                    setState(() {
                      if (_selectedCategoryIds.contains(categoryId)) {
                        _selectedCategoryIds.remove(categoryId);
                      } else {
                        _selectedCategoryIds.add(categoryId);
                      }
                    });
                  },
                  onNext: () => _tabController.animateTo(1),
                ),

                // Tab 2: Club Profile
                _loadedTabs.contains(1)
                    ? _ClubProfileTab(
                        logoImage: _logoImage,
                        coverImage: _coverImage,
                        isLogoUploaded: _isLogoUploaded,
                        isCoverUploaded: _isCoverUploaded,
                        emailController: _emailController,
                        phoneController: _phoneController,
                        websiteController: _websiteController,
                        facebookController: _facebookController,
                        instagramController: _instagramController,
                        merchandiseController: _merchandiseController,
                        onPickLogo: () => _pickImage(true),
                        onPickCover: () => _pickImage(false),
                        onBack: () => _tabController.animateTo(0),
                        onNext: () => _tabController.animateTo(2),
                      )
                    : const Center(child: CircularProgressIndicator()),

                // Tab 3: Description
                _loadedTabs.contains(2)
                    ? _DescriptionTab(
                        controller: _descriptionController,
                        onBack: () => _tabController.animateTo(1),
                        onNext: () => _tabController.animateTo(3),
                      )
                    : const Center(child: CircularProgressIndicator()),

                // Tab 4: Membership Questions
                _loadedTabs.contains(3)
                    ? _MembershipQuestionsTab(
                        questionControllers: _questionControllers,
                        onAddQuestion: _addMembershipQuestion,
                        onRemoveQuestion: _removeMembershipQuestion,
                        onBack: () => _tabController.animateTo(2),
                        onNext: () => _tabController.animateTo(4),
                      )
                    : const Center(child: CircularProgressIndicator()),

                // Tab 5: Club Terms
                _loadedTabs.contains(4)
                    ? _ClubTermsTab(
                        controller: _termsController,
                        onBack: () => _tabController.animateTo(3),
                        onNext: () => _tabController.animateTo(5),
                      )
                    : const Center(child: CircularProgressIndicator()),

                // Tab 6: Administrators
                _loadedTabs.contains(5)
                    ? _AdministratorsTab(
                        administrators: _administrators,
                        emailController: _adminEmailController,
                        onAddAdministrator: _addAdministrator,
                        onRemoveAdministrator: _removeAdministrator,
                        onBack: () => _tabController.animateTo(4),
                        onNext: () => _tabController.animateTo(6),
                      )
                    : const Center(child: CircularProgressIndicator()),

                // Tab 7: Publish
                // _loadedTabs.contains(6)
                //     ? _PublishTab(
                //         isPublished: _isPublished,
                //         onBack: () => _tabController.animateTo(5),
                //         onPublish: _validateAndCreate,
                //       )
                //     : const Center(child: CircularProgressIndicator()),
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
        return 'Your club profile';
      case 2:
        return 'Describe your club';
      case 3:
        return 'Membership Questions';
      case 4:
        return 'Club Terms';
      case 5:
        return 'Club Administrators';
      case 6:
        return 'Save and Publish';
      default:
        return 'Basic Details';
    }
  }
}

class _CategoryShimmer extends StatelessWidget {
  const _CategoryShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Column(
        children: List.generate(8, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 16,
                  width: 150 + (index * 10.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// Basic Details Tab
class _BasicDetailsTab extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController locationController;
  final FocusNode locationFocusNode;
  final String selectedCountry;
  final Set<int> selectedCategoryIds;
  final List<ClubCategory> availableCategories; // CHANGE TYPE
  final bool isLoadingCategories; // ADD THIS
  final int locationType;
  final Function(String name, double? lat, double? lng) onLocationSelected;
  final Function(int) onLocationTypeChanged;
  final Function(int) onCategoryToggled;
  final VoidCallback onNext;

  const _BasicDetailsTab({
    required this.titleController,
    required this.locationController,
    required this.locationFocusNode,
    required this.selectedCountry,
    required this.selectedCategoryIds,
    required this.availableCategories,
    required this.isLoadingCategories,
    required this.locationType,
    required this.onLocationSelected,
    required this.onLocationTypeChanged,
    required this.onCategoryToggled,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Club Title
          const Text(
            'Club Title',
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
              hintText: 'Enter club title',
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

          // Categories
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Categories',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (!isLoadingCategories) // ADD THIS CONDITION
                TextButton(
                  onPressed: () {
                    for (var category in availableCategories) {
                      if (!selectedCategoryIds.contains(category.termId)) {
                        // ✅ Changed
                        onCategoryToggled(category.termId); // ✅ Changed
                      }
                    }
                  },
                  child: Text(
                    'Select all',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // REPLACE THE CATEGORY LIST WITH THIS:
          isLoadingCategories
              ? const _CategoryShimmer()
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: availableCategories.map((category) {
                    final isSelected = selectedCategoryIds.contains(
                      category.termId,
                    ); // ✅ Changed
                    return FilterChip(
                      label: Text(category.name),
                      selected: isSelected,
                      onSelected: (_) => onCategoryToggled(
                        category.termId,
                      ), // ✅ Changed to termId
                      selectedColor: const Color(0xFFAE9159).withOpacity(0.1),
                      checkmarkColor: const Color(0xFFAE9159),
                    );
                  }).toList(),
                ),

          const SizedBox(height: 24),

          // Club Location Type
          const Text(
            'Club Location',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          const Text('*', style: TextStyle(color: Colors.red, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                // ✅ Changed from String to int
                value: locationType,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                items: const [
                  DropdownMenuItem(
                    value: 2, // ✅ Changed from 'local' to 2
                    child: Text('Local / Regional Club'),
                  ),
                  DropdownMenuItem(
                    value: 1, // ✅ Changed from 'national' to 1
                    child: Text('National Club'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onLocationTypeChanged(value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Club Location
          if (locationType == 2)
            GooglePlaceAutoCompleteTextField(
              textEditingController: locationController,
              googleAPIKey: "AIzaSyDqDMSFVfl-tOgqaj4ZqA5I3HnobrIK6jg",
              focusNode: locationFocusNode,
              inputDecoration: InputDecoration(
                hintText: 'Club Location',
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

          // Next Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Next Step',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Club Profile Tab
class _ClubProfileTab extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController websiteController;
  final TextEditingController facebookController;
  final TextEditingController instagramController;
  final TextEditingController merchandiseController;
  final VoidCallback onPickLogo;
  final VoidCallback onPickCover;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final ImageData? logoImage;
  final ImageData? coverImage;
  final bool isLogoUploaded;
  final bool isCoverUploaded;

  const _ClubProfileTab({
    required this.logoImage,
    required this.coverImage,
    required this.emailController,
    required this.phoneController,
    required this.websiteController,
    required this.facebookController,
    required this.instagramController,
    required this.merchandiseController,
    required this.onPickLogo,
    required this.onPickCover,
    required this.onBack,
    required this.onNext,
    required this.isLogoUploaded,
    required this.isCoverUploaded,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Club Logo
          const Text(
            'Club Logo',
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

          // Club Cover Image
          const Text(
            'Club Cover Image',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add an image that best represents your club',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
            'Club Email Address',
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

          // Club Website
          const Text(
            'Club Website',
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
            'Facebook Page',
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

          // Club Merchandise Link
          const Text(
            'Club Merchandise Link',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'If you sell club merchandise online, link it here',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: merchandiseController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://example.com/shop',
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
            ),
          ),

          const SizedBox(height: 40),

          // Navigation Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Next Step',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
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
                  'Tell us more about your club',
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
                            placeholder: 'Enter club description...',
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
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Next Step',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Membership Questions Tab
class _MembershipQuestionsTab extends StatelessWidget {
  final List<TextEditingController> questionControllers;
  final VoidCallback onAddQuestion;
  final Function(int) onRemoveQuestion;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _MembershipQuestionsTab({
    required this.questionControllers,
    required this.onAddQuestion,
    required this.onRemoveQuestion,
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
                  'If you would like members to answer any questions before they join, please add them here.',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 24),

                // Question Fields
                ...List.generate(questionControllers.length, (index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey.shade300,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'QUESTION *',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            if (questionControllers.length > 1)
                              IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () => onRemoveQuestion(index),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: questionControllers[index],
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Enter your question',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFAE9159),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // Add Another Button
                Center(
                  child: ElevatedButton.icon(
                    onPressed: onAddQuestion,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add another'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFAE9159),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Next Step',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Club Terms Tab
class _ClubTermsTab extends StatelessWidget {
  final QuillController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _ClubTermsTab({
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
                  'If you have any terms you\'d like new members to agree to, include them here.',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
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
                            placeholder: 'Enter club terms...',
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
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Next Step',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Administrators Tab
class _AdministratorsTab extends StatelessWidget {
  final List<ClubAdministrator> administrators;
  final TextEditingController emailController;
  final VoidCallback onAddAdministrator;
  final Function(int) onRemoveAdministrator;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _AdministratorsTab({
    required this.administrators,
    required this.emailController,
    required this.onAddAdministrator,
    required this.onRemoveAdministrator,
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
                  'Club administrators can create and manage events, accept new member requests and remove members. They cannot edit club details, unpublish or delete a club.',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Add Administrator Input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'Enter Email',
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
                            borderSide: const BorderSide(
                              color: Color(0xFFAE9159),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onAddAdministrator,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Invite'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFAE9159),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // List of Administrators
                if (administrators.isNotEmpty) ...[
                  const Text(
                    'Current Administrators',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // IN _AdministratorsTab build method, update the list display:
                  ...List.generate(administrators.length, (index) {
                    final admin = administrators[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                admin.isActive
                                    ? Icons.person
                                    : Icons.mail_outline,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    admin.email,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    admin.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: admin.isActive
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: () => onRemoveAdministrator(index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Next Step',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Publish Tab
class _PublishTab extends StatelessWidget {
  final bool isPublished;
  final VoidCallback onBack;
  final VoidCallback onPublish;

  const _PublishTab({
    required this.isPublished,
    required this.onBack,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Club Status Dropdown
          const Text(
            'Club Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
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
            child: Text(
              isPublished ? 'Published' : 'Unpublished',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
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
                  iconColor: isPublished
                      ? const Color(0xFFAE9159)
                      : Colors.grey,
                  text: isPublished
                      ? 'Your club is currently published.'
                      : 'Your club is currently unpublished.',
                ),
                const SizedBox(height: 8),
                const _StatusRow(
                  icon: Icons.check_circle,
                  iconColor: Color(0xFFAE9159),
                  text: 'You will be able to view and share it once it\'s live',
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
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onPublish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isPublished ? 'Update Club' : 'Publish Club',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Image Upload Box Widget
class _ImageUploadBox extends StatelessWidget {
  final ImageData? image;
  final double height;
  final VoidCallback onTap;
  final IconData placeholderIcon;
  final bool isUploaded;

  const _ImageUploadBox({
    required this.image,
    required this.height,
    required this.onTap,
    required this.placeholderIcon,
    this.isUploaded = false,
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

// Publish Club Modal
class _PublishClubModal extends StatelessWidget {
  final bool isPublished;
  final VoidCallback onPublish;
  final VoidCallback onSaveDraft;
  final VoidCallback? onDelete;

  const _PublishClubModal({
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
              'EDIT CLUB',
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
                        ? 'Your club is currently published.'
                        : 'Your club is currently unpublished.',
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    icon: Icons.check_circle,
                    iconColor: theme.primaryColor,
                    text:
                        'You will be able to view and share it once it\'s live',
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
                    child: Text(
                      isPublished ? 'Update Club' : 'Publish Club',
                      style: const TextStyle(
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
                  'DELETE CLUB',
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
