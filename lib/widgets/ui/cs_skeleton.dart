import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Shimmer-style skeleton placeholder for perceived-performance.
///
/// Use while data is loading instead of a blocking spinner.
class CsSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const CsSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  /// A text-line skeleton (single row).
  const CsSkeleton.line({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.borderRadius = 6,
  });

  /// A circle skeleton (e.g. avatar).
  const CsSkeleton.circle({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = 999;

  @override
  State<CsSkeleton> createState() => _CsSkeletonState();
}

class _CsSkeletonState extends State<CsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                CsColors.gray100,
                CsColors.gray200,
                CsColors.gray100,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value,
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A pre-built card skeleton that mimics a list item (avatar + 2 lines).
class CsSkeletonCard extends StatelessWidget {
  const CsSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: CsColors.white,
        borderRadius: BorderRadius.circular(CsRadii.md),
        border: Border.all(color: CsColors.gray200),
      ),
      child: Row(
        children: [
          const CsSkeleton.circle(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CsSkeleton.line(width: 140, height: 14),
                const SizedBox(height: 8),
                CsSkeleton.line(width: 200, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A skeleton that mimics the match detail header card.
class CsSkeletonMatchHeader extends StatelessWidget {
  const CsSkeletonMatchHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CsColors.white,
        borderRadius: BorderRadius.circular(CsRadii.md),
        border: Border.all(color: CsColors.gray200),
        boxShadow: CsShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CsSkeleton(width: 20, height: 20, borderRadius: 4),
              const SizedBox(width: 10),
              CsSkeleton(width: 70, height: 22, borderRadius: CsRadii.full),
            ],
          ),
          const SizedBox(height: 12),
          const CsSkeleton.line(width: 180, height: 18),
          const SizedBox(height: 10),
          const CsSkeleton.line(width: 220, height: 12),
          const SizedBox(height: 6),
          const CsSkeleton.line(width: 160, height: 12),
          const SizedBox(height: 12),
          CsSkeleton(height: 6, borderRadius: 3),
        ],
      ),
    );
  }
}

/// A skeleton that mimics a section with title + list items.
class CsSkeletonSection extends StatelessWidget {
  final int itemCount;
  const CsSkeletonSection({super.key, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CsSkeleton.line(width: 120, height: 14),
        const SizedBox(height: 10),
        ...List.generate(itemCount, (_) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: CsSkeletonCard(),
          );
        }),
      ],
    );
  }
}
