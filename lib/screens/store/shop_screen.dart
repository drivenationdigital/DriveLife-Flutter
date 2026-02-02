import 'package:drivelife/api/drivelife_api_service.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/store/checkout/stripe_checkout_screen.dart';
import 'package:drivelife/screens/store/my_orders_tab.dart';
import 'package:drivelife/screens/store/product_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/models/banner_model.dart';
import 'package:drivelife/models/product_model.dart';
import 'package:html_unescape/html_unescape.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  // Loading states
  bool _isLoadingBanners = true;
  bool _isLoadingProducts = true;

  // Data
  List<ProductsBanner> _banners = [];
  List<Product> _products = [];
  String? _selectedCategory; // This will be 'featured' for popular
  int _currentPage = 1;
  Pagination? _pagination;
  CategoryInfo? _categoryInfo;

  int _currentBannerIndex = 0;

  // Sort and filter
  String _sortBy = 'popularity'; // popularity or price
  String _filterBy = 'all'; // all, men, women, unisex

  // Hardcoded categories
  final List<Map<String, String>> _categories = [
    {'name': 'Popular', 'slug': 'featured'},
    {'name': 'New Arrivals', 'slug': 'new-arrivals'},
    {'name': 'Men', 'slug': 'mens'},
    {'name': 'Women', 'slug': 'womens'},
    {'name': 'Brands & Clubs', 'slug': 'brands-and-car-clubs'},
    {'name': 'Sale', 'slug': 'sale'},
  ];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().loadCart();
      _loadBanners();
      _loadFeaturedProducts();
    });
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  // Load banners
  Future<void> _loadBanners() async {
    setState(() => _isLoadingBanners = true);

    try {
      final response = await DriveLifeApiService.getBanners();
      setState(() {
        _banners = response.banners;
        _isLoadingBanners = false;
      });
    } catch (e) {
      setState(() => _isLoadingBanners = false);
      _showError('Failed to load banners: $e');
    }
  }

  // Load featured products
  Future<void> _loadFeaturedProducts() async {
    setState(() => _isLoadingProducts = true);

    // reset category info, filters, and pagination
    _categoryInfo = null;
    _pagination = null;
    _sortBy = 'popularity';
    _filterBy = 'all';

    try {
      final response = await DriveLifeApiService.getFeaturedProducts();
      setState(() {
        _products = response.products;
        _isLoadingProducts = false;
        _selectedCategory =
            'featured'; // Set this so the Popular pill shows as active
      });
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      _showError('Failed to load products: $e');
    }
  }

  // Load products by category
  Future<void> _loadProductsByCategory(
    String categorySlug, {
    int page = 1,
  }) async {
    // If clicking on "featured/popular" and already on it, don't reload
    if (categorySlug == 'featured' &&
        _selectedCategory == 'featured' &&
        !_isLoadingProducts) {
      return;
    }

    setState(() {
      _isLoadingProducts = true;
      _selectedCategory = categorySlug;
    });

    try {
      final response = await DriveLifeApiService.getProductsByCategory(
        categorySlug: categorySlug,
        page: page,
      );

      setState(() {
        _products = response.products;
        _pagination = response.pagination;
        _categoryInfo = response.category;

        _currentPage = page;
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      _showError('Failed to load products: $e');
    }
  }

  // Navigate to category from banner
  void _navigateToCategoryFromBanner(ProductsBanner banner) {
    final categorySlug = banner.categorySlug;
    print('Navigating to category: $categorySlug');
    if (categorySlug != null) {
      // If it's the featured category, load featured products
      if (categorySlug == 'featured') {
        _loadFeaturedProducts();
      } else {
        _loadProductsByCategory(categorySlug);
      }
    }
  }

  // Handle category pill click
  void _handleCategoryClick(String categorySlug) {
    if (categorySlug == 'featured') {
      // If already on featured, don't reload
      if (_selectedCategory == 'featured' && !_isLoadingProducts) {
        return;
      }
      _loadFeaturedProducts();
    } else {
      _loadProductsByCategory(categorySlug);
    }
  }

  // Show color and size picker
  void _showQuickAddModal(Product product) {
    ProductColour? selectedColour;
    String? selectedSize;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product info
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      product.image,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        PriceDisplay(
                          product: product,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFAE9159),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Color selection
              if (product.colours.isNotEmpty) ...[
                const Text(
                  'Select Color',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: product.colours.map((colour) {
                    final isSelected = selectedColour?.hex == colour.hex;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedColour = colour),
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
                                color: isSelected
                                    ? const Color(0xFFAE9159)
                                    : Colors.grey.shade300,
                                width: isSelected ? 3 : 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            colour.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Size selection
              if (product.sizes.isNotEmpty) ...[
                const Text(
                  'Select Size',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: product.sizes.map((size) {
                    final isSelected = selectedSize == size;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedSize = size),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFAE9159)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFAE9159)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          size.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Add to basket button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (selectedColour != null &&
                          (product.sizes.isEmpty || selectedSize != null))
                      ? () {
                          Navigator.pop(context);
                          _addToCart(
                            product,
                            selectedColour: selectedColour,
                            selectedSize: selectedSize,
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text(
                    'Add to Basket',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Add to cart
  void _addToCart(
    Product product, {
    ProductColour? selectedColour,
    String? selectedSize,
  }) {
    final cartProvider = context.read<CartProvider>();

    cartProvider.addToCart(
      productId: product.id.toString(),
      name: product.name,
      price: product.effectivePrice,
      isOnSale: product.isOnSale,
      originalPrice: product.price,
      currencySymbol: product.currencySymbol,
      image: product.image,
      variant: product.variant,
      selectedColorHex: selectedColour?.hex,
      selectedColorName: selectedColour?.name,
      selectedSize: selectedSize,
      supplierSku: selectedColour?.sku,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to basket'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'VIEW',
          onPressed: () => _mainTabController.animateTo(1),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Main tabs
          Consumer<CartProvider>(
            builder: (context, cartProvider, child) => Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: TabBar(
                controller: _mainTabController,
                labelColor: const Color(0xFFAE9159),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFFAE9159),
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 20),
                        const SizedBox(width: 6),
                        const Text('Browse'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_basket_outlined, size: 20),
                        const SizedBox(width: 6),
                        Text('Basket (${cartProvider.itemCount})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 20),
                        const SizedBox(width: 6),
                        const Text('My Orders'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: TabBarView(
              controller: _mainTabController,
              children: [
                _buildBrowseTab(theme),
                _buildBasketTab(),
                MyOrdersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasketTab() {
    return Consumer<CartProvider>(
      builder: (context, cartProvider, child) {
        if (cartProvider.cart.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_basket_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your basket is empty',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _mainTabController.animateTo(0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAE9159),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Continue Shopping',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basket Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: const Text(
                  'Basket',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),

              Divider(height: 1, color: Colors.grey.shade300),

              // Product Section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRODUCT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Product items
                    ...cartProvider.cart.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product image
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.image,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Product details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  if (item.selectedSize != null)
                                    Text(
                                      'Size: ${item.selectedSize}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),

                                  if (item.selectedColorName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Colour: ${item.selectedColorName}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 12),

                                  PriceDisplay(
                                    product: Product(
                                      id: 0,
                                      name: item.name,
                                      permalink: '',
                                      image: item.image,
                                      price:
                                          item.isOnSale == true &&
                                              item.originalPrice != null
                                          ? item.originalPrice!
                                          : item.price,
                                      formattedSalePrice: item.isOnSale == true
                                          ? '${item.currencySymbol}${item.price.toStringAsFixed(2)}'
                                          : null,
                                      formattedPrice:
                                          '${item.currencySymbol}${item.price.toStringAsFixed(2)}',
                                      salePrice: item.isOnSale == true
                                          ? item.price
                                          : null,
                                      isOnSale: item.isOnSale ?? false,
                                      currencySymbol: item.currencySymbol,
                                      inStock: true,
                                      stockStatus: 'instock',
                                      colours: [],
                                      sizes: [],
                                    ),
                                    // fontSize: 20,
                                    showSavings: true,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFAE9159),
                                  ),
                                  const SizedBox(height: 12),

                                  Row(
                                    spacing: 10,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4, // Reduced from 8 to 4
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: DropdownButton<int>(
                                          value: item.quantity,
                                          underline: const SizedBox(),
                                          isDense:
                                              true, // ADD THIS - makes dropdown more compact
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 18, // Reduced from 20 to 18
                                          ),
                                          style: const TextStyle(
                                            fontSize:
                                                14, // ADD THIS - smaller text
                                            color: Colors.black,
                                          ),
                                          items: List.generate(
                                            10,
                                            (index) => DropdownMenuItem(
                                              value: index + 1,
                                              child: Text('${index + 1}'),
                                            ),
                                          ),
                                          onChanged: (value) {
                                            if (value != null) {
                                              // Update quantity
                                              final diff =
                                                  value - item.quantity;
                                              if (diff > 0) {
                                                for (int i = 0; i < diff; i++) {
                                                  cartProvider
                                                      .incrementQuantity(
                                                        item.variantId,
                                                      );
                                                }
                                              } else if (diff < 0) {
                                                for (
                                                  int i = 0;
                                                  i < -diff;
                                                  i++
                                                ) {
                                                  cartProvider
                                                      .decrementQuantity(
                                                        item.variantId,
                                                      );
                                                }
                                              }
                                            }
                                          },
                                        ),
                                      ),

                                      // Remove item
                                      GestureDetector(
                                        onTap: () => cartProvider
                                            .removeFromCart(item.variantId),
                                        child: Text(
                                          'Remove Item',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: Colors.grey.shade300),

              // Basket Totals
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BASKET TOTALS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Add Coupon
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ExpansionTile(
                        title: const Text(
                          'Add Coupon',
                          style: TextStyle(fontSize: 14),
                        ),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Enter coupon code',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      // Apply coupon
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'Apply',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Sub Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Sub Total:',
                          style: TextStyle(fontSize: 14),
                        ),
                        Text(
                          '£${cartProvider.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Shipping
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Shipping: 5-10 days',
                          style: TextStyle(fontSize: 14),
                        ),
                        Text(
                          '£${(cartProvider.subtotal * 0.12).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Estimated Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Estimated Total',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '£${(cartProvider.subtotal * 1.12).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Proceed to Checkout
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // Navigator.pushNamed(context, '/checkout');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const HybridCheckoutScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Proceed to Checkout',
                          style: TextStyle(
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildBrowseTab(ThemeProvider theme) {
    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: () async {
        if (_selectedCategory == 'featured') {
          await _loadFeaturedProducts();
        } else if (_selectedCategory != null) {
          await _loadProductsByCategory(_selectedCategory!);
        } else {
          await _loadFeaturedProducts();
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Banner carousel
            if (_isLoadingBanners)
              _buildBannerSkeleton()
            else if (_banners.isNotEmpty &&
                _categoryInfo == null &&
                _selectedCategory == 'featured' &&
                !_isLoadingProducts)
              _buildBannerCarousel(),

            // // Category Pills (only show when not in a specific category or when on featured)
            // if ((_categoryInfo == null && _selectedCategory == 'featured') ||
            //     (_selectedCategory == 'featured' && !_isLoadingProducts))
            _buildCategoryPills(),

            // Category info with sort and filter dropdowns
            if (_categoryInfo != null && !_isLoadingProducts) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed: _loadFeaturedProducts,
                        ),
                        Expanded(
                          child: Text(
                            _categoryInfo!.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_categoryInfo!.description.isNotEmpty) ...[
                      Text(
                        _categoryInfo!.description,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Sort and Filter dropdowns
                    Row(
                      children: [
                        // Sort By dropdown
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButton<String>(
                              value: _sortBy,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'popularity',
                                  child: Text('Sort: Popularity'),
                                ),
                                DropdownMenuItem(
                                  value: 'price',
                                  child: Text('Sort: Price'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _sortBy = value);
                                  // TODO: Implement sort logic
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Filter By dropdown
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButton<String>(
                              value: _filterBy,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('Filter: All'),
                                ),
                                DropdownMenuItem(
                                  value: 'men',
                                  child: Text('Filter: Men'),
                                ),
                                DropdownMenuItem(
                                  value: 'women',
                                  child: Text('Filter: Women'),
                                ),
                                DropdownMenuItem(
                                  value: 'unisex',
                                  child: Text('Filter: Unisex'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _filterBy = value);
                                  // TODO: Implement filter logic
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Products grid
            if (_isLoadingProducts)
              _buildProductsSkeleton()
            else if (_products.isEmpty)
              const SizedBox(
                height: 400,
                child: Center(child: Text('No products found')),
              )
            else
              _buildProductsGrid(),

            // Pagination - only show if pagination exists and has multiple pages
            if (_pagination != null &&
                _pagination!.totalPages > 1 &&
                !_isLoadingProducts)
              _buildPagination(),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPills() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _categories.map((category) {
            // Fixed: Check if this category matches the selected category
            final isSelected = _selectedCategory == category['slug'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _handleCategoryClick(category['slug']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFAE9159)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    category['name']!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBannerCarousel() {
    return Container(
      height: 250,
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          PageView.builder(
            itemCount: _banners.length,
            onPageChanged: (index) =>
                setState(() => _currentBannerIndex = index),
            itemBuilder: (context, index) {
              final banner = _banners[index];
              return GestureDetector(
                onTap: () => _navigateToCategoryFromBanner(banner),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: DecorationImage(
                      image: NetworkImage(banner.backgroundImage),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!banner.hideText) ...[
                            Text(
                              banner.subtitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              banner.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            OutlinedButton(
                              onPressed: () =>
                                  _navigateToCategoryFromBanner(banner),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                banner.linkTitle.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _banners.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentBannerIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Skeleton loaders
  Widget _buildBannerSkeleton() {
    return Container(
      height: 250,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: CircularProgressIndicator(color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildProductsSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.65,
          crossAxisSpacing: 16,
          mainAxisSpacing: 24,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade200,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 16,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 16,
              width: 100,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.65,
          crossAxisSpacing: 16,
          mainAxisSpacing: 24,
        ),
        itemCount: _products.length,
        itemBuilder: (context, index) => _buildProductCard(_products[index]),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(productId: product.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade100,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      product.image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
                if (!product.inStock)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: const Center(
                      child: Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFAE9159),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: product.inStock
                          ? () => _showQuickAddModal(product)
                          : null,
                      icon: const Icon(Icons.add_shopping_cart),
                      color: Colors.white,
                      iconSize: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Show color swatches using colorHexes helper
          if (product.colorHexes.isNotEmpty)
            Row(
              children: product.colorHexes.take(6).map((colorHex) {
                return Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Color(int.parse(colorHex.replaceFirst('#', '0xFF'))),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          PriceDisplay(
            product: product,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFAE9159),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _pagination!.hasPreviousPage
                ? () => _loadProductsByCategory(
                    _selectedCategory!,
                    page: _currentPage - 1,
                  )
                : null,
          ),
          Text(
            'Page ${_pagination!.currentPage} of ${_pagination!.totalPages}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _pagination!.hasNextPage
                ? () => _loadProductsByCategory(
                    _selectedCategory!,
                    page: _currentPage + 1,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class PriceDisplay extends StatelessWidget {
  final Product product;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final bool? showSavings;

  const PriceDisplay({
    super.key,
    required this.product,
    this.fontSize = 16,
    this.fontWeight = FontWeight.bold,
    this.color,
    this.showSavings = false,
  });

  @override
  Widget build(BuildContext context) {
    if (product.isOnSale && product.formattedSalePrice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Price row
          Row(
            children: [
              // Sale price
              Text(
                decodeHtmlPrice(product.formattedSalePrice!),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: color ?? const Color(0xFFAE9159),
                ),
              ),
              const SizedBox(width: 8),
              // Regular price (strikethrough)
              Text(
                decodeHtmlPrice(product.formattedPrice),
                style: TextStyle(
                  fontSize: fontSize! * 0.85,
                  fontWeight: FontWeight.normal,
                  color: Colors.grey,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ],
          ),

          // Savings info (below price)
          if (showSavings == true) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Save ${_calculateSavings()}',
                style: TextStyle(
                  fontSize: fontSize! * 0.7,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
            ),
          ],
        ],
      );
    }

    // Regular price only
    return Text(
      decodeHtmlPrice(product.formattedPrice),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }

  String _calculateSavings() {
    if (product.salePrice != null) {
      final savings = product.price - product.salePrice!;
      return decodeHtmlPrice(
        '${product.currencySymbol}${savings.toStringAsFixed(2)}',
      );
    }
    return '';
  }

  String decodeHtmlPrice(String htmlPrice) {
    final unescape = HtmlUnescape();
    return unescape
        .convert(htmlPrice)
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .trim();
  }
}
