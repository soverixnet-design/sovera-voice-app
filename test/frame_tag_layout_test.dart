import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/effects_studio.dart';
import 'package:sovera/cosmetic_art.dart';
import 'package:sovera/account_cards.dart';
import 'package:sovera/main.dart';

Widget screen(Widget child) => MaterialApp(theme:ThemeData.dark(useMaterial3:true),
  home:MediaQuery(data:const MediaQueryData(disableAnimations:true),child:Scaffold(body:child)));

void main() {
 tearDown(() { resetCosmeticPreviews(); effectProfileId.value=''; effectProfileName.value='Sovera guest'; });

 testWidgets('Frame paint fits its reserved layout and does not cover the profile name',(tester)async {
  tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  for(final name in ['Solar Crown','Rose Crown','Royal Horses']) {
   previewAvatarFrame.value=effectPacks.firstWhere((p)=>p.name==name);
   await tester.pumpWidget(screen(SingleChildScrollView(child:ProfileIdentityCard(name:'Visible profile name',bio:'',onEdit:(){}))));
   await tester.pumpAndSettle();
   final frame=tester.getRect(find.byType(EffectPortrait));
   final art=tester.getRect(find.descendant(of:find.byType(EffectPortrait),matching:find.byType(CosmeticArt)).first);
   final label=tester.getRect(find.text('Visible profile name'));
   expect(art.left,greaterThanOrEqualTo(frame.left-.01));
   expect(art.right,lessThanOrEqualTo(frame.right+.01));
   expect(art.bottom,lessThanOrEqualTo(frame.bottom+.01));
   expect(label.top,greaterThanOrEqualTo(frame.bottom));
   expect(tester.takeException(),isNull);
  }
 });

 testWidgets('Small tag keeps name and real ID readable at large text sizes',(tester)async {
  await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(
   disableAnimations:true,textScaler:TextScaler.linear(2)),child:Scaffold(body:Center(child:SizedBox(width:280,
   child:RoomChatBubble(message:RoomChatMessage(text:'Hello room',name:'Shakil',userId:'1075212',tag:effectPacks.last))))))));
  await tester.pumpAndSettle();
  expect(find.text('ID · 1075212'),findsOneWidget);
  expect(tester.getSize(find.byType(CompactCosmeticTag)),const Size(96,28));
  expect(tester.takeException(),isNull);
 });

 testWidgets('Arrival tag expires and sent message retains its selected tag',(tester)async {
  previewNameTag.value=effectPacks.last; effectProfileName.value='Shakil'; effectProfileId.value='1075212';
  await tester.pumpWidget(screen(const VoiceRoom(name:'Tag check')));
  await tester.pumpAndSettle();
  expect(find.text('Joined the room'),findsOneWidget);
  expect(find.text('ID · 1075212'),findsOneWidget);
  await tester.enterText(find.byType(TextField),'Hello everyone');
  await tester.tap(find.byTooltip('Send local message')); await tester.pump();
  final bubble=tester.widget<RoomChatBubble>(find.byType(RoomChatBubble));
  expect(bubble.message.tag,effectPacks.last);
  expect(bubble.message.userId,'1075212');
  previewNameTag.value=null; await tester.pump(const Duration(seconds:7));
  expect(find.text('Joined the room'),findsNothing);
  expect(tester.widget<RoomChatBubble>(find.byType(RoomChatBubble)).message.tag,effectPacks.last);
  await tester.pumpWidget(const SizedBox.shrink());
 });

 testWidgets('Export corrected frame and compact chat review',(tester)async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  previewAvatarFrame.value=effectPacks.last; previewNameTag.value=effectPacks.last;
  effectProfileName.value='Shakil'; effectProfileId.value='1075212';
  final key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:screen(ListView(padding:const EdgeInsets.all(16),children:[
    ProfileIdentityCard(name:'Shakil',bio:'',onEdit:(){}),const SizedBox(height:16),
    CosmeticIdentityLine(name:'Shakil',userId:'1075212',tag:effectPacks.last),
    const SizedBox(height:8),RoomChatBubble(message:RoomChatMessage(text:'Hello everyone',name:'Shakil',userId:'1075212',tag:effectPacks.last)),
  ]))));
  await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  await tester.runAsync(()async {
   final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
   final data=await image.toByteData(format:ui.ImageByteFormat.png);
   await Directory('build/design-review').create(recursive:true);
   await File('build/design-review/frame-tag-fit.png').writeAsBytes(data!.buffer.asUint8List());image.dispose();
  });
 });
}
