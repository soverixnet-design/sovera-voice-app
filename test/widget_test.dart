import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';

void main() {
  testWidgets('Room seat layout applies only after Save', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VoiceRoom(name: 'Test room')));
    await tester.tap(find.byTooltip('Seat settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 seats'));
    await tester.tap(find.text('Save seat layout'));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect((grid.childrenDelegate as SliverChildBuilderDelegate).childCount, 5);
  });
}
