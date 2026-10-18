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
    if (asset == 'assets/effects/castle-entry.webp') {
      return Semantics(
        label: label,
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(asset, fit: BoxFit.contain),
              IgnorePointer(child: CustomPaint(painter: CastleFlagPainter(
                MediaQuery.disableAnimationsOf(context) ? 0 : phase,
              ))),
            ]),
          ),
        ),
      );
    }
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

/// Native flag motion over the castle artwork; no WebView or network needed.
class CastleFlagPainter extends CustomPainter {
  final double phase;
  CastleFlagPainter(this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    final pole = Offset(size.width * .5, size.height * .16);
    canvas.drawLine(pole, Offset(pole.dx, size.height * .295),
      Paint()..color = const Color(0xFFB8C7E8)..strokeWidth = 1.5);
    final width = size.width * .27;
    final height = size.height * .055;
    double wave(double x) => math.sin(x * math.pi * 2 - phase * math.pi * 28) * height * .12 * x;
    final flag = Path()..moveTo(pole.dx, pole.dy);
    for (var i = 1; i <= 24; i++) {
      final x = i / 24;
      flag.lineTo(pole.dx + width * x, pole.dy + wave(x));
    }
    for (var i = 24; i >= 0; i--) {
      final x = i / 24;
      flag.lineTo(pole.dx + width * x, pole.dy + height + wave(x));
    }
    flag.close();
    canvas.drawPath(flag, Paint()..shader = const LinearGradient(
      colors: [Color(0xFFB4C5F9), Color(0xFF574B99), Color(0xFF172D54)],
    ).createShader(Rect.fromLTWH(pole.dx, pole.dy, width, height)));
    final text = TextPainter(text: TextSpan(text: 'SOVERA', style: TextStyle(
      color: const Color(0xFFFFE7AD), fontSize: width * .16,
      fontWeight: FontWeight.w800, letterSpacing: width * .018,
    )), textDirection: TextDirection.ltr)..layout(maxWidth: width);
    text.paint(canvas, Offset(pole.dx + (width-text.width)/2,
      pole.dy + (height-text.height)/2 + wave(.5)));
  }
  @override
  bool shouldRepaint(CastleFlagPainter oldDelegate) => phase != oldDelegate.phase;
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
