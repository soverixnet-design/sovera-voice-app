import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';
import 'package:sovera/seat_link.dart';
void main(){
 test('Links only connect neighbours in the same row',(){expect(adjacentSeats(0,1,9),isTrue);expect(adjacentSeats(1,2,9),isTrue);expect(adjacentSeats(2,3,9),isFalse);expect(adjacentSeats(0,2,9),isFalse);expect(adjacentSeats(4,5,5),isFalse);});
 testWidgets('Last seat in a five-seat layout has a valid neighbour',(tester)async{
 await tester.pumpWidget(const MaterialApp(home:VoiceRoom(name:'Five seats',initialSeats:5)));await tester.pumpAndSettle();
 await tester.tap(find.bySemanticsLabel('Seat 5'));await tester.pumpAndSettle();
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
 await tester.tap(find.text('Apply seat preview'));await tester.pumpAndSettle();expect(find.byType(SeatLinkMarker),findsOneWidget);
 });
 testWidgets('Room switches between hand holding and CP heart previews',(tester)async{
 tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 await tester.runAsync(()async{await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');if(await font.exists())await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())))).load();});
 final key=GlobalKey();
 await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),home:const VoiceRoom(name:'Seat preview'))));await tester.pumpAndSettle();
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();await tester.tap(find.text('Apply seat preview'));await tester.pumpAndSettle();expect(find.byTooltip('Friendship holding-hands preview'),findsOneWidget);
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();await tester.tap(find.text('CP Love'));await tester.tap(find.text('Apply seat preview'));await tester.pumpAndSettle();expect(find.byTooltip('CP heart preview'),findsOneWidget);
 await tester.runAsync(()async{final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('build/design-review').create(recursive:true);await File('build/design-review/cp-seats.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();await tester.tap(find.text('Clear seat link'));await tester.pumpAndSettle();expect(find.byType(SeatLinkMarker),findsNothing);expect(tester.takeException(),isNull);
 });
}
