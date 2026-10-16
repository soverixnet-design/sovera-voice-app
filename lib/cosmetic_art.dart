import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated light stays on the artwork, leaving the portrait/text untouched.
class CosmeticArt extends StatelessWidget {
  final String asset;
  final double phase;
  final String label;
  const CosmeticArt({
    super.key,
    required this.asset,
    this.phase = 0,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      fit: BoxFit.contain,
      semanticLabel: label,
      filterQuality: FilterQuality.high,
    );
    if (phase == 0 || MediaQuery.disableAnimationsOf(context)) return image;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment(-3 + phase * 6, -1),
        end: Alignment(-2 + phase * 6, 1),
        colors: const [
          Colors.transparent,
          Color(0x88FFF8D8),
          Colors.transparent,
        ],
        stops: const [0, .5, 1],
      ).createShader(rect),
      child: image,
    );
  }
}

/// Only mounted, visible artwork ticks; reduced-motion users see a still.
class CosmeticLoop extends StatefulWidget {
  final Widget Function(double phase) builder;
  const CosmeticLoop({super.key, required this.builder});
  @override
  State<CosmeticLoop> createState() => _CosmeticLoopState();
}

class _CosmeticLoopState extends State<CosmeticLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      motion.stop();
      motion.value = 0;
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: motion,
        builder: (_, __) => widget.builder(motion.value),
      );
}

class ArrivalParticles extends CustomPainter {
  final Color color;
  final double phase;
  ArrivalParticles(this.color, this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 22; i++) {
      final t = (phase + i / 22) % 1;
      final x = size.width * ((i * .137 + .06 * math.sin(t * math.pi * 2)) % 1);
      final y = size.height * (1 - t);
      final opacity = math.sin(t * math.pi).clamp(0.0, 1.0).toDouble();
      final paint = Paint()..color = color.withValues(alpha: opacity * .8);
      final radius = 1.5 + i % 3;
      canvas.drawCircle(Offset(x, y), radius, paint);
      canvas.drawLine(
        Offset(x - radius * 2, y),
        Offset(x + radius * 2, y),
        paint..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(ArrivalParticles old) =>
      old.phase != phase || old.color != color;
}
