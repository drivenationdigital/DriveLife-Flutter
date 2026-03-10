import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';

class TicketsSection extends StatefulWidget {
  final List<dynamic> tickets;
  final ThemeProvider theme;

  const TicketsSection({super.key, required this.tickets, required this.theme});

  @override
  State<TicketsSection> createState() => _TicketsSectionState();
}

class _TicketsSectionState extends State<TicketsSection> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _currentPage = 1;
  static const int _pageSize = 15;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<dynamic> get _filtered {
    if (_query.isEmpty) return widget.tickets;
    final q = _query.toLowerCase();
    return widget.tickets.where((t) {
      final id = t['order_item_id']?.toString() ?? '';
      final buyer = '${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'
          .toLowerCase();
      final email = (t['email'] ?? '').toString().toLowerCase();
      final phone = (t['phone'] ?? '').toString().toLowerCase();
      return id.contains(q) ||
          buyer.contains(q) ||
          email.contains(q) ||
          phone.contains(q);
    }).toList();
  }

  List<dynamic> get _paged {
    final all = _filtered;
    final start = (_currentPage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil();
    final start = filtered.isEmpty ? 0 : (_currentPage - 1) * _pageSize + 1;
    final end = (_currentPage * _pageSize).clamp(0, filtered.length);

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
            // ── Header ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tickets',
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
                    '${widget.tickets.length}',
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

            // ── Search ────────────────────────────────────────────────
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() {
                _query = v.trim();
                _currentPage = 1;
              }),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by ID, name, email or phone…',
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
                          setState(() {
                            _query = '';
                            _currentPage = 1;
                          });
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

            // ── Empty state ───────────────────────────────────────────
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No tickets yet'
                        : 'No tickets match "$_query"',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ),
              )
            else ...[
              // ── Table ─────────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 40,
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FixedColumnWidth(60), // ID
                      1: FixedColumnWidth(120), // Buyer
                      2: FixedColumnWidth(170), // Email
                      3: FixedColumnWidth(120), // Phone
                      4: FixedColumnWidth(150), // Ticket
                      5: FixedColumnWidth(75), // Subtotal
                      6: FixedColumnWidth(160), // Car
                      7: FixedColumnWidth(120), // Car Club
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Colors.grey[100]!,
                        width: 1,
                      ),
                      bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                    ),
                    children: [
                      // Header row
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey[300]!,
                              width: 1.5,
                            ),
                          ),
                        ),
                        children: [
                          _HeaderCell('ID'),
                          _HeaderCell('Buyer'),
                          _HeaderCell('Email'),
                          _HeaderCell('Phone'),
                          _HeaderCell('Ticket'),
                          _HeaderCell('Subtotal'),
                          _HeaderCell('Car'),
                          _HeaderCell('Car Club'),
                        ],
                      ),
                      // Data rows
                      ..._paged.map((t) {
                        final car = t['car'] as Map? ?? {};
                        final carStr = [
                          car['make'] ?? '',
                          car['model'] ?? '',
                          if ((car['reg'] ?? '').toString().isNotEmpty)
                            '(${car['reg']})',
                        ].where((s) => s.isNotEmpty).join(' ');

                        final buyer =
                            '${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'
                                .trim();

                        return TableRow(
                          children: [
                            _DataCell(
                              t['order_item_id']?.toString() ?? '-',
                              bold: true,
                              color: widget.theme.primaryColor,
                            ),
                            _DataCell(buyer),
                            _DataCell(t['email'] ?? '-', small: true),
                            _DataCell(t['phone'] ?? '-'),
                            _DataCell(t['ticket_name'] ?? '-', small: true),
                            _DataCell('£${t['total'] ?? '0.00'}', bold: true),
                            _DataCell(
                              carStr.isEmpty ? '-' : carStr,
                              small: true,
                            ),
                            _DataCell(
                              (t['car_club'] ?? '').toString().isEmpty
                                  ? '-'
                                  : t['car_club'],
                              small: true,
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Pagination ────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$start–$end of ${filtered.length}',
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
                      const SizedBox(width: 8),
                      Text(
                        '$_currentPage / $totalPages',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
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
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String value;
  final bool bold;
  final bool small;
  final Color? color;

  const _DataCell(
    this.value, {
    this.bold = false,
    this.small = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        value,
        style: TextStyle(
          fontSize: small ? 12 : 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color ?? Colors.black87,
        ),
      ),
    );
  }
}

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