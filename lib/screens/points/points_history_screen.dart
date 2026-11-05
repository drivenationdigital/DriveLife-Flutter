import 'package:drivelife/api/points_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Where somebody's points came from, and where they went.
///
/// Reached by tapping the big number on the points screen, which is the
/// thing anybody wanting this explanation is already looking at.
///
/// ── WHY BOTH DIRECTIONS IN ONE LIST ─────────────────────────────────
///
/// Earning and losing are the same question asked twice — "why is the
/// number what it is" — and the answer is the sequence. Two tabs would
/// mean reading a gain and the reversal that cancelled it in different
/// places, which is precisely the pair somebody is trying to reconcile
/// when they come here. So one list, newest first, with the sign doing
/// the work.
class PointsHistoryScreen extends StatefulWidget {
  const PointsHistoryScreen({super.key});

  @override
  State<PointsHistoryScreen> createState() => _PointsHistoryScreenState();
}

class _PointsHistoryScreenState extends State<PointsHistoryScreen> {
  static const Color _gain = Color(0xFF1A7F37);
  static const Color _loss = Color(0xFFC0392B);

  final ScrollController _scroll = ScrollController();

  final List<PointsEntry> _entries = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 400px of runway, so the next page is usually in by the time the
    // bottom arrives and the list does not visibly stall.
    if (!_hasMore || _loadingMore || _loading) return;

    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final result = await PointsAPI.history(page: 1);
    if (!mounted) return;

    setState(() {
      _entries
        ..clear()
        ..addAll(result.entries);
      _hasMore = result.hasMore;
      _page = 1;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);

    final next = _page + 1;
    final result = await PointsAPI.history(page: next);

    if (!mounted) return;

    setState(() {
      _entries.addAll(result.entries);
      // The page counter only advances on a page that actually arrived.
      // Incrementing regardless would skip a page after one failed
      // request and leave a hole in the middle of the history.
      if (result.entries.isNotEmpty) _page = next;
      _hasMore = result.hasMore;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: theme.textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: DlHeading(
          'Points history',
          fontSize: 18,
          color: theme.textColor,
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: theme.primaryColor,
        onRefresh: _load,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
            : _entries.isEmpty
                ? _empty(theme)
                : _list(theme),
      ),
    );
  }

  /// Scrollable, or an empty history cannot be pulled to refresh.
  Widget _empty(ThemeProvider theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 90),
        Icon(
          Icons.receipt_long_outlined,
          size: 44,
          color: theme.subtextColor.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Nothing yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: theme.textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            'Post a vehicle, log a spot or add one to your garage and it '
            'will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.45,
              color: theme.subtextColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(ThemeProvider theme) {
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      // One extra row for the loading spinner at the foot, and only
      // while there is another page coming.
      itemCount: _entries.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: theme.subtextColor.withValues(alpha: 0.12),
      ),
      itemBuilder: (context, index) {
        if (index >= _entries.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.primaryColor,
                ),
              ),
            ),
          );
        }

        return _row(theme, _entries[index]);
      },
    );
  }

  Widget _row(ThemeProvider theme, PointsEntry entry) {
    final gain = entry.isGain;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // An arrow rather than a per-rule icon. Which direction the
          // points went is the thing being scanned for; what caused it
          // is in the words next to it, and five bespoke icons would
          // compete with the sign for attention.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (gain ? _gain : _loss).withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              gain ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 18,
              color: gain ? _gain : _loss,
            ),
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // The admin's note when there is one, because on a
                  // manual grant it is the only explanation the row has.
                  // Otherwise the date, which is what every other row
                  // needs.
                  entry.reason ?? _when(entry.at),
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.subtextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // The sign always shown, including the + . "50" and
                // "-50" read as a number and a mistake; "+50" and "-50"
                // read as a pair.
                '${gain ? '+' : ''}${entry.amount}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: gain ? _gain : _loss,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.balanceAfter}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.subtextColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// How a date reads in a list: "Today", "Yesterday", then "5 Nov 2026".
  ///
  /// Converted to local time first. The ledger is UTC, and a row earned
  /// at 00:30 in London would otherwise sit under yesterday's date.
  String _when(DateTime? at) {
    if (at == null) return '';

    final local = at.toLocal();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = midnight.difference(day).inDays;

    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';

    if (days == 0) return 'Today, $time';
    if (days == 1) return 'Yesterday, $time';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
