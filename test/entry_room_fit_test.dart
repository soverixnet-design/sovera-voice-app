import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';
import 'package:sovera/effects_studio.dart';

void main(){
 testWidgets('Room arrivals blend over the visible room on compact and tall screens',(tester)async{
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);tester.view.devicePixelRatio=1;
  await tester.runAsync(()async{await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();});
  for(final width in [320.0,390.0]){
   tester.view.physicalSize=Size(width,844);
   final key=GlobalKey();final pack=effectPacks.firstWhere((p)=>p.name=='Tiger Queen');
   await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(disableAnimations:true,textScaler:TextScaler.linear(width==320?1.5:1)),child:child!),home:const VoiceRoom(name:'Sovera Sapphire'))));await tester.pumpAndSettle();
   final context=tester.element(find.byType(VoiceRoom));await tester.runAsync(()=>precacheImage(AssetImage(pack.entryStillAsset!),context));
   showEntryPreview(context,pack);await tester.pump();await tester.pump(const Duration(milliseconds:300));
   final barrier=tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last;expect(barrier.color,anyOf(isNull,Colors.transparent));
   expect(find.byKey(const ValueKey('arrival-edge-blend')),findsOneWidget);expect(tester.takeException(),isNull);
   await tester.runAsync(()async{final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('build/design-review').create(recursive:true);await File('build/design-review/entry-room-fit-${width.toInt()}.png').writeAsBytes(data!.buffer.asUint8List());image.dispose();});
   await tester.tap(find.byTooltip('Close entry preview'));await tester.pumpAndSettle();expect(find.text('Sovera Sapphire'),findsOneWidget);
  }
 });
}
