import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/events/order_ticket_view.dart';
import 'package:flutter/material.dart';

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final ThemeProvider theme;

  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? theme.primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? Colors.white : Colors.grey[400],
        ),
      ),
    );
  }
}

class OrdersSection extends StatefulWidget {
  final List<dynamic> orders;
  final ThemeProvider theme;

  const OrdersSection({super.key, required this.orders, required this.theme});

  @override
  State<OrdersSection> createState() => OrdersSectionState();
}

class OrdersSectionState extends State<OrdersSection> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _currentPage = 1;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // REPLACE your existing _filtered getter with this
  List<dynamic> get _filtered {
    if (_query.isEmpty) return widget.orders;
    final q = _query.toLowerCase();
    return widget.orders.where((o) {
      final id = o['order_id']?.toString().toLowerCase() ?? '';
      final buyer = (o['buyer'] ?? '').toString().toLowerCase();
      final email = (o['email'] ?? '').toString().toLowerCase();
      return id.contains(q) || buyer.contains(q) || email.contains(q);
    }).toList();
  }

  // ADD this new getter below it
  List<dynamic> get _pagedOrders {
    final all = _filtered;
    final start = (_currentPage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  Widget _buildPagination(int totalCount) {
    final totalPages = (totalCount / _pageSize).ceil();
    final start = (_currentPage - 1) * _pageSize + 1;
    final end = (_currentPage * _pageSize).clamp(0, totalCount);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$start–$end of $totalCount',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          Row(
            children: [
              _PageButton(
                icon: Icons.chevron_left,
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
                theme: widget.theme,
              ),
              const SizedBox(width: 6),
              Text(
                '$_currentPage / $totalPages',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              _PageButton(
                icon: Icons.chevron_right,
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
                theme: widget.theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Orders',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.orders.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Search bar
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() {
                _query = v.trim();
                _currentPage = 1; // reset to first page on new search
              }),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by order ID, name or email…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Colors.grey[400],
                ),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: widget.theme.primaryColor,
                    width: 1.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // No results
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No orders yet'
                        : 'No orders match "$_query"',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ..._pagedOrders.map(
                (order) => _OrderCard(order: order, theme: widget.theme),
              ),
            if (_filtered.isNotEmpty) _buildPagination(_filtered.length),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final dynamic order;
  final ThemeProvider theme;

  const _OrderCard({required this.order, required this.theme});

  @override
  Widget build(BuildContext context) {
    final cars = (order['car'] as List?) ?? [];
    final hasCars = cars.isNotEmpty;
    final marketing = order['marketing']?.toString() ?? '-';
    final source = order['source']?.toString() ?? '';
    final total = order['total'];
    final quantity = order['quantity']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          // Top bar — order ID + view button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 15,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Order #${order['order_id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderTicketsPage(
                          orderId: order['order_id'].toString(),
                          admin: true,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                // Buyer + email
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Buyer',
                  value: order['buyer']?.toString().trim() ?? '-',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: order['email'] ?? '-',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Tel',
                  value: order['tel_no'] ?? '-',
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),

                // Quantity + total in a 2-col grid
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: 'Qty',
                        value: quantity,
                        icon: Icons.confirmation_number_outlined,
                        color: theme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        label: 'Total',
                        value: '£${total ?? '0.00'}',
                        icon: Icons.payments_outlined,
                        color: Colors.green[600]!,
                      ),
                    ),
                  ],
                ),

                // Cars (if any)
                if (hasCars) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.directions_car_outlined,
                    label: 'Cars',
                    value: cars.join(', '),
                  ),
                ],

                // const Padding(
                //   padding: EdgeInsets.symmetric(vertical: 10),
                //   child: Divider(height: 1),
                // ),

                // Marketing + source
                // Row(
                //   children: [
                //     Expanded(
                //       child: _InfoRow(
                //         icon: Icons.campaign_outlined,
                //         label: 'Marketing',
                //         value: marketing,
                //         valueColor: marketing == 'Yes'
                //             ? Colors.green[600]
                //             : null,
                //       ),
                //     ),
                //     if (source.isNotEmpty) ...[
                //       const SizedBox(width: 8),
                //       Expanded(
                //         child: _InfoRow(
                //           icon: Icons.link_outlined,
                //           label: 'Source',
                //           value: source,
                //         ),
                //       ),
                //     ],
                //   ],
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.grey[500]),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: color.withOpacity(0.7)),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
