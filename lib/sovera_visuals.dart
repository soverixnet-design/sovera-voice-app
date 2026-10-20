// Exact original Sovera UI primitives, separate from old Supabase app runtime.
// Firebase is used for identity only; all user content comes from Sovera server.
import 'package:flutter/material.dart';

const violet = Color(0xFF9268F4);
const gold = Color(0xFFECC58A);
const pink = Color(0xFFFF69B4);
const ink = Color(0xFF12172D);
const cyan = Color(0xFF71E5E6);

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 56});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sovera logo',
    image: true,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: cyan.withValues(alpha: .12), blurRadius: size*.38),
          BoxShadow(color: violet.withValues(alpha: .10), blurRadius: size*.55),
        ],
      ),
      child: Image.asset('assets/sovera-logo-transparent.png',
        width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.high),
    ),
  );
}
class Glass extends StatelessWidget {
  final Widget child;
  final Color tint;
  final EdgeInsets padding;
  const Glass({super.key, required this.child, this.tint = violet, this.padding = const EdgeInsets.all(18)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .22), const Color(0xFF17223A), const Color(0xFF10172C)]),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
      boxShadow: [BoxShadow(color: tint.withValues(alpha: .12), blurRadius: 24, offset: const Offset(0, 12))],
    ), child: child,
  );
}

class Jewel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const Jewel(this.icon, {super.key, this.color = violet, this.size = 54});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * .32),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, .45)!, color, Color.lerp(color, Colors.black, .4)!]),
      border: Border.all(color: Colors.white.withValues(alpha: .32)),
      boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 16, offset: const Offset(0, 7))]),
    child: Icon(icon, color: Colors.white, size: size * .49),
  );
}

