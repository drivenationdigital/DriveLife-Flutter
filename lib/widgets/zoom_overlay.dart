import 'package:flutter/material.dart';
import 'dart:math' as math;

class ZoomOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback onClose;
  const ZoomOverlay({super.key, required this.child, required this.onClose});

  @override
  State<ZoomOverlay> createState() => _ZoomOverlayState();
}

class _ZoomOverlayState extends State<ZoomOverlay>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;

  late AnimationController _resetController;
  late Animation<num> _scaleAnim;
  late Animation<Offset> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _resetController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          setState(() {
            _scale = _scaleAnim.value as double;
            _offset = _offsetAnim.value;
          });
        });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _reset() {
    _scaleAnim = Tween(begin: _scale, end: 1).animate(_resetController);
    _offsetAnim = Tween(
      begin: _offset,
      end: Offset.zero,
    ).animate(_resetController);
    _resetController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (d) {
        _startScale = _scale;
        _startOffset = _offset;
      },
      onScaleUpdate: (d) {
        setState(() {
          _scale = (_startScale * d.scale).clamp(1.0, 5.0);
          if (_scale > 1.01) {
            _offset = _startOffset + d.focalPointDelta;
          }
        });
      },
      onScaleEnd: (_) {
        if (_scale <= 1.01) widget.onClose(); // exit zoom if user shrank back
        _reset();
      },
      child: ColoredBox(
        color: Colors.black.withOpacity(0.4),
        child: Transform.translate(
          offset: _offset,
          child: Transform.scale(
            scale: _scale,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}
