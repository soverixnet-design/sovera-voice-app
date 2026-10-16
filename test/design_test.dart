import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';
import 'package:sovera/room_card.dart';

void main(){
 testWidgets('Room card separates following from room entry', (tester)async{
  var opened=0,followed=0;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:170,height:270,child:RoomCard(name:'A long community room name',category:'Music',subtitle:'9 seats · Voice coming soon',onOpen:()=>opened++,onFollow:()=>followed++)))));
  await tester.tap(find.byTooltip('Follow room'));
  expect(followed,1);expect(opened,0);
  await tester.tap(find.text('Explore room'));
  expect(opened,1);
  expect(tester.takeException(),isNull);
 });
 testWidgets('Compact home and large text do not overflow', (tester)async{
  tester.view.physicalSize=const Size(320,740);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:const Home()));
  await tester.pumpAndSettle();
  expect(tester.takeException(),isNull);
  await tester.drag(find.byType(Scrollable).first,const Offset(0,-600));await tester.pumpAndSettle();
  expect(tester.takeException(),isNull);
 });
 testWidgets('Export home design for visual review', (tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:const Sovera(preview:true)));
  await tester.pumpAndSettle();
  await tester.runAsync(()async{
   final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
   final image=await boundary.toImage(pixelRatio:2);
   final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
   await Directory('build/design-review').create(recursive:true);
   await File('build/design-review/home.png').writeAsBytes(bytes!.buffer.asUint8List());
   image.dispose();
  });
  expect(tester.takeException(),isNull);
 });
}
