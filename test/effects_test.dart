import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/effects_studio.dart';

void main() {
 testWidgets('Frame selection can be applied and reset', (tester) async {
  addTearDown(() => previewAvatarFrame.value = null);
  await tester.pumpWidget(const MaterialApp(home:EffectsStudio()));
  await tester.tap(find.text('Ice Wings').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Use frame in preview'));await tester.pumpAndSettle();
  await tester.tap(find.text('Use frame in preview'));
  expect(previewAvatarFrame.value,effectPacks[1]);
  await tester.ensureVisible(find.text('Reset preview styles'));await tester.pumpAndSettle();
  await tester.tap(find.text('Reset preview styles'));
  expect(previewAvatarFrame.value,isNull);
 });
 testWidgets('Entry overlay closes and speaking pulse completes', (tester) async {
  await tester.pumpWidget(const MaterialApp(home:EffectsStudio()));
  await tester.tap(find.text('Entry'));await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Preview entry'));await tester.pumpAndSettle();
  await tester.tap(find.text('Preview entry'));await tester.pump(const Duration(milliseconds:600));
  expect(find.byKey(const ValueKey('arrival-edge-blend')),findsOneWidget);
  await tester.tap(find.byTooltip('Close entry preview'));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Speaking glow'),-200,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();
  await tester.tap(find.text('Speaking glow'));await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Preview speaking glow'));await tester.pumpAndSettle();
  await tester.tap(find.text('Preview speaking glow'));await tester.pumpAndSettle();
  expect(tester.takeException(),isNull);
 });
 testWidgets('Compact effects studio supports large text', (tester) async {
  tester.view.physicalSize=const Size(320,740);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:const EffectsStudio()));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(Scrollable).first,const Offset(0,-600));await tester.pumpAndSettle();
  expect(tester.takeException(),isNull);
 });
 testWidgets('Export effects design', (tester) async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
   await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
   final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
   if(await font.exists()) await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())))).load();
  });
  final key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),home:const EffectsStudio())));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
   final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
   final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
   await Directory('build/design-review').create(recursive:true);
   await File('build/design-review/effects.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
  });
  expect(tester.takeException(),isNull);
 });
}
