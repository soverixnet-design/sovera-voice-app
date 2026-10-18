import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/effects_studio.dart';
void main(){
 testWidgets('Frame nameplates update with the wearer name',(tester)async{
  final old=effectProfileName.value;addTearDown(()=>effectProfileName.value=old);effectProfileName.value='Shakil';
  final pack=effectPacks.firstWhere((p)=>p.name=='Crown Violet');
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:EffectPortrait(pack:pack,child:const Text('Avatar'))))));await tester.pump();expect(find.text('Shakil'),findsOneWidget);
  effectProfileName.value='Ruman';await tester.pump();expect(find.text('Ruman'),findsOneWidget);expect(find.text('Shakil'),findsNothing);expect(tester.takeException(),isNull);
 });
 test('Five imported frames and two nameplates have accessibility stills',(){
  expect(effectPacks.length,19);
  for(final name in ['Crown Violet','Royal Horses','Solar Crown','Sunrise Crown','Rose Crown']){final p=effectPacks.firstWhere((p)=>p.name==name);expect(p.stillAsset,isNotNull);}
  expect(effectPacks.firstWhere((p)=>p.name=='Ice Dragon').entryDurationMs,4500);
 });
 testWidgets('Room arrival includes the user name and keeps the full ice clip',(tester)async{
  final old=effectProfileName.value;addTearDown(()=>effectProfileName.value=old);effectProfileName.value='Shakil';
  final pack=effectPacks.firstWhere((p)=>p.name=='Ice Dragon');
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>TextButton(onPressed:()=>showEntryPreview(context,pack),child:const Text('Play')))));
  await tester.tap(find.text('Play'));await tester.pump();await tester.pump(const Duration(seconds:3));expect(find.text('Shakil'),findsOneWidget);expect(find.byTooltip('Close entry preview'),findsOneWidget);await tester.pump(const Duration(seconds:2));await tester.pumpAndSettle();expect(find.byTooltip('Close entry preview'),findsNothing);
 });
}
