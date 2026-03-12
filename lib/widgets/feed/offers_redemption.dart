import 'package:drivelife/api/offers_api_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class OfferRedemptionScreen extends StatefulWidget {
  final int offerId;
  final String? offerImage;

  const OfferRedemptionScreen({super.key, required this.offerId, this.offerImage});

  @override
  State<OfferRedemptionScreen> createState() => _OfferRedemptionScreenState();
}

class _OfferRedemptionScreenState extends State<OfferRedemptionScreen> {
  static const _cream = Color(0xFFF5F0E8);

  OfferRedemptionData? _data;
  bool _loading = true;
  String? _error;
  bool _alreadyRedeemed = false;

  // FIX: Read theme in didChangeDependencies, not initState.
  // initState runs before the widget is inserted into the tree so
  // Provider.of(context) throws a late-init / lookup error there.
  ThemeProvider? _theme;

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

  Future<void> _load() async {
    debugPrint('Loading offer details for offer ID ${widget.offerId}');
    final result = await OffersApi.getRedemptionDetails(
      offerId: widget.offerId,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.alreadyRedeemed) {
        _alreadyRedeemed = true;
        _error = 'You have already redeemed this offer.';
      } else if (result.hasError) {
        _error = result.error;
      } else {
        _data = result.data;
      }
    });
  }

  // Safe accessor — guaranteed non-null after didChangeDependencies
  ThemeProvider get theme => _theme!;

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
      body: CustomScrollView(
        slivers: [
          // ── Hero image ─────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHero()),

          // ── Content ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _loading
                ? _buildLoading()
                : _error != null
                ? _buildError()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  // Full-width image block below the app bar
  Widget _buildHero() {
    final imageUrl = widget.offerImage ?? _data?.imageUrl;

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
    child: Icon(Icons.local_offer_rounded, color: theme.primaryColor, size: 48),
  );

  Widget _buildLoading() => SizedBox(
    height: 300,
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
        Icon(
          _alreadyRedeemed
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          color: _alreadyRedeemed ? Colors.green : Colors.red[300],
          size: 56,
        ),
        const SizedBox(height: 16),
        Text(
          _alreadyRedeemed ? 'Already Redeemed' : 'Unavailable',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'Something went wrong.',
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

  Widget _buildContent() {
    final d = _data!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
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
          Text(
            d.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
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
                "h1, h2, h3, h4, h5, h6": Style(
                  margin: Margins.only(top: 16, bottom: 8),
                  fontWeight: FontWeight.bold,
                ),
                "ul, ol": Style(margin: Margins.only(left: 16, bottom: 12)),
                "li": Style(margin: Margins.only(bottom: 4)),
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

          const SizedBox(height: 10),

          // QR Code — no container border, clean white card like screenshot
          Container(
            padding: const EdgeInsets.all(20),
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
            child: _buildQr(d),
          ),

          const SizedBox(height: 24),

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
        ],
      ),
    );
  }

  Widget _buildQr(OfferRedemptionData d) {
    if (d.hasServerQr) {
      return Image.memory(
        d.qrBytes!,
        width: 260,
        height: 260,
        fit: BoxFit.contain,
      );
    }

    if (d.qrUrl != null && d.qrUrl!.isNotEmpty) {
      return Image.network(
        d.qrUrl!,
        width: 260,
        height: 260,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : SizedBox(
                width: 260,
                height: 260,
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
    width: 260,
    height: 260,
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
}
