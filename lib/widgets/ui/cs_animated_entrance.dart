import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Wraps a child in a subtle entrance animation: fade-in + slide-up.
///
/// Use [delay] (or convenience constructor [CsAnimatedEntrance.staggered])
/// to create staggered list entrance effects.
class CsAnimatedEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double slideOffset;

  const CsAnimatedEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = CsDurations.entrance,
    this.slideOffset = 10.0,
  });

  /// Convenience: computes delay from list [index] × [csStaggerDelay].
  factory CsAnimatedEntrance.staggered({
    Key? key,
    required Widget child,
    required int index,
    Duration duration = CsDurations.entrance,
    double slideOffset = 10.0,
  }) {
    return CsAnimatedEntrance(
      key: key,
      delay: csStaggerDelay * index,
      duration: duration,
      slideOffset: slideOffset,
      child: child,
    );
  }

  @override
  State<CsAnimatedEntrance> createState() => _CsAnimatedEntranceState();
}

class _CsAnimatedEntranceState extends State<CsAnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);

    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _slide = Tween<Offset>(
      begin: Offset(0, widget.slideOffset),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(offset: _slide.value, child: child),
        );
      },
      child: widget.child,
    );
  }
}
