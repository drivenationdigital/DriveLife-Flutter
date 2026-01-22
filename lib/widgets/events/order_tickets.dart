import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Modern loading shimmer effect for tickets
class TicketLoadingShimmer extends StatelessWidget {
  const TicketLoadingShimmer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Download button shimmer
        _buildShimmerBox(height: 50, radius: 12),
        const SizedBox(height: 20),
        // Ticket cards shimmer
        ...[1, 2].map(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildTicketCardShimmer(),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerBox({required double height, double? radius}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius ?? 8),
        ),
      ),
    );
  }

  Widget _buildTicketCardShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 20, width: 150, color: Colors.white),
            const SizedBox(height: 12),
            Container(height: 16, width: double.infinity, color: Colors.white),
            const SizedBox(height: 8),
            Container(height: 16, width: 200, color: Colors.white),
            const SizedBox(height: 20),
            Container(height: 200, width: double.infinity, color: Colors.white),
            const SizedBox(height: 16),
            Container(height: 44, width: double.infinity, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Error state with retry option
class TicketErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const TicketErrorState({
    Key? key,
    required this.message,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red.shade300),
            const SizedBox(height: 20),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB9965A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Download all tickets button
class DownloadAllButton extends StatelessWidget {
  final VoidCallback onPressed;

  const DownloadAllButton({Key? key, required this.onPressed})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB9965A), Color(0xFFD4AF6A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB9965A).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.download_rounded, size: 22),
        label: const Text(
          'Download All Tickets',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Individual ticket card with modern design
class TicketDetailsCard extends StatelessWidget {
  final String ticketLabel;
  final String productTitle;
  final String eventDate;
  final String eventTime;
  final String orderId;
  final String transactionId;
  final String priceText;
  final Uint8List? qrCode;
  final VoidCallback? onDownload;

  const TicketDetailsCard({
    Key? key,
    required this.ticketLabel,
    required this.productTitle,
    required this.eventDate,
    required this.eventTime,
    required this.orderId,
    required this.transactionId,
    required this.priceText,
    this.qrCode,
    this.onDownload,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFB9965A).withOpacity(0.1),
                  const Color(0xFFD4AF6A).withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB9965A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.confirmation_number_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticketLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB9965A),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        productTitle.isNotEmpty ? productTitle : 'Event Ticket',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event details
                if (eventDate.isNotEmpty) ...[
                  _buildInfoRow(
                    Icons.calendar_today_rounded,
                    'Event Date',
                    eventDate,
                  ),
                  const SizedBox(height: 10),
                ],
                if (eventTime.isNotEmpty) ...[
                  _buildInfoRow(
                    Icons.access_time_rounded,
                    'Event Time',
                    eventTime,
                  ),
                  const SizedBox(height: 16),
                ],

                Divider(color: Colors.grey.shade200, thickness: 1),
                const SizedBox(height: 16),

                // Order details
                _buildDetailRow(
                  'Quantity',
                  '1 x ${productTitle.isNotEmpty ? productTitle : 'Event Ticket'}',
                ),
                const SizedBox(height: 8),
                _buildDetailRow('Order ID', '#$orderId'),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Transaction',
                  transactionId.isNotEmpty ? '#$transactionId' : '—',
                ),

                const SizedBox(height: 16),

                // Price
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB9965A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ticket Price',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        priceText,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB9965A),
                        ),
                      ),
                    ],
                  ),
                ),

                // QR Code
                if (qrCode != null) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Image.memory(
                            qrCode!,
                            width: 200,
                            height: 200,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Scan at venue',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Download button
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text(
                      'Download Ticket',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB9965A),
                      side: const BorderSide(
                        color: Color(0xFFB9965A),
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFB9965A)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

/// Totals summary card
class OrderTotalsCard extends StatelessWidget {
  final List<Map<String, dynamic>> totals;

  const OrderTotalsCard({Key? key, required this.totals}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.grey.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Order Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          ...totals.asMap().entries.map((entry) {
            final index = entry.key;
            final t = entry.value;
            final label = (t['label'] ?? '').toString();
            final value = (t['value'] ?? '').toString();
            final isLast = index == totals.length - 1;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w600,
                      color: isLast ? Colors.black : Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: isLast ? 18 : 15,
                      fontWeight: FontWeight.w800,
                      color: isLast ? const Color(0xFFB9965A) : Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
