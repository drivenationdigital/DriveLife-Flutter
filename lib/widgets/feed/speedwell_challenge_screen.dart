import 'package:drivelife/api/offers_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:drivelife/providers/theme_provider.dart';

class SpeedwellChallengeScreen extends StatefulWidget {
  final int offerId;
  final String? offerImage;

  const SpeedwellChallengeScreen({
    super.key,
    required this.offerId,
    this.offerImage,
  });

  @override
  State<SpeedwellChallengeScreen> createState() =>
      _SpeedwellChallengeScreenState();
}

class _SpeedwellChallengeScreenState extends State<SpeedwellChallengeScreen> {
  OfferRedemptionData? _offer;
  List<LeaderboardEntry> _leaderboard = [];
  LeaderboardEntry? _currentUserEntry;
  Map<String, dynamic>? _stats;

  bool _loading = true;
  String? _offerError;

  ThemeProvider? _theme;

  // Medal palette
  static const _gold = Color(0xFFFFD700);
  static const _silver = Color(0xFFB8B8B8);
  static const _bronze = Color(0xFFCD7F32);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme ??= Provider.of<ThemeProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  ThemeProvider get theme => _theme!;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _offerError = null;
    });

    // Fire both requests in parallel
    final redemptionFuture = OffersApi.getRedemptionDetails(
      offerId: widget.offerId,
    );
    final leaderboardFuture = OffersApi.getSpeedwellLeaderboard(
      offerId: widget.offerId,
    );

    final redemption = await redemptionFuture;
    final leaderboard = await leaderboardFuture;

    if (!mounted) return;

    setState(() {
      _loading = false;

      // Offer / QR
      if (redemption.hasError && !redemption.alreadyRedeemed) {
        _offerError = redemption.error;
      } else if (!redemption.alreadyRedeemed) {
        _offer = redemption.data;
      }
      // For Speedwell we intentionally don't block on alreadyRedeemed —
      // the QR is shown for score logging, not one-time redemption.

      // Leaderboard (non-fatal if it fails — just shows empty state)
      _leaderboard = leaderboard.leaderboard;
      _currentUserEntry = leaderboard.currentUser;
      _stats = leaderboard.stats;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: theme.primaryColor,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHero()),
            if (_loading)
              SliverToBoxAdapter(child: _buildLoading())
            else if (_offerError != null)
              SliverToBoxAdapter(child: _buildError())
            else ...[
              SliverToBoxAdapter(child: _buildOfferContent()),
              SliverToBoxAdapter(child: _buildLeaderboardSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Hero image ─────────────────────────────────────────────────────────────

  Widget _buildHero() {
    final imageUrl = widget.offerImage ?? _offer?.imageUrl;
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: imageUrl != null
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => _heroPlaceholder(),
            )
          : _heroPlaceholder(),
    );
  }

  Widget _heroPlaceholder() => Container(
    color: const Color(0xFF1A1A1A),
    width: double.infinity,
    height: double.infinity,
    child: Icon(Icons.speed_rounded, color: theme.primaryColor, size: 52),
  );

  // ── Loading / error states ─────────────────────────────────────────────────

  Widget _buildLoading() => SizedBox(
    height: 320,
    child: Center(
      child: CircularProgressIndicator(
        color: theme.primaryColor,
        strokeWidth: 2,
      ),
    ),
  );

  Widget _buildError() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 56),
        const SizedBox(height: 16),
        const Text(
          'Unavailable',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _offerError ?? 'Something went wrong.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.primaryColor,
            side: BorderSide(color: theme.primaryColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Go Back'),
        ),
      ],
    ),
  );

  // ── Offer content + QR ─────────────────────────────────────────────────────

  Widget _buildOfferContent() {
    final d = _offer;
    if (d == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title
          Text(
            d.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: theme.primaryColor,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 4),

          // Subtitle
          Text(
            d.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 16),

          // Description
          if (d.description.isNotEmpty)
            Html(
              data: d.description,
              style: {
                "body": Style(
                  textAlign: TextAlign.center,
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  fontSize: FontSize(15),
                  lineHeight: const LineHeight(1.6),
                  color: Colors.grey.shade700,
                ),
                "p": Style(margin: Margins.only(bottom: 12)),
                "a": Style(
                  color: const Color(0xFFAE9159),
                  textDecoration: TextDecoration.underline,
                ),
                "strong, b": Style(fontWeight: FontWeight.bold),
                "em, i": Style(fontStyle: FontStyle.italic),
              },
              onLinkTap: (url, attributes, element) async {
                if (url != null) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
            ),

          const SizedBox(height: 24),

          // QR card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'YOUR CHALLENGE QR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: theme.primaryColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                _buildQr(d),
                const SizedBox(height: 12),
                Text(
                  'Present this at the Speedwall to log your score',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Valid until chip
          if (d.validTo.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: theme.primaryColor,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Valid until ${d.validTo}',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildQr(OfferRedemptionData d) {
    if (d.hasServerQr) {
      return Image.memory(
        d.qrBytes!,
        width: 220,
        height: 220,
        fit: BoxFit.contain,
      );
    }

    if (d.qrUrl != null && d.qrUrl!.isNotEmpty) {
      return Image.network(
        d.qrUrl!,
        width: 220,
        height: 220,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : SizedBox(
                width: 220,
                height: 220,
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.primaryColor,
                    strokeWidth: 2,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => _qrError(),
      );
    }

    return _qrError();
  }

  Widget _qrError() => const SizedBox(
    width: 220,
    height: 220,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 48, color: Colors.black26),
          SizedBox(height: 8),
          Text(
            'QR unavailable',
            style: TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ],
      ),
    ),
  );

  // ── Leaderboard ────────────────────────────────────────────────────────────
  static const _pageSize = 10;
  int _leaderboardPage = 0;

  List<LeaderboardEntry> get _currentPageEntries {
    final start = _leaderboardPage * _pageSize;
    final end = (_leaderboardPage + 1) * _pageSize;
    return _leaderboard.sublist(
      start.clamp(0, _leaderboard.length),
      end.clamp(0, _leaderboard.length),
    );
  }

  int get _totalPages => (_leaderboard.length / _pageSize).ceil().clamp(1, 999);

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardSection() {
    final bool userIsPinned =
        _currentUserEntry != null &&
        !_currentPageEntries.any((e) => e.isCurrentUser);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: theme.primaryColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Leaderboard',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              // const Spacer(),
              // if (_leaderboard.isNotEmpty)
              //   Text(
              //     '${_leaderboard.length} player${_leaderboard.length == 1 ? '' : 's'}',
              //     style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              //   ),
            ],
          ),

          const SizedBox(height: 16),

          if (_stats != null) ...[
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.gps_fixed_rounded,
                    iconColor: const Color(0xFF22A06B),
                    label: 'Top Hits',
                    value: '${_stats!['highest_hits']}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.close_rounded,
                    iconColor: const Color(0xFFE5484D),
                    label: 'Least Misses',
                    value: '${_stats!['lowest_misses']}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.bolt_rounded,
                    iconColor: const Color(0xFFE9A23B),
                    label: 'Best Time',
                    value: '${_stats!['lowest_reaction_time']}s',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (_leaderboard.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.leaderboard_outlined,
                      size: 40,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No scores yet — be the first!',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // ── Column headers ───────────────────────────────────────
           Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 40), // rank column
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Player',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[400],
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Text(
                    'Hits · Misses · Time',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[400],
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),

            // ── Rows ────────────────────────────────────────────────
            ..._currentPageEntries.map(_buildRow),

            // ── Current user pinned ──────────────────────────────────
            if (userIsPinned) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'Your rank',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                  ],
                ),
              ),
              _buildRow(_currentUserEntry!),
            ],

            const SizedBox(height: 16),

            // ── Pagination ───────────────────────────────────────────
            if (_totalPages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pageButton(
                    icon: Icons.chevron_left_rounded,
                    enabled: _leaderboardPage > 0,
                    onTap: () => setState(() => _leaderboardPage--),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Page ${_leaderboardPage + 1} of $_totalPages',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _pageButton(
                    icon: Icons.chevron_right_rounded,
                    enabled: _leaderboardPage < _totalPages - 1,
                    onTap: () => setState(() => _leaderboardPage++),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _pageButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? theme.primaryColor.withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? theme.primaryColor.withOpacity(0.25)
                : Colors.grey.shade200,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? theme.primaryColor : Colors.grey[400],
        ),
      ),
    );
  }

  Widget _avatarFallback(LeaderboardEntry entry, Color? medalColor) {
    return Center(
      child: Text(
        entry.displayName.isNotEmpty ? entry.displayName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: medalColor != null
              ? Color.lerp(medalColor, Colors.black, 0.4)
              : theme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildRow(LeaderboardEntry entry) {
    final bool isMe = entry.isCurrentUser;

    // Medal tint for the top 3
    Color rankColor;
    switch (entry.rank) {
      case 1:
        rankColor = const Color(0xFFE9A23B); // gold
        break;
      case 2:
        rankColor = const Color(0xFF9AA0A6); // silver
        break;
      case 3:
        rankColor = const Color(0xFFB06A3B); // bronze
        break;
      default:
        rankColor = Colors.grey.shade400;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? theme.primaryColor.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isMe
            ? Border.all(color: theme.primaryColor.withOpacity(0.35))
            : null,
      ),
      child: Row(
        children: [
          // ── Rank ────────────────────────────────────────────────
          SizedBox(
            width: 16,
            child: Center(
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: rankColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ── Avatar ──────────────────────────────────────────────
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey.shade200,
            backgroundImage:
                (entry.profileImage != null && entry.profileImage!.isNotEmpty)
                ? NetworkImage(entry.profileImage!)
                : null,
            child: (entry.profileImage == null || entry.profileImage!.isEmpty)
                ? Text(
                    entry.displayName.isNotEmpty
                        ? entry.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // ── Name ────────────────────────────────────────────────
          Expanded(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),

          // ── Stats: hits headline, misses + time below ───────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.gps_fixed_rounded,
                    size: 13,
                    color: const Color(0xFF22A06B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.hits ?? 0}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.misses ?? 0} miss · ${entry.score.toStringAsFixed(2)}s',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
