import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/compact_gifts.dart';
import 'package:sovera/effects_studio.dart';

void main() {
  testWidgets('compact sheet shows prices and returns the exact selected occupant', (tester) async {
    GiftSeatSelection? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async { result = await showModalBottomSheet<GiftSeatSelection>(context: context,
        isScrollControlled: true, builder: (_) => const CompactGiftSheet(recipients: {0: 'alice', 2: 'bob'})); },
      child: const Text('Open gifts'))))));
    await tester.tap(find.text('Open gifts'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CompactGiftSheet)).height, lessThanOrEqualTo(400));
    expect(find.text('10 coins'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Preview to seat');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.text('Heart'));
    await tester.tap(find.text('Seat 3'));
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result?.gift.id, 'heart');
    expect(result?.seat, 2);
    expect(result?.userId, 'bob');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('applied frame preserves the requested portrait diameter', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(disableAnimations: true),
      child: Center(child: EffectPortrait(pack: effectPacks.first, size: 170, portraitSize: 100,
        child: const SizedBox(width: 100, height: 100))))));
    await tester.pump();
    expect(tester.getSize(find.byType(ClipOval).first), const Size(100, 100));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
