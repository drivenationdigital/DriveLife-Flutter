import 'package:drivelife/api/drivelife_api_service.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/models/product_model.dart';
import 'package:html_unescape/html_unescape.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isLoading = true;
  Product? _product;
  List<String> _galleryImages = [];
  String? _error;
  late PageController _imagePageController; // ADD THIS

  // Selection states
  int _selectedImageIndex = 0;
  ProductColour? _selectedColour;
  String? _selectedSize;
  int _quantity = 1;

  // Expandable sections
  bool _showFullDescription = false;
  bool _showMoreInfo = false;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _loadProduct();
  }

  @override
  void dispose() {
    _imagePageController.dispose(); // ADD THIS
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await DriveLifeApiService.getProductById(
        widget.productId,
      );

      if (response.products.isNotEmpty) {
        final product = response.products.first;

        // Build gallery images: main image + gallery
        final gallery = <String>[product.image];
        if (product.gallery != null && product.gallery!.isNotEmpty) {
          gallery.addAll(product.gallery!);
        }

        setState(() {
          _product = product;
          _galleryImages = gallery;
          _isLoading = false;

          // Pre-select first color if available
          if (product.colours.isNotEmpty) {
            _selectedColour = product.colours.first;
          }
        });
      } else {
        setState(() {
          _error = 'Product not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load product: $e';
        _isLoading = false;
      });
    }
  }

  void _addToCart() {
    if (_product == null) return;

    // Validate selections
    if (_product!.colours.isNotEmpty && _selectedColour == null) {
      _showSnackbar('Please select a color', isError: true);
      return;
    }

    if (_product!.sizes.isNotEmpty && _selectedSize == null) {
      _showSnackbar('Please select a size', isError: true);
      return;
    }

    final cartProvider = context.read<CartProvider>();

    for (int i = 0; i < _quantity; i++) {
      cartProvider.addToCart(
        productId: _product!.id.toString(),
        name: _product!.name,
        price: _product!.effectivePrice,
        isOnSale: _product!.isOnSale,
        originalPrice: _product!.price,
        currencySymbol: _product!.currencySymbol,
        image: _product!.image,
        variant: _product!.variant,
        selectedColorHex: _selectedColour?.hex,
        selectedColorName: _selectedColour?.name,
        selectedSize: _selectedSize,
        supplierSku: _selectedColour?.sku,
      );
    }

    _showSnackbar('${_product!.name} added to basket');

    // Reset quantity after adding
    setState(() => _quantity = 1);
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFFAE9159),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? _buildLoadingState(theme)
          : _error != null
          ? _buildErrorState()
          : _buildProductDetail(theme),
      bottomNavigationBar: !_isLoading && _error == null && _product != null
          ? _buildBottomBar(theme)
          : null,
    );
  }

  Widget _buildLoadingState(ThemeProvider theme) {
    return Center(child: CircularProgressIndicator(color: theme.primaryColor));
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _error ?? 'An error occurred',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductDetail(ThemeProvider theme) {
    if (_product == null) return const SizedBox();

    return CustomScrollView(
      slivers: [
        // App bar
        SliverAppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: Image.asset('assets/logo-dark.png', height: 18),
          // actions: [
          //   IconButton(
          //     icon: const Icon(Icons.share_outlined, color: Colors.black),
          //     onPressed: () {
          //       // Share product
          //     },
          //   ),
          //   IconButton(
          //     icon: const Icon(Icons.favorite_border, color: Colors.black),
          //     onPressed: () {
          //       // Add to favorites
          //     },
          //   ),
          // ],
        ),

        // Content
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image gallery
              _buildImageGallery(),

              // Product info
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      _product!.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Price
                    _buildPriceSection(),
                    const SizedBox(height: 20),

                    // Stock status
                    if (!_product!.inStock)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'OUT OF STOCK',
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),

                    if (_product!.inStock) ...[
                      // Color selector
                      if (_product!.colours.isNotEmpty) ...[
                        _buildColorSelector(),
                        const SizedBox(height: 24),
                      ],

                      // Size selector
                      if (_product!.sizes.isNotEmpty) ...[
                        _buildSizeSelector(),
                        const SizedBox(height: 24),
                      ],

                      // Description
                      _buildDescription(),
                      const SizedBox(height: 24),

                      // Sizing information link
                      if (_product!.sizes.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            // Show sizing information
                            _showSizingInfo();
                          },
                          child: const Row(
                            children: [
                              Text(
                                'Sizing information',
                                style: TextStyle(
                                  color: Color(0xFFAE9159),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                color: Color(0xFFAE9159),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),

                      // More information
                      _buildMoreInformation(),
                    ],

                    const SizedBox(height: 100), // Space for bottom bar
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. Update _buildImageGallery to use PageView
  Widget _buildImageGallery() {
    return Column(
      children: [
        // Main image - now swipeable
        GestureDetector(
          onTap: () => _showImageViewer(context),
          child: Container(
            height: 400,
            width: double.infinity,
            color: Colors.grey.shade50,
            child: PageView.builder(
              controller: _imagePageController,
              onPageChanged: (index) {
                setState(() => _selectedImageIndex = index);
              },
              itemCount: _galleryImages.length,
              itemBuilder: (context, index) {
                return Hero(
                  tag: 'product-image-${_product!.id}-$index',
                  child: Image.network(
                    _galleryImages[index],
                    fit: BoxFit.contain,
                  ),
                );
              },
            ),
          ),
        ),

        // Page indicator dots
        if (_galleryImages.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _galleryImages.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedImageIndex == index
                      ? const Color(0xFFAE9159)
                      : Colors.grey.shade300,
                ),
              ),
            ),
          ),
        ],

        // Thumbnail gallery
        if (_galleryImages.length > 1) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _galleryImages.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedImageIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedImageIndex = index);
                    _imagePageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFAE9159)
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.network(
                        _galleryImages[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSection() {
    if (_product!.isOnSale && _product!.formattedSalePrice != null) {
      final savings = _product!.price - _product!.salePrice!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _decodeHtml(_product!.formattedSalePrice!),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFAE9159),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _decodeHtml(_product!.formattedPrice),
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Save ${_decodeHtml("${_product!.currencySymbol}${savings.toStringAsFixed(2)}")}',
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      _decodeHtml(_product!.formattedPrice),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Color(0xFFAE9159),
      ),
    );
  }

  Widget _buildDescription() {
    final description = _product!.description ?? '';
    final cleanDescription = _decodeHtml(description);

    if (cleanDescription.isEmpty) return const SizedBox();

    final shouldTruncate = cleanDescription.length > 200;
    final displayText = shouldTruncate && !_showFullDescription
        ? '${cleanDescription.substring(0, 200)}...'
        : cleanDescription;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayText,
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Colors.grey.shade700,
          ),
        ),
        if (shouldTruncate) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                setState(() => _showFullDescription = !_showFullDescription),
            child: Text(
              _showFullDescription ? 'Show less' : 'Read more',
              style: const TextStyle(
                color: Color(0xFFAE9159),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSizeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Size',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _product!.sizes.map((size) {
            final isSelected = _selectedSize == size;
            return GestureDetector(
              onTap: () => setState(() => _selectedSize = size),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.white,
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  size.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.black87,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildColorSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Colour',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _product!.colours.map((colour) {
            final isSelected = _selectedColour?.hex == colour.hex;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedColour = colour);

                // Scroll to matching gallery image
                if (colour.mockupFront != null) {
                  final matchingIndex = _galleryImages.indexOf(
                    colour.mockupFront!,
                  );
                  if (matchingIndex != -1) {
                    setState(() => _selectedImageIndex = matchingIndex);
                    _imagePageController.animateToPage(
                      matchingIndex,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                }
              },
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse(colour.hex.replaceFirst('#', '0xFF')),
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey.shade300,
                        width: isSelected ? 3 : 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: _getContrastColor(colour.hex),
                            size: 24,
                          )
                        : null,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        if (_selectedColour != null) ...[
          const SizedBox(height: 12),
          Text(
            'Selected: ${_selectedColour!.name}',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantitySelector() {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _quantity > 1
                    ? () => setState(() => _quantity--)
                    : null,
                icon: const Icon(Icons.remove),
                iconSize: 20,
                color: _quantity > 1 ? Colors.black : Colors.grey.shade400,
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 40),
                child: Text(
                  '$_quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: _quantity < 10
                    ? () => setState(() => _quantity++)
                    : null,
                icon: const Icon(Icons.add),
                iconSize: 20,
                color: _quantity < 10 ? Colors.black : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMoreInformation() {
    final shortDesc = _product!.shortDescription ?? '';
    final cleanShortDesc = _decodeHtml(shortDesc);

    if (cleanShortDesc.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showMoreInfo = !_showMoreInfo),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'More Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Icon(
                  _showMoreInfo
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
        if (_showMoreInfo) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              cleanShortDesc,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar(ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Quantity selector - 30% width
            Expanded(flex: 5, child: _buildQuantitySelector()),

            // Add to basket button - 70% width
            Expanded(
              flex: 7,
              child: ElevatedButton(
                onPressed: _product!.inStock ? _addToCart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _product!.inStock ? 'Add to basket' : 'Out of Stock',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageViewer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          images: _galleryImages,
          initialIndex: _selectedImageIndex,
        ),
      ),
    );
  }

  void _showSizingInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sizing Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Please refer to our size guide to find your perfect fit. Measurements are in centimeters.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // You can add a size chart table here
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFAE9159),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getContrastColor(String hexColor) {
    final color = Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    final luminance =
        (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  String _decodeHtml(String html) {
    final unescape = HtmlUnescape();
    return unescape.convert(html).replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}

// Image viewer for full-screen gallery
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
              child: Image.network(widget.images[index], fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}
