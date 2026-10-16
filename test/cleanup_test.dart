import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';

void main(){
 testWidgets('Profile can save an empty bio',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Home()));await tester.pumpAndSettle();
  await tester.tap(find.text('Me'));await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Edit profile'));await tester.pumpAndSettle();
  await tester.tap(find.text('Edit profile'));await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField),'Updated guest');await tester.tap(find.text('Save'));await tester.pump(const Duration(milliseconds:400));await tester.pumpAndSettle();
  expect(find.text('Bio'),findsOneWidget);await tester.tap(find.text('Save'));await tester.pump(const Duration(milliseconds:400));await tester.pumpAndSettle();
  expect(find.byType(AlertDialog),findsNothing);expect(find.text('Updated guest'),findsOneWidget);
 });
 testWidgets('Search clears and New orders the room previews',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Home()));await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField),'missing');await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Clear room search'));await tester.pumpAndSettle();
  expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,isEmpty);
  await tester.scrollUntilVisible(find.text('New'),250,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('New'));await tester.pumpAndSettle();
  expect(tester.getTopLeft(find.text('Sovera Studio')).dy,lessThan(tester.getTopLeft(find.text('Moonlight Lounge')).dy));
  expect(find.text('Popular'),findsNothing);
 });
 testWidgets('Gift preview does not show a fake balance or sending control',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:VoiceRoom(name:'Preview')));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Preview gifts'));await tester.pumpAndSettle();
  expect(find.text('0 Coins'),findsNothing);expect(find.text('Send'),findsNothing);expect(find.text('Exclusive'),findsNothing);
  await tester.tap(find.text('Heart'));await tester.pumpAndSettle();await tester.tap(find.text('View selection'));await tester.pumpAndSettle();
  expect(find.text('Heart preview'),findsOneWidget);expect(find.byType(AlertDialog),findsOneWidget);
 });
 testWidgets('Room and Events work on compact screens with large text',(tester)async{
  tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  Widget app(Widget page)=>MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:page);
  await tester.pumpWidget(app(const Events()));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  await tester.pumpWidget(app(const VoiceRoom(name:'A long room name for compact screens')));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  await tester.tap(find.byTooltip('Preview gifts'));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
 });
 testWidgets('Export cleaned room and gift screen',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final key=GlobalKey();await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),home:const VoiceRoom(name:'Sovera Lounge'))));await tester.pumpAndSettle();
  for(final name in ['room-cleanup','gifts-cleanup']){
   if(name=='gifts-cleanup'){await tester.tap(find.byTooltip('Preview gifts'));await tester.pumpAndSettle();}
   await tester.runAsync(()async{final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('build/design-review').create(recursive:true);await File('build/design-review/$name.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
  }
 });
}
