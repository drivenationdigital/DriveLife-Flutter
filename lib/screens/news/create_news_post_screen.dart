import 'dart:io';

import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/search_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:fluttertagger/fluttertagger.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

class NewsMediaItem {
  final File file;
  NewsMediaItem({required this.file});
}

class CreateNewsScreen extends StatefulWidget {
  const CreateNewsScreen({super.key});

  @override
  State<CreateNewsScreen> createState() => _CreateNewsScreenState();
}

class _CreateNewsScreenState extends State<CreateNewsScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _titleController = TextEditingController();
  final QuillController _quillController = QuillController.basic();
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Document _savedDocument = Document(); // ← stores the saved quill content
  final FlutterTaggerController _captionController = FlutterTaggerController();

  // State
  List<NewsMediaItem> _images = [];
  int _currentPage = 0;
  bool _isPosting = false;
  bool _toolbarVisible = false;

  // ── Accent colour shared across the screen ──
  static const Color _gold = Color(0xFFAE9159);

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _pageController.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Image helpers
  // ─────────────────────────────────────────────

  Future<void> _pickImages() async {
    final List<XFile> picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;

    final remaining = 10 - _images.length;
    final toAdd = picked.take(remaining);

    setState(() {
      _images.addAll(toAdd.map((x) => NewsMediaItem(file: File(x.path))));
    });

    if (picked.length > remaining) {
      _showSnack('Maximum 10 images allowed');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      if (_currentPage >= _images.length && _currentPage > 0) {
        _currentPage = _images.length - 1;
        _pageController.jumpToPage(_currentPage);
      }
    });
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

  Future<void> _publishPost() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack('Please add a title', isError: true);
      return;
    }

    final delta = _quillController.document.toDelta();
    final isBodyEmpty =
        delta.toJson().length == 1 &&
        (delta.toJson().first['insert'] as String?)?.trim().isEmpty == true;

    if (isBodyEmpty) {
      _showSnack('Please write some content', isError: true);
      return;
    }

    setState(() => _isPosting = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        _showSnack('User not found', isError: true);
        return;
      }

      final userId = int.parse(user.id.toString());

      // Generate unique upload ID
      final uploadId = 'upload_${DateTime.now().millisecondsSinceEpoch}';
      final htmlContent = _getQuillContentAsHtml(_quillController);

      // Prepare upload data
      final uploadData = UploadPostData(
        id: uploadId,
        mediaFiles: _images.map((m) => m.file).toList(),
        isVideoList: List.filled(_images.length, false),
        caption: title, // Using title as caption for news posts
        newsContent: htmlContent,
        userId: userId,
        taggedEvents: [],
        taggedUsers: [],
        taggedVehicles: []
      );

      // Start background upload
      if (mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);

        Provider.of<UploadPostProvider>(
          context,
          listen: false,
        ).startUpload(uploadData, userProvider);
      }

      if (mounted) {
        Navigator.pop(context, true);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Uploading news post in background...'),
            backgroundColor: const Color(0xFFAE9159),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _showSnack('Failed to publish: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade600 : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Build helpers
  // ─────────────────────────────────────────────

  Widget _buildHeroImageSection() {
    if (_images.isEmpty) {
      // Empty state — tap to add
      return GestureDetector(
        onTap: _pickImages,
        child: Container(
          height: 240,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: _gold,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Add Cover Images',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Up to 10 images • Tap to browse',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    // Image carousel
    return Stack(
      children: [
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  Image.file(_images[index].file, fit: BoxFit.contain),
                  // Dark gradient at top for remove button legibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  // Remove button
                  Positioned(
                    top: 14,
                    right: 14,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Image counter badge
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${index + 1} / ${_images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Dot indicators
        if (_images.length > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _images.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == i ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? _gold
                        : Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        // Add more button (bottom-right corner)
        if (_images.length < 10)
          Positioned(
            bottom: 14,
            right: 14,
            child: GestureDetector(
              onTap: _pickImages,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Add Image',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: TextField(
        controller: _titleController,
        maxLines: null,
        maxLength: 150,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          letterSpacing: -0.6,
          height: 1.25,
        ),
        decoration: InputDecoration(
          hintText: 'News title...',
          hintStyle: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade300,
            letterSpacing: -0.6,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          counterStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_gold, _gold.withOpacity(0.0)]),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildToolbar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _toolbarVisible ? null : 0,
      child: _toolbarVisible
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                  bottom: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: QuillSimpleToolbar(
                controller: _quillController,
                config: QuillSimpleToolbarConfig(
                  showFontFamily: false,
                  showFontSize: true,
                  showBackgroundColorButton: false,
                  showClearFormat: true,
                  showColorButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showSearchButton: false,
                  showClipboardPaste: false,
                  showClipboardCut: false,
                  showClipboardCopy: false,
                  showInlineCode: false,
                  showCodeBlock: false,
                  showSmallButton: false,
                  showRedo: true,
                  showUndo: true,
                  showStrikeThrough: true,
                  showListBullets: true,
                  showListNumbers: true,
                  showQuote: true,
                  showLink: true,
                  toolbarIconAlignment: WrapAlignment.start,
                  buttonOptions: QuillSimpleToolbarButtonOptions(
                    base: QuillToolbarBaseButtonOptions(
                      iconTheme: QuillIconTheme(
                        iconButtonSelectedData: IconButtonData(
                          color: _gold,
                          style: IconButton.styleFrom(
                            backgroundColor: _gold.withOpacity(0.12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildContentPreview() {
    final isEmpty = _savedDocument.isEmpty();

    return GestureDetector(
      onTap: () async {
        // Navigate to full-screen editor, get document back on save
        final result = await Navigator.push<Document>(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenEditorScreen(
              // ↓ Clone via Delta — never pass the live Document instance directly
              initialDocument: Document.fromJson(
                _savedDocument.toDelta().toJson(),
              ),
            ),
          ),
        );
        if (result != null) {
          setState(() {
            _savedDocument = result;
            // Sync quill controller so publish still works
            _quillController.document = result;
          });
        }
      },
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 120),
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isEmpty ? Colors.grey.shade200 : Colors.transparent,
          ),
        ),
        child: isEmpty
            ? Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: Colors.grey.shade400,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Tap to write your article...',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade400,
                      height: 1.6,
                    ),
                  ),
                ],
              )
            : QuillEditor(
                focusNode: FocusNode()..unfocus(), // read-only, no focus
                scrollController: ScrollController(),
                controller: QuillController(
                  document: _savedDocument,
                  selection: const TextSelection.collapsed(offset: 0),
                  readOnly: true,
                ),
                config: QuillEditorConfig(
                  scrollable: false,
                  expands: false,
                  autoFocus: false,
                  enableInteractiveSelection: false,
                  padding: EdgeInsets.zero,
                  // same customStyles as before...
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      // ── App Bar ──────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withOpacity(0.06),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => _confirmDiscard(),
        ),
        centerTitle: true,
        title: Column(
          children: [
            const Text(
              'Create News',
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Editorial',
              style: TextStyle(
                color: _gold,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          // Toolbar toggle button
          IconButton(
            onPressed: () => setState(() => _toolbarVisible = !_toolbarVisible),
            icon: Icon(
              Icons.format_color_text_rounded,
              color: _toolbarVisible ? _gold : Colors.grey.shade500,
              size: 22,
            ),
            tooltip: 'Formatting',
          ),
          // Publish button
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: TextButton(
              onPressed: _isPosting ? null : _publishPost,
              style: TextButton.styleFrom(
                backgroundColor: _isPosting ? Colors.grey.shade200 : _gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                minimumSize: Size.zero,
              ),
              child: _isPosting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Publish',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ],
      ),

      // ── Body ─────────────────────────────────
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroImageSection(),
                  _buildTitleField(),
                  _buildDivider(),
                  // _buildCaptionField(),
                  // _buildDivider(),
                  _buildContentPreview(), // ← replaces the editor
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final titleEmpty = _titleController.text.trim().isEmpty;
    final delta = _quillController.document.toDelta();
    final bodyEmpty =
        delta.toJson().length == 1 &&
        (delta.toJson().first['insert'] as String?)?.trim().isEmpty == true;

    if (titleEmpty && bodyEmpty && _images.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Discard article?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          "Your draft won't be saved.",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep Editing',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (discard == true && mounted) Navigator.pop(context);
  }
}

class FullScreenEditorScreen extends StatefulWidget {
  final Document initialDocument;
  const FullScreenEditorScreen({super.key, required this.initialDocument});

  @override
  State<FullScreenEditorScreen> createState() => _FullScreenEditorScreenState();
}

class _FullScreenEditorScreenState extends State<FullScreenEditorScreen> {
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _toolbarVisible = true;

  static const Color _gold = Color(0xFFAE9159);

  @override
  void initState() {
    super.initState();

    // ── Sample article for testing ──────────────────────────────
    final sampleDelta = Delta()
      // ↓ Text is plain, '\n' carries the block attribute
      ..insert('Ferrari SF-24 Review: The Prancing Horse Roars Back')
      ..insert('\n', {
        'header': 1,
      }) // ← was: insert(text, {'header':1}) then insert('\n')
      ..insert('\n')
      ..insert(
        'After a turbulent 2023 season, Ferrari has returned with a car that feels genuinely special. We spent two days at Fiorano putting the SF-24 through its paces — and came away believers.',
      )
      ..insert('\n')
      ..insert('\n')
      ..insert('First Impressions')
      ..insert('\n', {'header': 2}) // ← header on the \n
      ..insert(
        'The moment you walk into the paddock and see the SF-24 under the Maranello sun, something stirs. The aggressive sidepod undercut, the revised front wing geometry, and that unmistakable Rosso Corsa livery all signal that Ferrari means business this year.',
      )
      ..insert('\n')
      ..insert('\n')
      ..insert('On Track')
      ..insert('\n', {'header': 2})
      ..insert(
        'Charles Leclerc set the tone on day one, posting a time that left the engineering crew quietly nodding. The SF-24\'s biggest leap forward is mechanical grip — mid-corner confidence is transformed compared to last year\'s car.',
      )
      ..insert('\n')
      ..insert('\n')
      ..insert('Key highlights from our two days:')
      ..insert('\n')
      ..insert('Rear stability under hard braking is dramatically improved')
      ..insert('\n', {'list': 'bullet'}) // ← list on the \n
      ..insert(
        'The updated power unit delivers a noticeable step in straight-line performance',
      )
      ..insert('\n', {'list': 'bullet'})
      ..insert('Tyre degradation remains the one area still under development')
      ..insert('\n', {'list': 'bullet'})
      ..insert('\n')
      ..insert('"This is the car we should have had twelve months ago."')
      ..insert('\n', {'blockquote': true}) // ← blockquote on the \n
      ..insert('\n')
      ..insert('Verdict')
      ..insert('\n', {'header': 2})
      ..insert(
        'The SF-24 is not yet a championship-winning car on paper, but it is a serious one. Ferrari\'s engineers have addressed the fundamental weaknesses that plagued 2023, and the result is a machine that finally lets its drivers push without fear. Tifosi, take heart — the Scuderia is back.',
      )
      ..insert('\n');

    final sampleDoc = Document.fromDelta(sampleDelta);

    // ── Swap this out once testing is done ──────────────────────
    final docToLoad = widget.initialDocument.isEmpty()
        ? sampleDoc
        : Document.fromJson(widget.initialDocument.toDelta().toJson());

    _controller = QuillController(
      document: docToLoad,
      selection: const TextSelection.collapsed(offset: 0),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context), // discard changes
        ),
        title: const Text(
          'Write Article',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _toolbarVisible = !_toolbarVisible),
            icon: Icon(
              Icons.format_color_text_rounded,
              color: _toolbarVisible ? _gold : Colors.grey.shade400,
              size: 22,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  // ↓ Return a fresh clone so the parent's copy is also independent
                  Document.fromJson(_controller.document.toDelta().toJson()),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                minimumSize: Size.zero,
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          if (_toolbarVisible)
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: QuillSimpleToolbar(
                controller: _controller,
                config: const QuillSimpleToolbarConfig(
                  showFontFamily: false,
                  showBackgroundColorButton: false,
                  showColorButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showInlineCode: false,
                  showCodeBlock: false,
                  showSmallButton: false,
                  showClipboardPaste: false,
                  showClipboardCut: false,
                  showClipboardCopy: false,
                  showSearchButton: false,
                ),
              ),
            ),

          // Full-screen editor
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: QuillEditor(
                focusNode: _focusNode,
                scrollController: _scrollController,
                controller: _controller,
                config: QuillEditorConfig(
                  scrollable: true,
                  expands: true, // fills all remaining space
                  autoFocus: true, // keyboard opens immediately
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  placeholder: 'Start writing...',
                  // paste your same customStyles here
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
