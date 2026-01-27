import 'package:drivelife/providers/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;
  int _currentBannerIndex = 0;
  String _selectedCategory = 'Popular';
  String _selectedGender = 'Men';
  String _selectedSort = 'Popularity';
  bool _isHomePage = true;

  final List<Map<String, String>> _banners = [
    {
      'title': 'Cars & Coffee Collection',
      'subtitle': 'NEW IN',
      'image': 'assets/banner1.jpg',
    },
    {
      'title': 'Summer Racing Collection',
      'subtitle': 'TRENDING',
      'image': 'assets/banner2.jpg',
    },
    {
      'title': 'Classic Car Merch',
      'subtitle': 'BEST SELLERS',
      'image': 'assets/banner3.jpg',
    },
  ];

  final List<String> _categories = [
    'Popular',
    'New',
    'Men',
    'Women',
    'Brands',
    'Sale',
  ];

  final List<Map<String, dynamic>> _products = [
    {
      'id': '1',
      'name': 'Premium Oversized Sunday Drivers Club Hoodie',
      'price': 50.00,
      'image':
          'https://www.drive-life.com/wp-content/uploads/2025/10/Mock-Up-2-2.png',
      'colors': ['#000000', '#CCCCCC', '#8B4513'],
    },
    {
      'id': '2',
      'name': 'Out-Brake Relaxed Fit Hoodie',
      'price': 45.00,
      'image':
          'https://www.drive-life.com/wp-content/uploads/2025/10/Mock-Up-2-2.png',
      'colors': [
        '#000000',
        '#CCCCCC',
        '#000080',
        '#D4C5A0',
        '#87CEEB',
        '#696969',
      ],
    },
    {
      'id': '3',
      'name': 'DriveLife Logo T-Shirt',
      'price': 25.00,
      'image':
          'https://www.drive-life.com/wp-content/uploads/2025/10/Mock-Up-2-2.png',
      'colors': ['#000000', '#FFFFFF', '#FF0000'],
    },
    {
      'id': '4',
      'name': 'Racing Stripes Crew Neck',
      'price': 55.00,
      'image':
          'https://www.drive-life.com/wp-content/uploads/2025/10/Mock-Up-2-2.png',
      'colors': ['#8B0000', '#000000', '#FFFFFF'],
    },
    {
      'id': '5',
      'name': 'Vintage Car Club Cap',
      'price': 20.00,
      'image':
          'https://www.drive-life.com/wp-content/uploads/2025/10/Mock-Up-2-2.png',
      'colors': ['#000080', '#8B4513', '#000000'],
    },
    {
      'id': '6',
      'name': 'Weekend Cruiser Jacket',
      'price': 75.00,
      'image':
          'https://www.drive-life.com/wp-content/uploads/2025/10/Mock-Up-2-2.png',
      'colors': ['#2F4F4F', '#000000', '#696969'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);
    // Load cart when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().loadCart();
    });
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  void _navigateToCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _isHomePage = false;
    });
  }

  void _backToHome() {
    setState(() {
      _isHomePage = true;
    });
  }

  void _addToCart(Map<String, dynamic> product, {String? selectedColor}) {
    final cartProvider = context.read<CartProvider>();

    cartProvider.addToCart(
      variantId: '${product['id']}_${selectedColor ?? 'default'}',
      productId: product['id'],
      name: product['name'],
      price: product['price'],
      image: product['image'],
      selectedColor: selectedColor,
      quantity: 1,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']} added to basket'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'VIEW',
          onPressed: () {
            _mainTabController.animateTo(1);
          },
        ),
      ),
    );
  }

  void _showColorPicker(Map<String, dynamic> product) {
    final colors = product['colors'] as List<String>;

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
            Text(
              'Select Color',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: colors.map((colorHex) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _addToCart(product, selectedColor: colorHex);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse(colorHex.replaceFirst('#', '0xFF')),
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade400, width: 2),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

          // Main tabs (Browse, Basket, My Orders)
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
                  const Tab(
                    icon: Icon(Icons.shopping_bag_outlined, size: 20),
                    text: 'Browse',
                  ),
                  Tab(
                    icon: Icon(Icons.shopping_basket_outlined, size: 20),
                    text: 'Basket (${cartProvider.itemCount})',
                  ),
                  const Tab(
                    icon: Icon(Icons.receipt_long_outlined, size: 20),
                    text: 'My Orders',
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
                // Browse Tab
                _buildBrowseTab(),

                // Basket Tab
                _buildBasketTab(),

                // My Orders Tab
                const Center(child: Text('My Orders Content')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          if (_isHomePage) ...[
            // Banner carousel
            _buildBannerCarousel(),

            // Category chips
            _buildCategoryChips(),
          ] else ...[
            // Filter dropdowns for category page
            _buildFilters(),
          ],

          // Products grid
          _buildProductsGrid(),
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

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: cartProvider.cart.length,
                itemBuilder: (context, index) {
                  final item = cartProvider.cart[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              item.image,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Product details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                if (item.selectedColor != null)
                                  Row(
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: Color(
                                            int.parse(
                                              item.selectedColor!.replaceFirst(
                                                '#',
                                                '0xFF',
                                              ),
                                            ),
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Color selected',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  '£${item.price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Quantity controls
                          Column(
                            children: [
                              IconButton(
                                onPressed: () => cartProvider.removeFromCart(
                                  item.variantId,
                                  selectedColor: item.selectedColor,
                                ),
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                                iconSize: 20,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          cartProvider.decrementQuantity(
                                            item.variantId,
                                            selectedColor: item.selectedColor,
                                          ),
                                      icon: const Icon(Icons.remove),
                                      iconSize: 16,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          cartProvider.incrementQuantity(
                                            item.variantId,
                                            selectedColor: item.selectedColor,
                                          ),
                                      icon: const Icon(Icons.add),
                                      iconSize: 16,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Cart summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:'),
                      Text(
                        '£${cartProvider.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tax (20%):'),
                      Text(
                        '£${cartProvider.tax.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '£${cartProvider.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFAE9159),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Proceed to checkout
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFAE9159),
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
        );
      },
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
            onPageChanged: (index) {
              setState(() => _currentBannerIndex = index);
            },
            itemBuilder: (context, index) {
              final banner = _banners[index];
              return GestureDetector(
                onTap: () => _navigateToCategory('Men'),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background pattern (simplified)
                      Opacity(
                        opacity: 0.2,
                        child: Icon(
                          Icons.coffee_outlined,
                          size: 200,
                          color: Colors.white,
                        ),
                      ),
                      // Content
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            banner['subtitle']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            banner['title']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton(
                            onPressed: () => _navigateToCategory('Men'),
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
                            child: const Text(
                              'SHOP NOW',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Page indicators
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

  Widget _buildCategoryChips() {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = category;
                });
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: const Color(0xFFAE9159),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Gender filter
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButton<String>(
                value: _selectedGender,
                isExpanded: true,
                underline: const SizedBox(),
                items: ['Men', 'Women', 'Unisex']
                    .map(
                      (gender) =>
                          DropdownMenuItem(value: gender, child: Text(gender)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedGender = value!);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sort filter
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButton<String>(
                value: _selectedSort,
                isExpanded: true,
                underline: const SizedBox(),
                items:
                    [
                          'Popularity',
                          'Price: Low to High',
                          'Price: High to Low',
                          'Newest',
                        ]
                        .map(
                          (sort) => DropdownMenuItem(
                            value: sort,
                            child: Text(
                              'Sort: $sort',
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  setState(() => _selectedSort = value!);
                },
              ),
            ),
          ),
        ],
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
        itemBuilder: (context, index) {
          final product = _products[index];
          return _buildProductCard(product);
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    return GestureDetector(
      onTap: () {
        _showColorPicker(product);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
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
                      product['image'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
                // Add to cart button
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
                      onPressed: () => _showColorPicker(product),
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

          // Color swatches
          Row(
            children: (product['colors'] as List<String>)
                .take(6)
                .map(
                  (colorHex) => Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse(colorHex.replaceFirst('#', '0xFF')),
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Product name
          Text(
            product['name'],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          // Price
          Text(
            '£${product['price'].toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
