import 'package:flutter/material.dart';
import 'dart:math' as math;

class ZoomableMedia extends StatefulWidget {
  final Widget child;
  final void Function(bool zooming)? onZoomChanged;

  const ZoomableMedia({super.key, required this.child, this.onZoomChanged});

  @override
  State<ZoomableMedia> createState() => _ZoomableMediaState();
}

class _ZoomableMediaState extends State<ZoomableMedia>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;

  late AnimationController _resetController;
  late Animation<double> _scaleAnim;
  late Animation<Offset> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );

    _resetController.addListener(() {
      setState(() {
        _scale = _scaleAnim.value;
        _offset = _offsetAnim.value;
      });
    });
  }

  void _resetZoom() {
    _scaleAnim = Tween(begin: _scale, end: 1.0).animate(_resetController);
    _offsetAnim = Tween(
      begin: _offset,
      end: Offset.zero,
    ).animate(_resetController);
    _resetController.forward(from: 0);
    widget.onZoomChanged?.call(false);
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (d) {
        _baseScale = _scale;
        _baseOffset = _offset;
      },
      onScaleUpdate: (d) {
        setState(() {
          _scale = (_baseScale * d.scale).clamp(1.0, 4.0);
          if (_scale > 1.01) {
            widget.onZoomChanged?.call(true);
            _offset = _baseOffset + d.focalPointDelta / _scale;
          }
        });
      },
      onScaleEnd: (_) => _resetZoom(),
      child: Transform.translate(
        offset: _offset,
        child: Transform.scale(scale: _scale, child: widget.child),
      ),
    );
  }
}
