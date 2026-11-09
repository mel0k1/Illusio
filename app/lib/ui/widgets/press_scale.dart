import 'package:flutter/material.dart';

import '../theme.dart';

class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.98,
    this.enabled = true,
  });

  final Widget child;
  final double pressedScale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (!widget.enabled) {
          return;
        }
        if (mounted) {
          setState(() => _pressed = true);
        }
      },
      onPointerUp: (_) {
        if (mounted && _pressed) {
          setState(() => _pressed = false);
        }
      },
      onPointerCancel: (_) {
        if (mounted && _pressed) {
          setState(() => _pressed = false);
        }
      },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: _pressed ? effectsFast : spatialFast,
        curve: _pressed ? exitCurve : springCurve,
        child: widget.child,
      ),
    );
  }
}
