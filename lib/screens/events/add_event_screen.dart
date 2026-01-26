import 'dart:convert';
import 'dart:io';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/models/event_media.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AddEventScreen extends StatefulWidget {
  final String? eventId; // Add this parameter

  const AddEventScreen({super.key, this.eventId});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _externalUrlController = TextEditingController();

  // Also update your controller declarations at the top:
  late QuillController _descriptionController;
  late QuillController _entryDetailsController;
  late QuillController _entryDetailsFreeController;

  // Location
  final FocusNode _locationFocusNode = FocusNode();
  double? _lat;
  double? _lng;
  String? _locationName;

  // Images
  final ImagePicker _picker = ImagePicker();
  ImageData? _coverImage;
  List<ImageData> _galleryImages = [];

  // Form data
  String _selectedCountry = 'gb';
  List<String> _selectedCategories = [];
  List<Map<String, dynamic>> _categories = [];
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);
  String _ticketType = '1'; // 1=Free, 2=Platform, 3=External
  String _visibility = '1'; // 1=Public, 2=Private
  String _status = 'publish'; // publish or draft

  String? _eventID;
  bool _isCoverImageUploaded = false;

  bool _isLoading = false;
  double _uploadProgress = 0.0; // Add this line

  // Track which tabs have been visited for lazy loading
  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);

    // Initialize Quill controllers
    _descriptionController = QuillController.basic();
    _entryDetailsController = QuillController.basic();
    _entryDetailsFreeController = QuillController.basic();

    // Track tab changes for lazy loading
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _visitedTabs.add(_tabController.index);
        });
      }
    });

    _fetchCategories();

    // Load event data if editing
    if (widget.eventId != null) {
      _eventID = widget.eventId;
      _loadEventData(widget.eventId!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _locationController.dispose();
    _externalUrlController.dispose();
    _locationFocusNode.dispose();
    _descriptionController.dispose();
    _entryDetailsController.dispose();
    _entryDetailsFreeController.dispose();

    // Clear image cache to free memory
    imageCache.clear();
    imageCache.clearLiveImages();

    super.dispose();
  }

  Future<void> _removeGalleryImage(int index) async {
    final imageData = _galleryImages[index];

    // If it's an uploaded remote image, show confirmation
    if (imageData.isRemote && imageData.remoteId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Image?'),
          content: const Text(
            'This will permanently delete the uploaded image. This action cannot be undone.',
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

      if (confirmed != true) return;

      // Show loading
      setState(() => _isLoading = true);

      try {
        final response = await EventsAPI.removeEventImage(
          eventId: _eventID!,
          mediaId: imageData.remoteId!,
        );

        if (response != null && response['success'] == true) {
          setState(() {
            _galleryImages.removeAt(index);
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image deleted successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception('Failed to delete image');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting image: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      // Local image, just remove from list
      setState(() {
        _galleryImages.removeAt(index);
      });
    }
  }

  String _htmlToPlainText(String html) {
    if (html.isEmpty) return '';

    // Remove HTML tags
    String text = html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .trim();

    return text;
  }

  Future<void> _loadEventData(String eventId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await EventsAPI.getEventEditData(
        eventId: eventId,
        country: _selectedCountry,
      );

      if (response != null && response['success'] == true) {
        final data = response['data'];

        setState(() {
          // Basic fields
          _titleController.text = data['title'] ?? '';
          _selectedCountry = data['country'] ?? 'gb';

          // Location
          if (data['location'] != null) {
            _locationName = data['location']['address'];
            _locationController.text = data['location']['address'] ?? '';
            _lat = double.tryParse(data['location']['lat']?.toString() ?? '');
            _lng = double.tryParse(data['location']['lng']?.toString() ?? '');
          }

          // Categories - convert to List<String>
          if (data['categories'] != null && data['categories'] is List) {
            _selectedCategories = (data['categories'] as List)
                .map((cat) => cat.toString())
                .toList();
          }

          // Visibility and status
          _visibility = data['visibility']?.toString() ?? '1';
          _status = data['status'] ?? 'publish';

          // Dates
          if (data['date'] != null) {
            if (data['date']['start_date'] != null) {
              _startDate = DateTime.parse(data['date']['start_date']);
            }
            if (data['date']['end_date'] != null) {
              _endDate = DateTime.parse(data['date']['end_date']);
            }

            // Times
            if (data['date']['start_time'] != null) {
              final startTimeParts = data['date']['start_time'].split(':');
              _startTime = TimeOfDay(
                hour: int.parse(startTimeParts[0]),
                minute: int.parse(startTimeParts[1]),
              );
            }
            if (data['date']['end_time'] != null) {
              final endTimeParts = data['date']['end_time'].split(':');
              _endTime = TimeOfDay(
                hour: int.parse(endTimeParts[0]),
                minute: int.parse(endTimeParts[1]),
              );
            }
          }

          // Ticket type and details
          _ticketType = data['ticket_type']?.toString() ?? '1';
          _externalUrlController.text = data['external_ticket_url'] ?? '';

          // Description - populate Quill controllers
          if (data['description'] != null &&
              data['description'].toString().isNotEmpty) {
            final plainDescription = _htmlToPlainText(data['description']);
            _descriptionController.document = Document()
              ..insert(0, plainDescription);
          }

          if (data['entry_details_free'] != null &&
              data['entry_details_free'].toString().isNotEmpty) {
            final plainText = _htmlToPlainText(data['entry_details_free']);
            _entryDetailsFreeController.document = Document()
              ..insert(0, plainText);
          }

          if (data['external_ticket_details'] != null &&
              data['external_ticket_details'].toString().isNotEmpty) {
            final plainText = _htmlToPlainText(data['external_ticket_details']);
            _entryDetailsController.document = Document()..insert(0, plainText);
          }

          // Load cover image
          if (data['cover_photo'] != null &&
              data['cover_photo']['url'] != null) {
            _coverImage = ImageData.fromRemote(
              url: data['cover_photo']['url'],
              id: data['cover_photo']['id'],
            );
            _isCoverImageUploaded = true;
          }

          // Load gallery images
          if (data['gallery'] != null && data['gallery'] is List) {
            _galleryImages = (data['gallery'] as List).map((img) {
              return ImageData.fromRemote(url: img['url'], id: img['id']);
            }).toList();
          }
        });

        // Refresh categories for the selected country
        await _fetchCategories();

        print('✅ Event data loaded successfully');
      } else {
        throw Exception('Failed to load event data');
      }
    } catch (e) {
      print('❌ Error loading event data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading event: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCategories() async {
    final categories = await EventsAPI.getEventCategories(
      country: _selectedCountry,
    );
    if (categories != null && mounted) {
      setState(() {
        _categories = categories;
      });
    }
  }

  /// Convert File to ImageData with base64
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

  Future<void> _pickCoverImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      // maxWidth: 1920,
      // maxHeight: 1080,
      // imageQuality: 85,
    );

    if (image != null) {
      final imageData = await _fileToImageData(File(image.path));
      setState(() {
        _coverImage = imageData;
        _isCoverImageUploaded =
            false; // Mark as not uploaded when new image selected
      });
    }
  }

  Future<void> _pickGalleryImages() async {
    final List<XFile> images = await _picker.pickMultiImage(
      // maxWidth: 1920,
      // maxHeight: 1080,
      // imageQuality: 85,
    );

    if (images.isNotEmpty) {
      // Convert all picked images to ImageData
      final imageDataList = await Future.wait(
        images.map((xFile) => _fileToImageData(File(xFile.path))),
      );

      setState(() {
        _galleryImages.addAll(imageDataList);
        // Don't reset any flag here - individual images track their own upload status
      });
    }
  }

  Future<void> _selectDate(bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          if (_endDate == null || _endDate!.isBefore(picked)) {
            _endDate = picked;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime : _endTime,
    );

    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _getQuillContentAsHtml(QuillController controller) {
    // Convert Quill delta to HTML
    final delta = controller.document.toDelta();
    final plainText = controller.document.toPlainText();

    // Simple conversion - you may want to use a proper delta to HTML converter
    // For now, return plain text wrapped in <p> tags
    if (plainText.trim().isEmpty) return '';

    return plainText
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => '<p>${_escapeHtml(line)}</p>')
        .join('');
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  Future<void> _showUploadProgress(String eventId) async {
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
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Uploading Images',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CircularProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.grey.shade200,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
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
      // Upload cover image (only if not already uploaded)
      if (_coverImage != null && !_isCoverImageUploaded) {
        statusNotifier.value = 'Uploading cover image...';
        print('📤 Starting cover image upload...');

        await EventsAPI.uploadEventImages(
          eventId: eventId,
          images: [_coverImage!],
          type: 'cover',
          onProgress: (progress) {
            print('📊 Cover progress: ${progress.toStringAsFixed(1)}%');
            progressNotifier.value = progress;
          },
        );

        setState(() {
          _isCoverImageUploaded = true;
        });
        print('✅ Cover image uploaded');
      }

      // Filter gallery images to only upload new ones
      final imagesToUpload = _galleryImages
          .where((img) => !img.isUploaded)
          .toList();

      if (imagesToUpload.isNotEmpty) {
        statusNotifier.value =
            'Uploading gallery images (${imagesToUpload.length} new images)...';
        progressNotifier.value = 0; // Reset for gallery upload
        print(
          '📤 Starting gallery upload (${imagesToUpload.length} new images out of ${_galleryImages.length} total)...',
        );

        await EventsAPI.uploadEventImages(
          eventId: eventId,
          images: imagesToUpload,
          type: 'gallery',
          onProgress: (progress) {
            print('📊 Gallery progress: ${progress.toStringAsFixed(1)}%');
            progressNotifier.value = progress;
          },
        );

        // Mark uploaded images as uploaded
        setState(() {
          for (var img in imagesToUpload) {
            img.isUploaded = true;
          }
        });
        print('✅ Gallery images uploaded');
      }

      progressNotifier.dispose();
      statusNotifier.dispose();

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event saved successfully!'),
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

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select event dates')),
      );
      return;
    }

    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid location')),
      );
      return;
    }

    if (_ticketType == '3' && _externalUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('External ticket URL is required')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final description = _getQuillContentAsHtml(_descriptionController);
      final entryDetails = _getQuillContentAsHtml(_entryDetailsController);
      final entryDetailsFree = _getQuillContentAsHtml(
        _entryDetailsFreeController,
      );

      final response = await EventsAPI.saveEvent(
        eventId: _eventID, // Will be null for new events, populated for edits
        title: _titleController.text.trim(),
        country: _selectedCountry,
        location: {
          'address': _locationName ?? _locationController.text.trim(),
          'lat': _lat,
          'lng': _lng,
        },
        categories: _selectedCategories,
        visibility: _visibility,
        status: _status,
        dates: [
          {
            'start_date': DateFormat('yyyy-MM-dd').format(_startDate!),
            'end_date': DateFormat('yyyy-MM-dd').format(_endDate!),
            'start_time':
                '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
            'end_time':
                '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
            'exclude_time': false,
          },
        ],
        description: description,
        externalTicketsUrl: _ticketType == '3'
            ? _externalUrlController.text.trim()
            : null,
        ticketType: _ticketType,
        entryDetailsFree: _ticketType == '1' ? entryDetailsFree : null,
        entryDetails: _ticketType == '3' ? entryDetails : null,
      );

      if (response != null && response['success'] == true) {
        final eventId = response['event_id'].toString();

        setState(() {
          _eventID = eventId;
        });

        print(
          '🎉 Event ${_eventID != null ? "updated" : "created"} with ID: $eventId',
        );

        // Show upload progress dialog only if there are new images to upload
        bool hasNewCoverImage = _coverImage != null && !_isCoverImageUploaded;
        bool hasNewGalleryImages = _galleryImages.any((img) => !img.isUploaded);

        if (hasNewCoverImage || hasNewGalleryImages) {
          await _showUploadProgress(eventId);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Event saved successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception('Failed to save event');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

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
            onPressed: _isLoading ? null : _saveEvent,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.primaryColor,
          labelColor: theme.primaryColor,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Title'),
            Tab(text: 'Dates'),
            Tab(text: 'Details'),
            Tab(text: 'Gallery'),
            Tab(text: 'Tickets'),
            Tab(text: 'Visibility'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTitleTab(theme),
                _buildLazyTab(1, () => _buildDatesTab(theme)),
                _buildLazyTab(2, () => _buildDetailsTab(theme)),
                _buildLazyTab(3, () => _buildGalleryTab(theme)),
                _buildLazyTab(4, () => _buildTicketsTab(theme)),
                _buildLazyTab(5, () => _buildVisibilityTab(theme)),
              ],
            ),
          ),
          if (_isLoading && _uploadProgress > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Uploading images...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${_uploadProgress.toStringAsFixed(0)}%',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _uploadProgress / 100,
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Lazy loading wrapper for tabs
  Widget _buildLazyTab(int index, Widget Function() builder) {
    if (_visitedTabs.contains(index)) {
      return builder();
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildCoverImagePreview() {
    if (_coverImage == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('Tap to Upload', style: TextStyle(color: Colors.grey.shade600)),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _coverImage!.isRemote
              ? CachedNetworkImage(
                  imageUrl: _coverImage!.remoteUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 800, // Downscale for memory efficiency
                  memCacheHeight: 600,
                  placeholder: (context, url) =>
                      Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 48, color: Colors.red.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.red.shade600),
                      ),
                    ],
                  ),
                )
              : Image.file(
                  _coverImage!.file!,
                  fit: BoxFit.cover,
                  cacheWidth: 800, // Downscale local images too
                  cacheHeight: 600,
                ),
        ),
        if (_isCoverImageUploaded)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check_circle, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Uploaded',
                    style: TextStyle(
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
    );
  }

  Widget _buildTitleTab(ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Event Title
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Event Title *',
            hintText: 'Enter event title',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Event title is required';
            }
            return null;
          },
        ),

        const SizedBox(height: 24),

        // Cover Image
        const Text(
          'Event Cover Image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickCoverImage,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _buildCoverImagePreview(),
          ),
        ),

        const SizedBox(height: 24),

        // Country
        const Text(
          'Country *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedCountry,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'gb', child: Text('United Kingdom')),
            DropdownMenuItem(value: 'us', child: Text('United States')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedCountry = value;
                _selectedCategories.clear();
              });
              _fetchCategories();
            }
          },
        ),

        const SizedBox(height: 24),

        // Location
        const Text(
          'Event Location *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GooglePlaceAutoCompleteTextField(
          textEditingController: _locationController,
          googleAPIKey: "AIzaSyDqDMSFVfl-tOgqaj4ZqA5I3HnobrIK6jg",
          focusNode: _locationFocusNode,
          inputDecoration: const InputDecoration(
            hintText: 'Enter event location',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on),
          ),
          debounceTime: 400,
          countries: [_selectedCountry],
          isLatLngRequired: true,
          getPlaceDetailWithLatLng: (Prediction prediction) {
            _locationName = prediction.description ?? '';
            _lat = double.tryParse(prediction.lat ?? '');
            _lng = double.tryParse(prediction.lng ?? '');
          },
          itemClick: (Prediction prediction) {
            _locationController.text = prediction.description ?? '';
            _locationFocusNode.unfocus();
          },
          isCrossBtnShown: true,
        ),

        const SizedBox(height: 24),

        // Categories
        const Text(
          'Event Categories',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _showCategoryPicker(theme),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedCategories.isEmpty
                      ? 'Select Categories'
                      : '${_selectedCategories.length} selected',
                  style: TextStyle(
                    color: _selectedCategories.isEmpty
                        ? Colors.grey.shade600
                        : Colors.black,
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatesTab(ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Start Date
        const Text(
          'Event Start Date *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _selectDate(true),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _startDate != null
                      ? DateFormat('dd/MM/yyyy').format(_startDate!)
                      : 'Select date',
                  style: TextStyle(
                    color: _startDate != null
                        ? Colors.black
                        : Colors.grey.shade600,
                  ),
                ),
                const Icon(Icons.calendar_today, size: 20),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // End Date
        const Text(
          'Event End Date *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _selectDate(false),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _endDate != null
                      ? DateFormat('dd/MM/yyyy').format(_endDate!)
                      : 'Select date',
                  style: TextStyle(
                    color: _endDate != null
                        ? Colors.black
                        : Colors.grey.shade600,
                  ),
                ),
                const Icon(Icons.calendar_today, size: 20),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Start Time
        const Text(
          'Event Start Time',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _selectTime(true),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_startTime.format(context)),
                const Icon(Icons.access_time, size: 20),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // End Time
        const Text(
          'Event End Time',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _selectTime(false),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_endTime.format(context)),
                const Icon(Icons.access_time, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsTab(ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Event Description',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
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
                  controller: _descriptionController,
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
                  controller: _descriptionController,
                  config: const QuillEditorConfig(
                    placeholder: 'Enter event description...',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryTab(ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Add Images',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickGalleryImages,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'Tap to Upload Images',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),

        if (_galleryImages.isNotEmpty) ...[
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _galleryImages.length,
            itemBuilder: (context, index) {
              final imageData = _galleryImages[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageData.isRemote
                        ? CachedNetworkImage(
                            imageUrl: imageData.remoteUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 300, // Small thumbnail size
                            memCacheHeight: 300,
                            maxWidthDiskCache: 300,
                            maxHeightDiskCache: 300,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade200,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade300,
                              child: Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                          )
                        : Image.file(
                            imageData.file!,
                            fit: BoxFit.cover,
                            cacheWidth: 300, // Downscale local images
                            cacheHeight: 300,
                          ),
                  ),
                  // Show upload status badge
                  if (imageData.isUploaded)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check, size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              'Uploaded',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Delete button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeGalleryImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: imageData.isRemote
                              ? Colors.red.shade700
                              : Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          imageData.isRemote ? Icons.delete : Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildTicketsTab(ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Select Ticket Option',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Ticket Type Selection
        _buildTicketTypeButton('1', 'Free or\nNot Required', theme),
        const SizedBox(height: 12),
        _buildTicketTypeButton('3', 'External\nTickets', theme),
        const SizedBox(height: 12),
        _buildTicketTypeButton('2', 'CarEvents.com\nTicketing', theme),

        const SizedBox(height: 24),

        // Show relevant fields based on ticket type
        if (_ticketType == '1') ...[
          const Text(
            'Entry Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildQuillEditor(
            _entryDetailsFreeController,
            'Add information about event entry...',
          ),
        ],

        if (_ticketType == '3') ...[
          const Text(
            'External Ticket Link *',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _externalUrlController,
            decoration: const InputDecoration(
              hintText: 'Enter ticket link',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Entry Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildQuillEditor(
            _entryDetailsController,
            'Add information about event entry...',
          ),
        ],

        if (_ticketType == '2') ...[
          const Text(
            'To sell tickets using our inbuilt ticket platform, please visit CarEvents.com to manage your event.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildQuillEditor(QuillController controller, String placeholder) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
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
          Container(
            height: 250,
            padding: const EdgeInsets.all(12),
            child: QuillEditor.basic(
              controller: controller,
              config: QuillEditorConfig(placeholder: placeholder),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketTypeButton(
    String value,
    String label,
    ThemeProvider theme,
  ) {
    final isSelected = _ticketType == value;
    return InkWell(
      onTap: () => setState(() => _ticketType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? theme.primaryColor : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildVisibilityTab(ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Event Visibility *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _visibility,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: '1', child: Text('Public Event')),
            DropdownMenuItem(value: '2', child: Text('Private Event')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _visibility = value);
            }
          },
        ),

        const SizedBox(height: 24),

        const Text(
          'Status *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _status,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'publish', child: Text('Published')),
            DropdownMenuItem(value: 'draft', child: Text('Draft')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _status = value);
            }
          },
        ),
      ],
    );
  }

  void _showCategoryPicker(ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Categories',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final categoryId = category['id'].toString();
                      final isSelected = _selectedCategories.contains(
                        categoryId,
                      );

                      return CheckboxListTile(
                        title: Text(
                          category['name'].toString().replaceAll('&amp;', '&'),
                        ),
                        value: isSelected,
                        onChanged: (value) {
                          setModalState(() {
                            if (value == true) {
                              _selectedCategories.add(categoryId);
                            } else {
                              _selectedCategories.remove(categoryId);
                            }
                          });
                          setState(() {});
                        },
                        activeColor: theme.primaryColor,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
