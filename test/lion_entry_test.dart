import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/effects_studio.dart';

void main() {
 for(final name in ['Phoenix Queen','Tiger Queen']) {
  testWidgets('$name remains visible beyond the old three-second limit',(tester)async {
   final pack=effectPacks.firstWhere((p)=>p.name==name);
   await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showEntryPreview(context,pack),child:const Text('Play'))))));
   await tester.tap(find.text('Play'));await tester.pump();await tester.pump(const Duration(milliseconds:200));await tester.pump(const Duration(seconds:5));
   expect(find.text(name),findsOneWidget);expect(find.bySemanticsLabel('$name room arrival'),findsOneWidget);
   await tester.pump(Duration(milliseconds:pack.entryDurationMs));await tester.pumpAndSettle();expect(find.byTooltip('Close entry preview'),findsNothing);expect(tester.takeException(),isNull);
  });
 }

 testWidgets('Lion Queen arrival keeps the full ten-second clip and can close',(tester) async {
  final pack=effectPacks.firstWhere((p)=>p.name=='Lion Queen');
  expect(pack.name,'Lion Queen');expect(pack.entryDurationMs,10600);
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showEntryPreview(context,pack),child:const Text('Play'))))));
  await tester.tap(find.text('Play'));await tester.pump();await tester.pump(const Duration(milliseconds:200));await tester.pump(const Duration(seconds:5));
  expect(find.byTooltip('Close entry preview'),findsOneWidget);
  await tester.tap(find.byTooltip('Close entry preview'));await tester.pumpAndSettle();
  expect(find.byTooltip('Close entry preview'),findsNothing);expect(tester.takeException(),isNull);
 });
 testWidgets('Reduced motion uses the still and dismisses automatically',(tester) async {
  await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(disableAnimations:true),child:child!),home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showEntryPreview(context,effectPacks.firstWhere((p)=>p.name=='Lion Queen')),child:const Text('Play'))))));
  await tester.tap(find.text('Play'));await tester.pump();await tester.pump(const Duration(milliseconds:200));
  final images=tester.widgetList<Image>(find.byType(Image));expect(images.any((i)=>i.image is AssetImage&&(i.image as AssetImage).assetName=='assets/effects/lion-queen-still.webp'),isTrue);
  await tester.pump(const Duration(seconds:3));await tester.pumpAndSettle();expect(find.byTooltip('Close entry preview'),findsNothing);expect(tester.takeException(),isNull);
 });
}
