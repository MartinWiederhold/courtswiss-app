import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen splash overlay with premium scale + fade animation.
///
/// Matches the native launch screen (white bg, centred logo) and adds
/// a subtle entrance animation before fading out to reveal the app.
///
/// **Flow:**
///  1. Native splash (static) is removed when Flutter renders first frame.
///  2. This overlay is immediately visible – identical appearance, no jump.
///  3. Logo scales 0.92 → 1.0 + fades in (550 ms, easeOutCubic).
///  4. Subtle settle pulse 1.0 → 1.03 → 1.0 (180 ms).
///  5. Entire overlay fades out (200 ms).
///  6. Overlay removes itself via [onFinished] callback.
class CsSplashOverlay extends StatefulWidget {
  const CsSplashOverlay({super.key, required this.onFinished});

  /// Called when the animation sequence is complete and the overlay should
  /// be removed from the widget tree.
  final VoidCallback onFinished;

  @override
  State<CsSplashOverlay> createState() => _CsSplashOverlayState();
}

class _CsSplashOverlayState extends State<CsSplashOverlay>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final AnimationController _settleCtrl;
  late final AnimationController _fadeOutCtrl;

  // ── Animations ───────────────────────────────────────────────
  late final Animation<double> _scaleEntrance;
  late final Animation<double> _opacityEntrance;
  late final Animation<double> _scaleSettle;
  late final Animation<double> _opacityFadeOut;

  @override
  void initState() {
    super.initState();

    // Lock status bar to dark icons on white splash.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    // 1) Entrance: scale 0.92 → 1.0  +  opacity 0 → 1   (550 ms)
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _scaleEntrance = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
    );
    _opacityEntrance = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut),
    );

    // 2) Settle: scale 1.0 → 1.03 → 1.0  (180 ms, smooth in-out)
    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleSettle = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.03), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 50),
    ]).animate(
      CurvedAnimation(parent: _settleCtrl, curve: Curves.easeInOut),
    );

    // 3) Fade out entire overlay (200 ms)
    _fadeOutCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _opacityFadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeOutCtrl, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Small initial delay so native splash has time to dismiss cleanly.
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    await _entranceCtrl.forward();
    if (!mounted) return;

    await _settleCtrl.forward();
    if (!mounted) return;

    // Brief hold so user perceives the logo.
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    await _fadeOutCtrl.forward();
    if (!mounted) return;

    widget.onFinished();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _settleCtrl.dispose();
    _fadeOutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entranceCtrl, _settleCtrl, _fadeOutCtrl]),
      builder: (context, child) {
        // Combine scales: entrance drives 0.92→1.0, settle drives 1.0→1.03→1.0
        final scale = _scaleEntrance.value *
            (_settleCtrl.isAnimating || _settleCtrl.isCompleted
                ? _scaleSettle.value
                : 1.0);

        // Combine opacities: entrance fade-in × fade-out
        final opacity = _opacityEntrance.value * _opacityFadeOut.value;

        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              color: Colors.white,
              alignment: Alignment.center,
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            ),
          ),
        );
      },
      child: FractionallySizedBox(
        widthFactor: 0.55, // ~55 % of screen width
        child: Image.asset(
          'assets/sports/Logo_Courtswiss.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
