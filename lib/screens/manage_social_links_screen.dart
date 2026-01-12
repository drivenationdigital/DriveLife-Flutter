import 'package:flutter/material.dart';

class ManageSocialLinksScreen extends StatefulWidget {
  const ManageSocialLinksScreen({super.key});

  @override
  State<ManageSocialLinksScreen> createState() =>
      _ManageSocialLinksScreenState();
}

class _ManageSocialLinksScreenState extends State<ManageSocialLinksScreen> {
  final _instagramController = TextEditingController();
  final _facebookController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _miviaController = TextEditingController();
  final _custodianController = TextEditingController();

  final List<Map<String, TextEditingController>> _otherLinks = [];

  @override
  void initState() {
    super.initState();
    _loadSocialLinks();
  }

  @override
  void dispose() {
    _instagramController.dispose();
    _facebookController.dispose();
    _tiktokController.dispose();
    _youtubeController.dispose();
    _miviaController.dispose();
    _custodianController.dispose();
    for (var link in _otherLinks) {
      link['controller']?.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSocialLinks() async {
    // TODO: Load from API
    setState(() {
      _instagramController.text = 'kesh.xn';
      _facebookController.text = 'keshanth.jude';
    });
  }

  Future<void> _saveSocialLinks() async {
    // TODO: Save to API
    Navigator.pop(context);
  }

  void _addOtherLink() {
    setState(() {
      _otherLinks.add({
        'name': TextEditingController(text: 'Github'),
        'controller': TextEditingController(),
      });
    });
  }

  void _removeOtherLink(int index) {
    setState(() {
      _otherLinks[index]['name']?.dispose();
      _otherLinks[index]['controller']?.dispose();
      _otherLinks.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          TextButton(
            onPressed: _saveSocialLinks,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Social Links',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField('Instagram', _instagramController),
          const SizedBox(height: 16),
          _buildTextField('Facebook', _facebookController),
          const SizedBox(height: 16),
          _buildTextField(
            'TikTok',
            _tiktokController,
            hint: 'Enter Tiktok Username',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'YouTube',
            _youtubeController,
            hint: 'Enter YouTube Username',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Mivia',
            _miviaController,
            hint: 'Enter Mivia Username',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Custodian Garage / Car link',
            _custodianController,
            hint: 'Enter Custodian Username',
          ),
          const SizedBox(height: 32),
          const Text(
            'Other Links',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          ..._otherLinks.asMap().entries.map((entry) {
            final index = entry.key;
            final link = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildOtherLinkField(
                link['name']!.text,
                link['controller']!,
                () => _removeOtherLink(index),
              ),
            );
          }),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _addOtherLink,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'ADD LINK',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
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
      ],
    );
  }

  Widget _buildOtherLinkField(
    String label,
    TextEditingController controller,
    VoidCallback onRemove,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            IconButton(
              icon: Icon(Icons.cancel, color: Colors.grey.shade400, size: 20),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
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
      ],
    );
  }
}
