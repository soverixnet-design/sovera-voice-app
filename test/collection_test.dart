import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/account_cards.dart';
import 'package:sovera/effects_studio.dart';
import 'package:sovera/medal_collection.dart';

Widget still(Widget screen)=>MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(disableAnimations:true),child:child!),home:screen);
void main(){
 setUp(resetCosmeticPreviews);tearDown(resetCosmeticPreviews);
 testWidgets('All ten themes and original entry assets are bundled',(tester)async{
  expect(effectPacks.length,10);
  expect(effectPacks.map((p)=>p.name),containsAll(['Royal Gold','Violet Love','Ice Admin','Golden Dragon','Ice Dragon','Violet Phoenix']));
  for(final pack in effectPacks){for(final asset in [pack.asset,pack.stillAsset,pack.entryAsset,pack.entryStillAsset].whereType<String>()){expect((await rootBundle.load(asset)).lengthInBytes,greaterThan(0));}}
  await tester.pumpWidget(still(const EffectsStudio()));await tester.pumpAndSettle();
  await tester.tap(find.text('Browse all 10 themes'));await tester.pumpAndSettle();
  expect(find.text('Royal Gold'),findsWidgets);
 });
 testWidgets('Chosen medals appear below ID and levels',(tester)async{
  previewRankingMedals.value={'gold','silver','bronze'};
  await tester.pumpWidget(still(Scaffold(body:SingleChildScrollView(child:ProfileIdentityCard(name:'Sovera member',bio:'',onEdit:(){})))));await tester.pumpAndSettle();
  expect(tester.getTopLeft(find.text('Medals')).dy,greaterThan(tester.getBottomLeft(find.text('VIP')).dy));
  expect(tester.getTopLeft(find.text('VIP')).dy,greaterThan(tester.getTopLeft(find.text('ID · Sign in to receive your ID')).dy));
  expect(find.bySemanticsLabel('gold medal preview'),findsOneWidget);
 });
 testWidgets('Ranking medals can be chosen and cleared',(tester)async{
  await tester.pumpWidget(still(const MedalCollection()));await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Show below levels').first);await tester.pumpAndSettle();await tester.tap(find.text('Show below levels').first);await tester.pumpAndSettle();
  expect(previewRankingMedals.value,contains('gold'));resetCosmeticPreviews();await tester.pump();expect(previewRankingMedals.value,isEmpty);
 });
 testWidgets('Export profile medal placement',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(()async{await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');if(await font.exists())await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())))).load();});
  previewRankingMedals.value={'gold','silver','bronze'};previewAvatarFrame.value=effectPacks[8];
  final key=GlobalKey();await tester.pumpWidget(RepaintBoundary(key:key,child:still(Scaffold(appBar:AppBar(title:const Text('My profile')),body:SingleChildScrollView(padding:const EdgeInsets.all(20),child:ProfileIdentityCard(name:'Sovera member',bio:'',onEdit:(){}))))));await tester.pumpAndSettle();
  await tester.runAsync(()async{final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('build/design-review').create(recursive:true);await File('build/design-review/profile-medals.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
  expect(tester.takeException(),isNull);
 });
}
