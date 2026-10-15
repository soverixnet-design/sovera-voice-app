import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';

void main() {
  testWidgets('Compact home opens future Games collection without layout errors', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const Sovera());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Games').first);
    await tester.tap(find.text('Games').first);
    await tester.pumpAndSettle();
    expect(find.byType(GamesHub), findsOneWidget);
    expect(find.textContaining('Games will be added later'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
