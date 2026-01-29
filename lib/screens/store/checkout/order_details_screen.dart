import 'package:drivelife/api/orders_api_services.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class OrderDetailsScreen extends StatefulWidget {
  final int orderId;
  final int? userId;

  const OrderDetailsScreen({super.key, required this.orderId, this.userId});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  Map<String, dynamic>? _order;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await OrderApiService.getOrderById(
        orderId: widget.orderId,
        userId: widget.userId,
      );

      if (result['success'] == true) {
        setState(() {
          _order = result['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load order';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading order: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _order != null
              ? 'Order #${_order!['order_number']}'
              : 'Order Details',
          style: const TextStyle(color: Colors.black, fontSize: 16),
        ),
      ),
      body: _isLoading
          ? _buildShimmerLoading()
          : _errorMessage != null
          ? _buildErrorState()
          : _buildOrderDetails(),
    );
  }

  Widget _buildOrderDetails() {
    return RefreshIndicator(
      onRefresh: _loadOrder,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderHeader(),
            const SizedBox(height: 24),
            _buildOrderItems(),
            const SizedBox(height: 24),
            _buildShippingInfo(),
            const SizedBox(height: 24),
            _buildBillingInfo(),
            const SizedBox(height: 24),
            _buildPriceBreakdown(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeader() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Number',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '#${_order!['order_number']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(_order!['status']),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildInfoRow('Date', _formatDate(_order!['date_created'])),
            const SizedBox(height: 8),
            _buildInfoRow('Payment', _order!['payment_method'] ?? 'N/A'),
            if (_order!['order_key'] != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow('Order Key', _order!['order_key']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildOrderItems() {
    final items = _order!['items'] as List? ?? [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...items.map((item) => _buildOrderItem(item)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item) {
    final metaData = item['meta_data'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item['image'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item['image'],
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.image, color: Colors.grey.shade400),
                  );
                },
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'Unknown Product',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quantity: ${item['quantity'] ?? 1}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if (metaData['variant'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Variant: ${metaData['variant']}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
                if (metaData['size'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Size: ${metaData['size']}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
                if (metaData['color'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Color: ${metaData['color']}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${_order!['currency'] ?? '£'}${_formatPrice(item['total'])}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildShippingInfo() {
    final shipping = _order!['shipping'];
    final shippingAddress = _order!['shipping_address'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shipping',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (shipping != null) ...[
              Text(
                shipping['method'] ?? 'Standard Shipping',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                '${_order!['currency'] ?? '£'}${_formatPrice(shipping['total'])}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
            ],
            if (shippingAddress != null) ...[
              Text(
                '${shippingAddress['first_name']} ${shippingAddress['last_name']}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(shippingAddress['address_1'] ?? ''),
              if (shippingAddress['address_2']?.isNotEmpty ?? false)
                Text(shippingAddress['address_2']),
              Text(
                '${shippingAddress['city']}, ${shippingAddress['state']} ${shippingAddress['postcode']}',
              ),
              Text(shippingAddress['country'] ?? ''),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBillingInfo() {
    final billing = _order!['billing'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Billing Address',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '${billing['first_name']} ${billing['last_name']}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(billing['address_1'] ?? ''),
            if (billing['address_2']?.isNotEmpty ?? false)
              Text(billing['address_2']),
            Text(
              '${billing['city']}, ${billing['state']} ${billing['postcode']}',
            ),
            Text(billing['country'] ?? ''),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (billing['email']?.isNotEmpty ?? false)
              Text('Email: ${billing['email']}'),
            if (billing['phone']?.isNotEmpty ?? false)
              Text('Phone: ${billing['phone']}'),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildPriceRow('Subtotal', _order!['subtotal']),
            _buildPriceRow('Shipping', _order!['shipping_total']),
            if (double.parse(_order!['tax_total'].toString()) > 0)
              _buildPriceRow('Tax', _order!['tax_total']),
            if (double.parse(_order!['discount_total'].toString()) > 0)
              _buildPriceRow('Discount', '-${_order!['discount_total']}'),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _buildPriceRow('Total', _order!['total'], isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, dynamic amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
          Text(
            '${_order!['currency'] ?? '£'}${_formatPrice(amount)}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color backgroundColor;
    Color textColor;

    switch (status?.toLowerCase()) {
      case 'completed':
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        break;
      case 'processing':
        backgroundColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        break;
      case 'pending':
        backgroundColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        break;
      case 'cancelled':
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        break;
      default:
        backgroundColor = Colors.grey.shade200;
        textColor = Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        (status ?? 'Unknown').toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            4,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(_errorMessage ?? 'Failed to load order'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadOrder, child: const Text('Retry')),
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }
}
