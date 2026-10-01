import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen images, swipeable and zoomable.
///
/// The plain lightbox: a list of URLs, a page indicator and a close button.
/// Anything with its own actions — likes, tags, deleting — wants a viewer that
/// knows about those; this is for pictures that are only pictures.
class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              // Cached, so opening this from a page that has already shown
              // the image is instant rather than a second download over the
              // same connection.
              child: CachedNetworkImage(
                imageUrl: widget.images[index],
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
