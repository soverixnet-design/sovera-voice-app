import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';
import 'package:sovera/social_center.dart';

void main(){
 testWidgets('Friendship uses holding-hands art and request tab has no fabricated users',(tester)async{
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:const SocialCenter()));
  await tester.pumpAndSettle();
  expect(find.byIcon(Icons.handshake_rounded),findsWidgets);
  await tester.scrollUntilVisible(find.text('Requests'),200,scrollable:find.byType(Scrollable).first);
  await tester.tap(find.text('Requests'));await tester.pumpAndSettle();
  expect(find.text('Friend requests will appear here.'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
 testWidgets('CP invitation reports that no request was sent',(tester)async{
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:const SocialCenter(initial:SocialSection.cp)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Invite a CP partner'));
  await tester.tap(find.text('Invite a CP partner'));await tester.pumpAndSettle();
  expect(find.text('Social connections are not connected to the server yet. No request was sent.'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
 testWidgets('Love gift preview changes without inventing points',(tester)async{
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:const SocialCenter(initial:SocialSection.love)));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Rose'),200,scrollable:find.byType(Scrollable).first);
  await tester.tap(find.text('Rose'));await tester.pumpAndSettle();
  expect(find.text('Rose preview'),findsOneWidget);
  expect(find.text('Love points · —'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
 testWidgets('CP layout works at compact width with large text',(tester)async{
  tester.view.physicalSize=const Size(320,740);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:const SocialCenter(initial:SocialSection.cp)));
  await tester.pumpAndSettle();expect(tester.takeException(),isNull);
 });
 testWidgets('Export friendship CP and Love screens for visual review',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(()async{
   await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
   final file=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
   if(await file.exists())await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load();
  });
  for(final section in SocialSection.values){
   final key=GlobalKey();
   await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(theme:ThemeData.dark().copyWith(scaffoldBackgroundColor:ink,colorScheme:const ColorScheme.dark(primary:violet,secondary:cyan)),home:SocialCenter(key:ValueKey(section),initial:section))));
   await tester.pumpAndSettle();
   await tester.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    await Directory('build/design-review').create(recursive:true);
    await File('build/design-review/${section.name}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
   });
   expect(tester.takeException(),isNull);
  }
 });
}
