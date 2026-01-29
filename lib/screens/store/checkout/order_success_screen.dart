import 'package:drivelife/api/orders_api_services.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

class OrderSuccessScreen extends StatefulWidget {
  final Map<String, dynamic>? orderData;

  const OrderSuccessScreen({super.key, this.orderData});

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  // Immediate data from order creation
  Map<String, dynamic>? _initialOrderData;

  // Full order details from API
  Map<String, dynamic>? _fullOrderDetails;

  bool _isLoadingDetails = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialOrderData = widget.orderData;
    print('Initial Order Data: $_initialOrderData');
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    if (_initialOrderData == null || _initialOrderData!['orderId'] == null) {
      setState(() {
        _errorMessage = 'Order information not available';
        _isLoadingDetails = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoadingDetails = true;
        _errorMessage = null;
      });
      // Get the app order ID from the initial data
      // Note: Adjust this based on your actual response structure
      final orderId = _initialOrderData!['orderId'];

      final result = await OrderApiService.getOrderById(
        orderId: orderId,
        // userId: yourUserId, // Add if you have user authentication
      );

      if (result['success'] == true) {
        setState(() {
          _fullOrderDetails = result['data'];
          _isLoadingDetails = false;
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load order details';
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      print('Error loading order details: $e');
      setState(() {
        _errorMessage = 'Error loading order details';
        _isLoadingDetails = false;
      });
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
        centerTitle: true,
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.search);
            },
          ),
          ...SharedHeaderIcons.actionIcons(
            iconColor: Colors.black,
            showQr: false,
            showNotifications: true,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Success icon
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: theme.primaryColor,
                    size: 50,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Order received heading
              const Center(
                child: Text(
                  'Order received',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),

              // Thank you message
              const Center(
                child: Text(
                  'Thank you. Your order has been received.',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              // Order info grid - shows immediately
              _buildInfoItem(
                'ORDER NUMBER',
                _initialOrderData?['orderNumber']?.toString() ??
                    _initialOrderData?['orderId']?.toString() ??
                    'N/A',
              ),
              const SizedBox(height: 16),
              _buildInfoItem('DATE:', _formatDate(DateTime.now())),
              const SizedBox(height: 16),
              _buildInfoItem(
                'TOTAL:',
                '£${_formatPrice(_initialOrderData?['total'])}',
              ),
              const SizedBox(height: 16),
              _buildInfoItem('PAYMENT METHOD:', 'Card (Stripe)'),

              const SizedBox(height: 40),

              // Order details heading
              const Text(
                'Order details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Order details container
              _buildOrderDetailsContainer(),

              const SizedBox(height: 24),

              // Action buttons
              if (_fullOrderDetails != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: BorderSide(color: Colors.grey.shade300),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text(
                      'Continue shopping',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderDetailsContainer() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Product',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Products - shimmer while loading, actual data when loaded
          if (_isLoadingDetails)
            ..._buildShimmerItems()
          else if (_errorMessage != null)
            _buildErrorState()
          else if (_fullOrderDetails != null)
            ..._buildOrderItems(),

          // Subtotal
          _buildSummaryRow(
            'Subtotal:',
            _isLoadingDetails
                ? _buildShimmerText(width: 60)
                : '£${_formatPrice(_fullOrderDetails?['subtotal'])}',
          ),

          // Shipping
          _buildShippingRow(),

          // Payment method
          _buildSummaryRow('Payment method:', 'Card (Stripe)'),

          // Total
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '£${_formatPrice(_initialOrderData?['total'])}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildShimmerItems() {
    return List.generate(2, (index) => _buildShimmerItem());
  }

  Widget _buildShimmerItem() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 60,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerText({required double width}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  List<Widget> _buildOrderItems() {
    final items = _fullOrderDetails?['items'] as List? ?? [];

    if (items.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(32),
          child: const Center(
            child: Text('No items found', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ];
    }

    return items.map<Widget>((item) => _buildOrderItem(item)).toList();
  }

  Widget _buildOrderItem(Map<String, dynamic> item) {
    final metaData = item['meta_data'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image (optional)
          if (item['image'] != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item['image'],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 60,
                    height: 60,
                    color: Colors.grey.shade200,
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.grey.shade400,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
          ],

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'Unknown Product',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '× ${item['quantity'] ?? 1}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),

                // Display metadata (color, size, variant)
                if (metaData['variant'] != null &&
                    metaData['variant'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Variant: ${metaData['variant']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                if (metaData['size'] != null &&
                    metaData['size'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Size: ${metaData['size']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                if (metaData['color'] != null &&
                    metaData['color'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Colour: ${metaData['color']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Text(
            '£${_formatPrice(item['total'])}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Failed to load order details',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: _loadOrderDetails, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildShippingRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shipping',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (_isLoadingDetails)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildShimmerText(width: 50),
                const SizedBox(height: 4),
                _buildShimmerText(width: 120),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '£${_formatPrice(_fullOrderDetails?['shipping_total'])}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_fullOrderDetails?['shipping']?['method'] != null)
                  Text(
                    _fullOrderDetails!['shipping']['method'],
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          value is Widget
              ? value
              : Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ],
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';

    if (price is String) {
      return double.tryParse(price)?.toStringAsFixed(2) ?? '0.00';
    }

    if (price is num) {
      return price.toStringAsFixed(2);
    }

    return '0.00';
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    String getDaySuffix(int day) {
      if (day >= 11 && day <= 13) {
        return 'th';
      }
      switch (day % 10) {
        case 1:
          return 'st';
        case 2:
          return 'nd';
        case 3:
          return 'rd';
        default:
          return 'th';
      }
    }

    return '${date.day}${getDaySuffix(date.day)} ${months[date.month - 1]} ${date.year}';
  }
}
