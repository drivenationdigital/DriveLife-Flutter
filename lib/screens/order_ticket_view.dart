import 'dart:convert';
import 'dart:typed_data';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/widgets/events/order_tickets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderTicketsPage extends StatefulWidget {
  /// Can be encrypted order id OR plain numeric id (must match your API)
  final String orderId;
  final bool admin;

  const OrderTicketsPage({
    super.key,
    required this.orderId,
    this.admin = false,
  });

  @override
  State<OrderTicketsPage> createState() => _OrderTicketsPageState();
}

class _OrderTicketsPageState extends State<OrderTicketsPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _header;
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _totals = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await EventsAPI.getOrderTickets(
        order: widget.orderId,
        admin: widget.admin,
      );

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _error = 'No response from server';
          _loading = false;
        });
        return;
      }

      if (res['success'] != true) {
        setState(() {
          _error = res['message']?.toString() ?? 'Failed to load tickets';
          _loading = false;
        });
        return;
      }

      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final header = (data['header'] as Map?)?.cast<String, dynamic>();
      final ticketsRaw = (data['tickets'] as List? ?? []);
      final totalsRaw = (data['totals'] as List? ?? []);

      setState(() {
        _header = header;
        _tickets = ticketsRaw
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _totals = totalsRaw
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final launchUri = uri.hasScheme ? uri : Uri.parse(url);

    if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication)) {
      await launchUrl(launchUri, mode: LaunchMode.inAppBrowserView);
    }
  }

  Uint8List? _decodeB64(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  String _formatEventDate(Map<String, dynamic>? dates) {
    if (dates == null) return '';
    final sd = (dates['start_date'] ?? '').toString();
    final ed = (dates['end_date'] ?? '').toString();
    if (sd.isEmpty) return '';
    if (ed.isEmpty || ed == sd) return _toDdMmYy(sd);
    return '${_toDdMmYy(sd)} - ${_toDdMmYy(ed)}';
  }

  String _formatEventTime(Map<String, dynamic>? dates) {
    if (dates == null) return '';
    final st = (dates['start_time'] ?? '').toString();
    final et = (dates['end_time'] ?? '').toString();
    if (st.isEmpty) return '';
    return et.isEmpty ? _toHhMm(st) : '${_toHhMm(st)} - ${_toHhMm(et)}';
  }

  String _toDdMmYy(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
    final yy = parts[0].substring(2);
    return '${parts[2]}/${parts[1]}/$yy';
  }

  String _toHhMm(String t) {
    if (t.length >= 5) return t.substring(0, 5);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final orderId = _header?['order_id']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          orderId.isNotEmpty ? 'Order #$orderId' : 'My Tickets',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _loading
          ? const TicketLoadingShimmer()
          : _error != null
          ? TicketErrorState(message: _error!, onRetry: _fetch)
          : RefreshIndicator(
              onRefresh: _fetch,
              color: const Color(0xFFB9965A),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Download all button
                  if (_hasDownloadAllUrl())
                    DownloadAllButton(
                      onPressed: () => _openUrl(_getDownloadAllUrl()),
                    ),

                  if (_hasDownloadAllUrl()) const SizedBox(height: 20),

                  // Ticket cards
                  ..._tickets.map((ticket) => _buildTicketCard(ticket)),

                  // Totals
                  if (_totals.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OrderTotalsCard(totals: _totals),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  bool _hasDownloadAllUrl() {
    final url = _header?['actions']?['download_all_url']?.toString();
    return url != null && url.isNotEmpty;
  }

  String _getDownloadAllUrl() {
    return (_header?['actions']?['download_all_url'] ?? '').toString();
  }

  Widget _buildTicketCard(Map<String, dynamic> t) {
    final label = (t['ticket_label'] ?? 'Ticket').toString();

    final event = (t['event'] as Map?)?.cast<String, dynamic>();
    final dates = (event?['dates'] as Map?)?.cast<String, dynamic>();

    final product = (t['product'] as Map?)?.cast<String, dynamic>();
    final productTitle = (product?['title'] ?? '').toString();

    final pricing = (t['pricing'] as Map?)?.cast<String, dynamic>();
    final formatted = (pricing?['formatted'] as Map?)?.cast<String, dynamic>();
    final priceText = (formatted?['total'] ?? '').toString().isNotEmpty
        ? (formatted?['total'] ?? '').toString()
        : (pricing?['total']?.toString() ?? '');

    final orderId = (t['order_id'] ?? '').toString();
    final trx = (_header?['transaction_id'] ?? '').toString();

    final qr = (t['qr'] as Map?)?.cast<String, dynamic>();
    final b64 = (qr?['base64_jpeg'] ?? '').toString();
    final qrBytes = _decodeB64(b64);

    final urls = (t['urls'] as Map?)?.cast<String, dynamic>();
    final downloadSingle = (urls?['download_single_url'] ?? '').toString();

    return TicketDetailsCard(
      ticketLabel: label,
      productTitle: productTitle,
      eventDate: _formatEventDate(dates),
      eventTime: _formatEventTime(dates),
      orderId: orderId,
      transactionId: trx,
      priceText: priceText,
      qrCode: qrBytes,
      onDownload: downloadSingle.isEmpty
          ? null
          : () => _openUrl(downloadSingle),
    );
  }
}
