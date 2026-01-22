import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:html_editor_enhanced/html_editor.dart';
import 'package:intl/intl.dart';

class AddEventScreen extends StatefulWidget {
  const AddEventScreen({super.key});

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
  final _descriptionController = HtmlEditorController();
  final _entryDetailsController = HtmlEditorController();
  final _entryDetailsFreeController = HtmlEditorController();

  // Location
  final FocusNode _locationFocusNode = FocusNode();
  double? _lat;
  double? _lng;
  String? _locationName;

  // Images
  File? _coverImage;
  List<File> _galleryImages = [];
  final ImagePicker _picker = ImagePicker();

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

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _fetchCategories();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _locationController.dispose();
    _externalUrlController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
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

  Future<void> _pickCoverImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _coverImage = File(image.path);
      });
    }
  }

  Future<void> _pickGalleryImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _galleryImages.addAll(images.map((e) => File(e.path)));
      });
    }
  }

  void _removeGalleryImage(int index) {
    setState(() {
      _galleryImages.removeAt(index);
    });
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
      final description = await _descriptionController.getText();
      final entryDetails = await _entryDetailsController.getText();
      final entryDetailsFree = await _entryDetailsFreeController.getText();

      final response = await EventsAPI.saveEvent(
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

        // Upload images
        if (_coverImage != null) {
          await EventsAPI.uploadEventImages(
            eventId: eventId,
            images: [_coverImage!],
            type: 'cover',
          );
        }

        if (_galleryImages.isNotEmpty) {
          await EventsAPI.uploadEventImages(
            eventId: eventId,
            images: _galleryImages,
            type: 'gallery',
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event created successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Failed to create event');
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
          icon: const Icon(Icons.chevron_left, color: Colors.black),
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
          // isScrollable: true,
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
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildTitleTab(theme),
            _buildDatesTab(theme),
            _buildDetailsTab(theme),
            _buildGalleryTab(theme),
            _buildTicketsTab(theme),
            _buildVisibilityTab(theme),
          ],
        ),
      ),
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
            child: _coverImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_coverImage!, fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to Upload',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
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
          height: 400,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: HtmlEditor(
            controller: _descriptionController,
            htmlEditorOptions: const HtmlEditorOptions(
              hint: "Enter event description...",
              shouldEnsureVisible: true,
            ),
            htmlToolbarOptions: const HtmlToolbarOptions(
              toolbarPosition: ToolbarPosition.aboveEditor,
              toolbarType: ToolbarType.nativeScrollable,
              defaultToolbarButtons: [
                StyleButtons(),
                FontButtons(),
                ListButtons(listStyles: false),
                // ParagraphButtons(),
                // InsertButtons(
                //   video: false,
                //   audio: false,
                //   table: false,
                //   hr: false,
                //   otherFile: false,
                // ),
              ],
            ),
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
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_galleryImages[index], fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeGalleryImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
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
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: HtmlEditor(
              controller: _entryDetailsFreeController,
              htmlEditorOptions: const HtmlEditorOptions(
                hint: "Add information about event entry...",
              ),
              htmlToolbarOptions: const HtmlToolbarOptions(
                toolbarType: ToolbarType.nativeScrollable,
              ),
            ),
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
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: HtmlEditor(
              controller: _entryDetailsController,
              htmlEditorOptions: const HtmlEditorOptions(
                hint: "Add information about event entry...",
              ),
              htmlToolbarOptions: const HtmlToolbarOptions(
                toolbarType: ToolbarType.nativeScrollable,
              ),
            ),
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
