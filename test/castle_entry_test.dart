import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/effects_studio.dart';
import 'package:sovera/cosmetic_art.dart';

void main() {
  testWidgets('Castle entry animates a native flag and dismisses after seven seconds', (tester) async {
    final pack = effectPacks.firstWhere((pack) => pack.name == 'Castle Flag');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showEntryPreview(context, pack), child: const Text('Play')),
    ))));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Close entry preview'), findsOneWidget);
    expect(tester.widgetList<CustomPaint>(find.byType(CustomPaint)).any((w) => w.painter is CastleFlagPainter), isTrue);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close entry preview'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
