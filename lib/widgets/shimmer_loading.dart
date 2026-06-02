import 'package:flutter/material.dart';

/// Animated shimmer placeholder. No external packages required.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: const [
              Color(0xFFE0E0E0),
              Color(0xFFF0F0F0),
              Color(0xFFE0E0E0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two side-by-side stat cards skeleton for the dashboard header.
class DashboardStatShimmer extends StatelessWidget {
  const DashboardStatShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _card()),
        const SizedBox(width: 12),
        Expanded(child: _card()),
      ],
    );
  }

  Widget _card() => Container(
        height: 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ShimmerBox(width: 56, height: 13),
            ShimmerBox(width: 40, height: 28),
            ShimmerBox(width: 72, height: 11),
          ],
        ),
      );
}

/// Upcoming-session bar skeleton.
class UpcomingSessionShimmer extends StatelessWidget {
  const UpcomingSessionShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShimmerBox(width: 120, height: 12),
          SizedBox(height: 10),
          ShimmerBox(width: double.infinity, height: 18),
        ],
      ),
    );
  }
}

/// 2-column grid of action card skeletons.
class DashboardGridShimmer extends StatelessWidget {
  final int itemCount;
  const DashboardGridShimmer({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShimmerBox(
              width: 36,
              height: 36,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            SizedBox(height: 14),
            ShimmerBox(width: 80, height: 14),
          ],
        ),
      ),
    );
  }
}
