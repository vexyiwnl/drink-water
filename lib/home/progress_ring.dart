import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated goal ring. When [total] goes up, a "+250 ml" drop floats up and the ring glows.
class ProgressRing extends StatefulWidget {
  const ProgressRing({super.key, required this.total, required this.goal, this.size = 260});

  final int total;
  final int goal;
  final double size;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing> with SingleTickerProviderStateMixin {
  late final _splash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  int _delta = 0;

  @override
  void didUpdateWidget(ProgressRing old) {
    super.didUpdateWidget(old);
    if (widget.total > old.total) {
      _delta = widget.total - old.total;
      _splash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _splash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final progress = widget.goal <= 0 ? 0.0 : widget.total / widget.goal;

    return SizedBox.square(
      dimension: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, p, _) => AnimatedBuilder(
          animation: _splash,
          builder: (context, _) {
            final t = _splash.value;
            final splashing = _splash.isAnimating;
            return Stack(alignment: Alignment.center, children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPainter(p, splashing ? sin(t * pi) : 0),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(p * 100).round()}%',
                    style: text.displayMedium!.copyWith(color: aqua, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${widget.total} / ${widget.goal} ml', style: text.titleMedium!.copyWith(color: textMuted)),
              ]),
              if (splashing)
                Positioned(
                  top: widget.size * 0.2 - t * 40,
                  child: Opacity(
                    opacity: 1 - t,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.water_drop, color: aqua, size: 18),
                      Text(' +$_delta ml',
                          style: text.titleMedium!.copyWith(color: aqua, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.glow);

  final double progress;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final arc = (Offset.zero & size).deflate(stroke / 2 + 10);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    canvas.drawCircle(arc.center, arc.width / 2, Paint.from(base)..color = cardHigh);

    final sweep = 2 * pi * progress.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    if (glow > 0) {
      canvas.drawArc(
          arc,
          -pi / 2,
          sweep,
          false,
          Paint.from(base)
            ..strokeWidth = stroke + 12 * glow
            ..color = aqua.withValues(alpha: 0.35 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    }
    canvas.drawArc(
        arc,
        -pi / 2,
        sweep,
        false,
        Paint.from(base)
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(colors: [aquaDeep, aqua, aquaDeep], transform: GradientRotation(-pi / 2))
              .createShader(arc));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.glow != glow;
}
