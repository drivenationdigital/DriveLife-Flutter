import 'package:drivelife/providers/feature_tips_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Marks a control as new, and explains it once.
///
/// Wrap the thing itself — a button, an icon, a tab. While the tip is unseen
/// the child gets a small gold dot and, on the first frame it is visible, a
/// callout pointing at it. Either dismissing the callout or using the feature
/// retires the tip for good.
///
/// Once seen — which is the state for all but a few minutes of the app's life
/// — [build] returns the child untouched. No key, no overlay, no post-frame
/// callback, no listener beyond a single boolean.
class FeatureTipTarget extends StatefulWidget {
  final FeatureTip tip;
  final Widget child;

  /// Open the callout by itself when the target first appears.
  ///
  /// False leaves just the dot, for somewhere a popover would be in the way —
  /// a tab bar, or a control that is off screen when the page opens.
  final bool autoShow;

  /// Where the dot sits on the child.
  final Alignment dotAlignment;

  const FeatureTipTarget({
    super.key,
    required this.tip,
    required this.child,
    this.autoShow = true,
    this.dotAlignment = Alignment.topRight,
  });

  @override
  State<FeatureTipTarget> createState() => _FeatureTipTargetState();
}

class _FeatureTipTargetState extends State<FeatureTipTarget> {
  final GlobalKey _anchor = GlobalKey();

  OverlayEntry? _entry;

  /// Guards the post-frame callback so a rebuild cannot queue a second one.
  bool _scheduled = false;

  @override
  void dispose() {
    // Removed directly rather than through _close: the element is going away,
    // and touching the provider from dispose is too late to be useful.
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _maybeShow() {
    _scheduled = false;

    if (!mounted || _entry != null) return;

    final tips = context.read<FeatureTipsProvider>();
    if (!tips.canPresent(widget.tip) || !tips.claim(widget.tip)) return;

    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;

    // Off screen, or scrolled out of view. The dot stays; the callout waits
    // for a frame where there is something to point at.
    final screen = MediaQuery.sizeOf(context);
    if (origin.dy > screen.height || origin.dy + size.height < 0) {
      tips.release(widget.tip);
      return;
    }

    _entry = OverlayEntry(
      builder: (_) => _TipCallout(
        tip: widget.tip,
        anchor: Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
        onDismiss: _close,
      ),
    );

    overlay.insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;

    if (mounted) context.read<FeatureTipsProvider>().markSeen(widget.tip);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when this one tip's answer changes — marking another tip
    // seen does not touch this widget.
    final show = context.select<FeatureTipsProvider, bool>(
      (tips) => tips.shouldShow(widget.tip),
    );

    if (!show) {
      // Nothing left to say. An overlay may still be open from the frame the
      // dismissal happened on, so close it, but leave the tree alone.
      if (_entry != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _entry?.remove();
          _entry = null;
        });
      }
      return widget.child;
    }

    if (widget.autoShow && !_scheduled && _entry == null) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
    }

    return Stack(
      key: _anchor,
      clipBehavior: Clip.none,
      children: [
        // Using the feature is as good as reading about it, and better —
        // a tip still flagging something the user has already found is noise.
        Listener(
          onPointerDown: (_) => _close(),
          behavior: HitTestBehavior.translucent,
          child: widget.child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: widget.dotAlignment,
              child: const _TipDot(),
            ),
          ),
        ),
      ],
    );
  }
}

/// The marker on an unseen control.
class _TipDot extends StatelessWidget {
  const _TipDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: const Color(0xFFC4A062),
        shape: BoxShape.circle,
        // A ring in the page colour, so the dot reads as separate from
        // whatever it is sitting on rather than as part of the icon.
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

/// The card that explains a tip, pointing at its target.
class _TipCallout extends StatefulWidget {
  final FeatureTip tip;
  final Rect anchor;
  final VoidCallback onDismiss;

  const _TipCallout({
    required this.tip,
    required this.anchor,
    required this.onDismiss,
  });

  @override
  State<_TipCallout> createState() => _TipCalloutState();
}

class _TipCalloutState extends State<_TipCallout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  static const Color _ink = Color(0xFF14140F);
  static const Color _gold = Color(0xFFC4A062);
  static const double _cardWidth = 268;
  static const double _arrow = 9;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final anchor = widget.anchor;

    // Below the target, unless there is more room above it — a callout that
    // runs off the bottom of the screen explains nothing.
    final spaceBelow = screen.height - anchor.bottom - padding.bottom;
    final below = spaceBelow > 190 || spaceBelow > anchor.top;

    // Centred on the target, then pulled back inside the screen. The arrow is
    // placed against the target afterwards, so it keeps pointing at the right
    // thing however far the card had to move.
    final wanted = anchor.center.dx - _cardWidth / 2;
    final left = wanted.clamp(12.0, screen.width - _cardWidth - 12.0);

    final arrowLeft = (anchor.center.dx - left - _arrow).clamp(
      14.0,
      _cardWidth - 14.0 - _arrow * 2,
    );

    final fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    return Stack(
      children: [
        // Tapping anywhere closes it. No dimming: this is a hint about one
        // button, not a modal, and darkening the screen for it would make a
        // small thing feel like an interruption.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: below ? anchor.bottom + 8 : null,
          bottom: below ? null : screen.height - anchor.top + 8,
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, below ? -0.04 : 0.04),
                end: Offset.zero,
              ).animate(fade),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (below) _Arrow(left: arrowLeft, pointingUp: true),
                  _card(context),
                  if (!below) _Arrow(left: arrowLeft, pointingUp: false),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _cardWidth,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 15, color: _gold),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.tip.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.tip.body,
              style: const TextStyle(
                color: Color(0xFFD6D2C8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: _gold,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The little triangle joining the card to what it is about.
class _Arrow extends StatelessWidget {
  final double left;
  final bool pointingUp;

  const _Arrow({required this.left, required this.pointingUp});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: left),
      child: CustomPaint(
        size: const Size(_TipCalloutState._arrow * 2, _TipCalloutState._arrow),
        painter: _ArrowPainter(pointingUp: pointingUp),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final bool pointingUp;

  const _ArrowPainter({required this.pointingUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _TipCalloutState._ink;
    final path = Path();

    if (pointingUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }

    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) =>
      oldDelegate.pointingUp != pointingUp;
}
