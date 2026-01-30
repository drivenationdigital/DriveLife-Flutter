import 'package:drivelife/api/orders_api_services.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

class MyOrdersTab extends StatefulWidget {
  const MyOrdersTab({super.key});

  @override
  State<MyOrdersTab> createState() => _MyOrdersTabState();
}

class _MyOrdersTabState extends State<MyOrdersTab> {
  // Orders data
  List<Map<String, dynamic>> _orders = [];

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalOrders = 0;
  final int _perPage = 10;
  late int? userId; // Replace with actual user ID retrieval

  // State management
  bool _isLoading = false;
  bool _isInitialLoad = true;
  String? _errorMessage;
  String? _selectedStatus;

  // Simple in-memory cache
  static final Map<String, CachedOrders> _ordersCache = {};

  @override
  void initState() {
    super.initState();
    userId = context.read<UserProvider>().user!.id;
    _loadOrders();
  }

  String _getCacheKey() {
    return 'user_${userId}_status_${_selectedStatus ?? 'all'}_page_$_currentPage';
  }

  Future<void> _loadOrders({bool forceRefresh = false}) async {
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please log in to view your orders';
        _isLoading = false;
        _isInitialLoad = false;
      });
      return;
    }

    // Check cache first
    final cacheKey = _getCacheKey();
    final cachedData = _ordersCache[cacheKey];

    if (!forceRefresh && cachedData != null && !cachedData.isExpired) {
      if (!mounted) return;
      setState(() {
        _orders = cachedData.orders;
        _totalPages = cachedData.totalPages;
        _totalOrders = cachedData.totalOrders;
        _isLoading = false;
        _isInitialLoad = false;
        _errorMessage = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await OrderApiService.getUserOrders(
        userId: userId!,
        page: _currentPage,
        perPage: _perPage,
        status: _selectedStatus,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final orders = List<Map<String, dynamic>>.from(result['data'] ?? []);
        final pagination = result['pagination'];

        // Cache the results
        _ordersCache[cacheKey] = CachedOrders(
          orders: orders,
          totalPages: pagination['total_pages'] ?? 1,
          totalOrders: pagination['total'] ?? 0,
          timestamp: DateTime.now(),
        );

        if (!mounted) return;
        setState(() {
          _orders = orders;
          _totalPages = pagination['total_pages'] ?? 1;
          _totalOrders = pagination['total'] ?? 0;
          _isLoading = false;
          _isInitialLoad = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load orders';
          _isLoading = false;
          _isInitialLoad = false;
        });
      }
    } catch (e) {
      print('Error loading orders: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading orders. Please try again.';
        _isLoading = false;
        _isInitialLoad = false;
      });
    }
  }

  void _changePage(int newPage) {
    if (newPage < 1 || newPage > _totalPages) return;

    setState(() {
      _currentPage = newPage;
    });

    _loadOrders();
  }

  void _filterByStatus(String? status) {
    setState(() {
      _selectedStatus = status;
      _currentPage = 1; // Reset to first page
    });

    _loadOrders();
  }

  void _clearCache() {
    _ordersCache.clear();
    _loadOrders(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _loadOrders(forceRefresh: true),
      child: Column(
        children: [
          // Filter chips
          _buildFilterChips(),

          // Content
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', null),
            const SizedBox(width: 8),
            _buildFilterChip('Processing', 'processing'),
            const SizedBox(width: 8),
            _buildFilterChip('Completed', 'completed'),
            const SizedBox(width: 8),
            _buildFilterChip('Cancelled', 'cancelled'),
            const SizedBox(width: 8),
            _buildFilterChip('Pending', 'pending'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String? status) {
    final isSelected = _selectedStatus == status;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        _filterByStatus(selected ? status : null);
      },
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFAE9159).withOpacity(0.2),
      checkmarkColor: const Color(0xFFAE9159),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFAE9159) : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFFAE9159) : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildContent() {
    if (_isInitialLoad && _isLoading) {
      return _buildShimmerLoading();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_orders.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Orders count
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_totalOrders ${_totalOrders == 1 ? 'Order' : 'Orders'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _clearCache,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFAE9159),
                ),
              ),
            ],
          ),
        ),

        // Orders list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _orders.length,
            itemBuilder: (context, index) {
              return _buildOrderCard(_orders[index]);
            },
          ),
        ),

        // Pagination
        if (_totalPages > 1) _buildPagination(),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final items = order['items'] as List? ?? [];
    final firstItem = items.isNotEmpty ? items[0] : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          // In my_orders_tab.dart, already set up:
          Navigator.pushNamed(
            context,
            AppRoutes.orderDetails,
            arguments: {'orderId': order['order_id'], 'userId': userId},
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${order['order_number']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(order['created_date']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(order['status']),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Order preview
              Row(
                children: [
                  // First item image
                  if (firstItem?['image'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        firstItem['image'],
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
                    )
                  else
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.grey.shade400,
                      ),
                    ),

                  const SizedBox(width: 12),

                  // Order details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order['payment_method'] ?? 'Card Payment',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${order['currency'] ?? '£'}${_formatPrice(order['total'])}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color backgroundColor;
    Color textColor;
    String displayStatus;

    switch (status?.toLowerCase()) {
      case 'completed':
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        displayStatus = 'Completed';
        break;
      case 'processing':
        backgroundColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        displayStatus = 'Processing';
        break;
      case 'pending':
        backgroundColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        displayStatus = 'Pending';
        break;
      case 'cancelled':
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        displayStatus = 'Cancelled';
        break;
      case 'refunded':
        backgroundColor = Colors.purple.shade50;
        textColor = Colors.purple.shade700;
        displayStatus = 'Refunded';
        break;
      case 'failed':
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        displayStatus = 'Failed';
        break;
      default:
        backgroundColor = Colors.grey.shade200;
        textColor = Colors.grey.shade700;
        displayStatus = status ?? 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayStatus.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final hasNextPage = _currentPage < _totalPages;
    final hasPreviousPage = _currentPage > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: hasPreviousPage
                ? () => _changePage(_currentPage - 1)
                : null,
            color: hasPreviousPage ? Colors.black : Colors.grey.shade300,
          ),
          const SizedBox(width: 16),
          Text(
            'Page $_currentPage of $_totalPages',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: hasNextPage ? () => _changePage(_currentPage + 1) : null,
            color: hasNextPage ? Colors.black : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedStatus != null
                ? 'No ${_selectedStatus} orders found'
                : 'Start shopping to see your orders here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          if (_selectedStatus != null)
            TextButton(
              onPressed: () => _filterByStatus(null),
              child: const Text('Clear filter'),
            )
          else
            ElevatedButton(
              onPressed: () {
                // Switch to browse tab
                DefaultTabController.of(context).animateTo(0);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAE9159),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              child: const Text('Start Shopping'),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Oops!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Something went wrong',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _loadOrders(forceRefresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAE9159),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown date';

    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
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
      }
    } catch (e) {
      return dateStr;
    }
  }
}

// Simple in-memory cache class
class CachedOrders {
  final List<Map<String, dynamic>> orders;
  final int totalPages;
  final int totalOrders;
  final DateTime timestamp;

  CachedOrders({
    required this.orders,
    required this.totalPages,
    required this.totalOrders,
    required this.timestamp,
  });

  // Cache expires after 5 minutes
  bool get isExpired {
    return DateTime.now().difference(timestamp).inMinutes > 5;
  }
}
