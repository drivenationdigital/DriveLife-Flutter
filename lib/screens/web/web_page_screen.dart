import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A web page rendered as an app screen.
///
/// Not the system browser. The checkout and the ticket links use
/// `url_launcher`'s in-app browser because payments demand a real one —
/// PayPal refuses embedded user agents and Apple Pay only exists in Safari.
/// Nothing here takes a payment, so this can be a WebView, and a WebView can
/// look like part of the app: our own app bar, our own back, no Safari chrome
/// offering to share or reopen the page elsewhere.
///
/// The work is not the WebView. It is the half-dozen things around it that
/// separate "a web page in a box" from a screen: not flashing white, not
/// becoming a browser when somebody taps a link, having a back button that
/// means what it says, and failing like an app rather than like Chrome.
class WebPageScreen extends StatefulWidget {
  /// The page to show.
  final Uri url;

  /// Shown in the app bar until the page reports its own title.
  final String title;

  /// Schemes that mean "this screen is finished".
  ///
  /// The web side signals completion by navigating to `drivelife://…` — the
  /// same link it uses to escape the system browser. Here it never needs to
  /// leave the app at all: the navigation is caught and the screen closes,
  /// which is why this is smoother than the browser it replaces.
  final Set<String> closeSchemes;

  /// Hosts that stay inside this screen. Anything else opens in a real
  /// browser, because a link to somebody else's site inside our chrome is
  /// how an app quietly turns into a browser nobody asked for.
  final Set<String> internalHosts;

  /// Wear the DriveLife header, as every other screen does.
  ///
  /// The logo leads and [title] sits under it in small type, so the screen
  /// still says what it is. The point is that a page loaded from the web
  /// should not announce itself as a different place: the organiser tapped
  /// Edit Event inside DriveLife and should still be inside DriveLife.
  ///
  /// Off for a page that genuinely is somewhere else — an organiser's own
  /// site, say — where our branding over their content would be a lie.
  final bool branded;

  const WebPageScreen({
    super.key,
    required this.url,
    required this.title,
    this.closeSchemes = const {'drivelife'},
    this.internalHosts = const {},
    this.branded = true,
  });

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;

  /// Until the first paint lands. The WebView is transparent and sits on the
  /// scaffold's own colour, so what shows through is the app's background
  /// rather than the white a WebView paints by default.
  bool _firstPaintDone = false;

  /// Non-null when the page could not be loaded at all.
  String? _error;

  double _progress = 0;

  /// What the page called itself, once it says so.
  String? _pageTitle;

  /// Set when a close-scheme link was followed, so the caller can tell a
  /// finished job from somebody backing out halfway.
  Uri? _closedWith;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Transparent, so the scaffold shows through rather than the WebView's
      // own white — this is what stops the flash on open.
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value / 100);
          },
          onPageFinished: (_) async {
            final title = await _controller.getTitle();
            if (mounted) {
              setState(() {
                _firstPaintDone = true;
                _pageTitle = title;
              });
            }
          },
          onWebResourceError: (error) {
            // Only the main document. A failed image or analytics beacon is
            // not a broken page, and showing an error screen for one would
            // be worse than the missing asset.
            if (!error.isForMainFrame!) return;
            if (mounted) {
              setState(() {
                _error = 'This page could not be loaded.';
                _firstPaintDone = true;
              });
            }
          },
          onNavigationRequest: _onNavigate,
        ),
      )
      ..loadRequest(widget.url);
  }

  /// Decides where each navigation goes.
  Future<NavigationDecision> _onNavigate(NavigationRequest request) async {
    // Subframes are not navigations, they are the page loading itself.
    //
    // iOS and Android disagree here, and the difference is not cosmetic: on
    // Android this fires only for the main frame, while WKWebView reports
    // every iframe and subresource through the same delegate. So a page that
    // embeds Stripe.js — which mounts hidden iframes on js.stripe.com — had
    // each of those read as "the user is navigating off-site", and the rule
    // below dutifully handed js.stripe.com to Safari and left the app.
    //
    // Only a main-frame navigation is a decision a user made.
    if (!request.isMainFrame) return NavigationDecision.navigate;

    final target = Uri.tryParse(request.url);

    if (target == null) return NavigationDecision.prevent;

    // The page saying it is done.
    if (widget.closeSchemes.contains(target.scheme.toLowerCase())) {
      _closedWith = target;
      if (mounted) Navigator.of(context).pop(target);
      return NavigationDecision.prevent;
    }

    // Anything that is not a web page — a tel:, mailto:, or another app's
    // scheme — belongs to the OS, not to this WebView.
    if (target.scheme != 'http' && target.scheme != 'https') {
      unawaited(launchUrl(target, mode: LaunchMode.externalApplication));
      return NavigationDecision.prevent;
    }

    final allowed = widget.internalHosts.isEmpty
        ? {widget.url.host}
        : widget.internalHosts;

    if (allowed.contains(target.host)) return NavigationDecision.navigate;

    // Somebody else's site. Out it goes, with the screen left as it was.
    unawaited(launchUrl(target, mode: LaunchMode.externalApplication));
    return NavigationDecision.prevent;
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _firstPaintDone = false;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // Back walks the page's own history first. Popping the screen on the
      // first back press would throw away an organiser's place in a
      // multi-step form, which is exactly what back is meant to protect.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // Captured before the await: the analyzer is right that `context` is
        // not safe across one, and a Navigator taken afterwards could belong
        // to a tree this screen has already left.
        final navigator = Navigator.of(context);

        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }

        if (mounted) navigator.pop(_closedWith);
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          // The page's own <title> is deliberately ignored when branded: the
          // dashboard calls itself things like "Event editor | DriveLife
          // Accounts", which is correct on the web and wrong here.
          title: widget.branded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo-dark.png', height: 16),
                    const SizedBox(height: 2),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8A8A),
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : Text(
                  _pageTitle?.trim().isNotEmpty == true
                      ? _pageTitle!
                      : widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(_closedWith),
          ),
          bottom: _progress > 0 && _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            if (_error == null) WebViewWidget(controller: _controller),

            // Covers the WebView until it has something to show. An opaque
            // layer rather than a spinner over a white page: the point is
            // that the buyer never sees the page being built.
            if (!_firstPaintDone && _error == null)
              ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),

            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 36,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton(
                        onPressed: _reload,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
