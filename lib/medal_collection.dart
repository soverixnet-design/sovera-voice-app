import 'package:flutter/material.dart';

/// Bundled artwork previews; ranking awards continue to be server-owned.
class MedalCollection extends StatelessWidget {
  const MedalCollection({super.key});

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sovera medals')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Ranking collection', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Gold, Silver and Bronze · Animated artwork previews'),
          const SizedBox(height: 20),
          for (final medal in const [
            ('gold', 'Gold · Rank 1', Color(0xFFFFD45F)),
            ('silver', 'Silver · Rank 2', Color(0xFF91DCFF)),
            ('bronze', 'Bronze · Rank 3', Color(0xFFFFAB4C)),
          ])
            Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Image.asset(
                    'assets/medals/${medal.$1}.${reducedMotion ? 'png' : 'webp'}',
                    width: 240, height: 240, fit: BoxFit.contain,
                    semanticLabel: '${medal.$2} Sovera medal',
                  ),
                  const SizedBox(height: 12),
                  Text(medal.$2, style: TextStyle(color: medal.$3, fontSize: 21, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
