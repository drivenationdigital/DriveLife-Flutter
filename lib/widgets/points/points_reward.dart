import 'dart:async';
import 'dart:math' as math;

import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "You earned 500 points", as something worth watching.
///
/// Built to be reused: every rule that pays out should end here, so
/// earning points feels the same wherever it happens and there is one
/// place to change how it looks.
///
///     await PointsReward.show(context, points: 500,
///         reason: 'For adding a vehicle to your garage');
///
/// WHY AN OVERLAY AND NOT A DIALOG
///
/// A dialog takes the navigator, and the moments points are earned are
/// almost always moments something else is already navigating — a form
/// popping back, a sheet closing. An overlay entry sits above all of
/// that and does not care what the route stack is doing.
///
/// NOTHING IS BLOCKED
///
/// It dismisses itself, and a tap anywhere sends it early. Points are
/// good news, and good news should never need acknowledging — a reward
/// with an OK button is a reward that interrupts.
class PointsReward {
  const PointsReward._();

  /// How long it stays once it has finished arriving.
  static const Duration _linger = Duration(milliseconds: 2600);

  /// Show the reward. Resolves when it has gone.
  ///
  /// [points] of zero or less does nothing at all, so a caller can pass
  /// a server's `points_awarded` straight in without checking first —
  /// which is what stops "+500" appearing for somebody adding their
  /// fourth vehicle.
  static Future<void> show(
    BuildContext context, {
    required int points,
    String? reason,
  }) async {
    if (points <= 0 || !context.mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // A short tap, not a notification buzz. The animation is the event;
    // the haptic is punctuation under it.
    unawaited(HapticFeedback.mediumImpact());

    final completer = Completer<void>();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RewardLayer(
        points: points,
        reason: reason,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    overlay.insert(entry);
    await completer.future;
  }
}

class _RewardLayer extends StatefulWidget {
  final int points;
  final String? reason;
  final VoidCallback onDone;

  const _RewardLayer({
    required this.points,
    required this.reason,
    required this.onDone,
  });

  @override
  State<_RewardLayer> createState() => _RewardLayerState();
}

class _RewardLayerState extends State<_RewardLayer>
    with TickerProviderStateMixin {
  static const Color _gold = Color(0xFFAE9159);
  static const Color _ink = Color(0xFF111113);

  /// Arrival: the scrim, the card, the burst.
  late final AnimationController _in = AnimationController(
    duration: const Duration(milliseconds: 620),
    vsync: this,
  );

  /// Departure, run separately so an early tap can start it at any
  /// point in the arrival without rewinding what is on screen.
  late final AnimationController _out = AnimationController(
    duration: const Duration(milliseconds: 260),
    vsync: this,
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();

    _in.forward();

    Future<void>.delayed(PointsReward._linger + _in.duration!, () {
      if (mounted) _leave();
    });
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;

    await _out.forward();
    widget.onDone();
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_in, _out]),
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_in.value);
        final leaving = Curves.easeIn.transform(_out.value);
        final opacity = (1 - leaving).clamp(0.0, 1.0);

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            // Anywhere. Hunting for a close button on something that
            // will go on its own is a worse experience than the two
            // seconds of waiting it saves.
            onTap: _leave,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: opacity,
              child: Container(
                color: Colors.black.withValues(alpha: 0.55 * t),
                alignment: Alignment.center,
                child: Transform.scale(
                  // Overshoots very slightly and settles. A reward that
                  // arrives at exactly its final size looks placed; one
                  // that springs looks given.
                  scale: (0.82 + 0.18 * Curves.easeOutBack.transform(_in.value))
                      .clamp(0.0, 1.2),
                  child: _card(t),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(double t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Rays, thrown outward as the medal lands.
                  CustomPaint(
                    size: const Size(132, 132),
                    painter: _BurstPainter(progress: t, colour: _gold),
                  ),

                  // The medal. Scaled on its own curve so it arrives a
                  // beat after the burst starts, which is what makes
                  // the burst read as caused by it.
                  Transform.scale(
                    scale: Curves.easeOutBack
                        .transform((_in.value * 1.6).clamp(0.0, 1.0))
                        .clamp(0.0, 1.2),
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: const BoxDecoration(
                        color: _gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 46,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Counts up rather than appearing. The number IS the
            // reward, and watching it climb is most of why this is an
            // animation and not a snackbar.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: widget.points.toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => DlHeading(
                '+${_format(value.round())}',
                fontSize: 52,
                fontWeight: FontWeight.w900,
                height: 1,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),

            DlHeading(
              widget.points == 1 ? 'Point earned' : 'Points earned',
              fontSize: 17,
              color: _gold,
            ),

            if (widget.reason != null && widget.reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.reason!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(int n) {
    final s = n.toString();
    final buffer = StringBuffer();

    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }

    return buffer.toString();
  }
}

/// The rays behind the medal.
///
/// Drawn rather than animated as widgets: twelve tapered lines that
/// shoot out and fade is twelve more widgets to lay out every frame,
/// and a painter does it in one.
class _BurstPainter extends CustomPainter {
  final double progress;
  final Color colour;

  const _BurstPainter({required this.progress, required this.colour});

  static const int _rays = 12;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final centre = Offset(size.width / 2, size.height / 2);

    // They travel out and stop before the edge, then fade. Fading on
    // the way out rather than at the end is what stops them looking
    // like a loading spinner frozen mid-turn.
    final travel = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);

    final paint = Paint()
      ..color = colour.withValues(alpha: 0.9 * fade)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    final inner = 44 + 14 * travel;
    final outer = inner + 12 * travel;

    for (var i = 0; i < _rays; i++) {
      // Offset by half a step so no ray points straight up, which reads
      // as an arrow rather than a burst.
      final angle = (i / _rays) * 2 * math.pi + (math.pi / _rays);

      final from = centre + Offset(math.cos(angle), math.sin(angle)) * inner;
      final to = centre + Offset(math.cos(angle), math.sin(angle)) * outer;

      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.colour != colour;
}
