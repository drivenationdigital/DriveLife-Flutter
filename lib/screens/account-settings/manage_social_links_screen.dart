import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  List<Map<String, dynamic>> _otherLinks = [];
  bool _isSaving = false;
  bool _isLoading = true;

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
    super.dispose();
  }

  Future<void> _loadSocialLinks() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    if (user != null) {
      setState(() {
        final profileLinks = user.profileLinks;
        final externalLinks = profileLinks?.externalLinks;

        _instagramController.text = profileLinks?.instagram ?? '';
        _facebookController.text = profileLinks?.facebook ?? '';
        _tiktokController.text = profileLinks?.tiktok ?? '';
        _youtubeController.text = profileLinks?.youtube ?? '';
        _miviaController.text = profileLinks?.mivia ?? '';
        _custodianController.text = profileLinks?.custodian ?? '';

        if (externalLinks != null) {
          _otherLinks = externalLinks
              .map(
                (link) => {
                  'id': link.id,
                  'label': link.link.label,
                  'url': link.link.url,
                },
              )
              .toList();
        }

        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  String _cleanUsername(String username) {
    return username.startsWith('@') ? username.substring(1) : username;
  }

  bool _isValidUsername(String username) {
    final pattern = RegExp(r'^[a-zA-Z0-9._-]+$');
    return pattern.hasMatch(username);
  }

  bool _isFullFacebookUrl(String input) {
    return input.contains('facebook.com') || input.contains('fb.com');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _saveSocialLinks() async {
    setState(() => _isSaving = true);

    try {
      // Clean and validate usernames
      String instagram = _instagramController.text.trim();
      String facebook = _facebookController.text.trim();
      String tiktok = _tiktokController.text.trim();
      String youtube = _youtubeController.text.trim();
      String mivia = _miviaController.text.trim();
      String custodian = _custodianController.text.trim();

      // Validate Instagram
      if (instagram.isNotEmpty) {
        instagram = _cleanUsername(instagram);
        if (!_isValidUsername(instagram)) {
          _showError(
            'Invalid Instagram username (letters, numbers, _, -, . only)',
          );
          setState(() => _isSaving = false);
          return;
        }
      }

      // Validate TikTok
      if (tiktok.isNotEmpty) {
        tiktok = _cleanUsername(tiktok);
        if (!_isValidUsername(tiktok)) {
          _showError(
            'Invalid TikTok username (letters, numbers, _, -, . only)',
          );
          setState(() => _isSaving = false);
          return;
        }
      }

      // Validate YouTube
      if (youtube.isNotEmpty) {
        youtube = _cleanUsername(youtube);
        if (!_isValidUsername(youtube)) {
          _showError(
            'Invalid YouTube username (letters, numbers, _, -, . only)',
          );
          setState(() => _isSaving = false);
          return;
        }
      }

      // Validate Mivia
      if (mivia.isNotEmpty) {
        mivia = _cleanUsername(mivia);
        if (!_isValidUsername(mivia)) {
          _showError('Invalid Mivia username (letters, numbers, _, -, . only)');
          setState(() => _isSaving = false);
          return;
        }
      }

      // Validate Custodian
      if (custodian.isNotEmpty && !custodian.startsWith('https://')) {
        _showError('Custodian URL must start with https://');
        setState(() => _isSaving = false);
        return;
      }

      // Validate Facebook
      if (facebook.isNotEmpty) {
        if (!_isFullFacebookUrl(facebook)) {
          facebook = _cleanUsername(facebook);
          if (!_isValidUsername(facebook)) {
            _showError(
              'Invalid Facebook username (letters, numbers, _, -, . only)',
            );
            setState(() => _isSaving = false);
            return;
          }
        }
      }

      final links = {
        'instagram': instagram,
        'facebook': facebook,
        'tiktok': tiktok,
        'youtube': youtube,
        'mivia': mivia,
        'custodian': custodian,
      };

      print('🔄 [ManageSocialLinks] Updating social links...');

      final response = await ProfileAPI.updateSocialLinks(links);

      if (!mounted) return;

      if (response != null && response['success'] == true) {
        // Update UserProvider
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.refreshUser();

        // Clear profile cache
        print('✅ [ManageSocialLinks] Social links updated');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Social links updated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context, true);
      } else {
        throw Exception(response?['message'] ?? 'Failed to update');
      }
    } catch (e) {
      print('❌ [ManageSocialLinks] Error: $e');

      String errorMessage = e.toString();
      if (errorMessage.contains('Exception:')) {
        errorMessage = errorMessage.replaceFirst('Exception: ', '');
      }

      _showError('Failed to update: $errorMessage');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showAddLinkModal() {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Link',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Link Title',
                  hintText: 'E.g. My Website',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFAE9159)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: 'Link URL',
                  hintText: 'E.g. https://www.mylink.com',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFAE9159)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _addExternalLink(
                    titleController.text,
                    urlController.text,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'SAVE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addExternalLink(String title, String url) async {
    if (title.isEmpty) {
      _showError('Please enter a link title');
      return;
    }

    if (url.isEmpty) {
      _showError('Please enter a link URL');
      return;
    }

    // Validate URL
    final urlPattern = RegExp(
      r'^(https?:\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)$',
    );

    if (!urlPattern.hasMatch(url)) {
      _showError('Please enter a valid URL');
      return;
    }

    Navigator.pop(context); // Close modal

    setState(() => _isSaving = true);

    try {
      print('🔄 [ManageSocialLinks] Adding external link: $title');

      final response = await ProfileAPI.addUserProfileLinks(
        link: {'label': title, 'url': url},
        type: 'external_links',
      );

      if (!mounted) return;

      if (response != null && response['success'] == true) {
        setState(() {
          _otherLinks.add({'id': response['id'], 'label': title, 'url': url});
        });

        // Update UserProvider
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.refreshUser();

        print('✅ [ManageSocialLinks] External link added');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response?['message'] ?? 'Failed to add link');
      }
    } catch (e) {
      print('❌ [ManageSocialLinks] Error: $e');
      _showError('Failed to add link: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteExternalLink(int index) async {
    final link = _otherLinks[index];
    final linkId = link['id'];

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Link'),
        content: const Text('Are you sure you want to delete this link?'),
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

    setState(() => _isSaving = true);

    try {
      print('🔄 [ManageSocialLinks] Deleting link ID: $linkId');

      final response = await ProfileAPI.removeProfileLink(linkId);

      if (!mounted) return;

      if (response == true) {
        setState(() {
          _otherLinks.removeAt(index);
        });

        // Update UserProvider
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.refreshUser();

        print('✅ [ManageSocialLinks] Link deleted');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Failed to delete link');
      }
    } catch (e) {
      print('❌ [ManageSocialLinks] Error: $e');
      _showError('Failed to delete link: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Image.asset('assets/logo-dark.png', height: 18),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSocialLinks,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
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
      body: Container(
        padding: const EdgeInsets.only(bottom: 16),
        // add more space in the bottom for the button
        height: double.infinity,
        child: ListView(
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
              hint: 'Enter Custodian URL (https://...)',
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
                  link['label'] as String,
                  link['url'] as String,
                  () => _deleteExternalLink(index),
                ),
              );
            }),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _showAddLinkModal,
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
            const SizedBox(height: 46),
          ],
        ),
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

  Widget _buildOtherLinkField(String label, String url, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  url,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.cancel, color: Colors.grey.shade400, size: 24),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
