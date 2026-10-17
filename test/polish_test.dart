import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';
import 'package:sovera/member_directory.dart';
import 'package:sovera/role_styles.dart';
import 'package:sovera/seat_link.dart';
import 'package:sovera/effects_studio.dart';
import 'package:sovera/room_visuals.dart';

class FakeMembers extends MemberStore{
 bool visible=false;Set<String> saved={};
 @override Future<Map<String,dynamic>?> ownCard(String id)async=>{'listed':visible};
 @override Future<Set<String>> following(String id)async=>{...saved};
 @override Future<List<Map<String,dynamic>>> members(String own,String query,int offset)async=>[{'user_id':'other','uid':100002,'display_name':'Member fixture'}];
 @override Future<void> publish(Map<String,dynamic> profile,bool listed)async{visible=listed;}
 @override Future<void> follow(String own,String target,bool value)async{value?saved.add(target):saved.remove(target);}
}
void main(){
 testWidgets('Equipped seat frame uses the full circle and keeps mute below it',(tester)async{
  previewAvatarFrame.value=effectPacks[4];addTearDown(()=>previewAvatarFrame.value=null);
  await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(disableAnimations:true),child:const Scaffold(body:Center(child:RoomSeatAvatar(occupied:true,muted:true))))));
  await tester.pumpAndSettle();
  expect(tester.getSize(find.byType(EffectPortrait)),const Size(88,88));
  final frame=tester.getRect(find.byType(EffectPortrait));final badge=tester.getRect(find.byKey(const ValueKey('muted-seat-badge')));
  expect(badge.bottom,greaterThan(frame.bottom));expect(tester.takeException(),isNull);
 });

 setUp((){minimizedRoom.value=null;previewRoleStyles.value={};});
 tearDown((){minimizedRoom.value=null;previewRoleStyles.value={};});
 testWidgets('Own mute badge toggles and minimizing preserves the seat',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Home()));await tester.pumpAndSettle();
  tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(builder:(_)=>const VoiceRoom(name:'Preserved room')));await tester.pumpAndSettle();
  await tester.tap(find.text('1'));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('muted-seat-badge')),findsOneWidget);
  await tester.tap(find.byTooltip('Unmute preview'));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('muted-seat-badge')),findsNothing);
  await tester.tap(find.byTooltip('Minimize room'));await tester.pumpAndSettle();expect(minimizedRoom.value?.mySeat,0);expect(minimizedRoom.value?.muted,isFalse);
  await tester.tap(find.text('Return to room'));await tester.pumpAndSettle();expect(find.text('You'),findsOneWidget);expect(find.byTooltip('Mute preview'),findsOneWidget);
  await tester.tap(find.byTooltip('Mute preview'));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('muted-seat-badge')),findsOneWidget);
  await tester.tap(find.byTooltip('Leave room'));await tester.pumpAndSettle();expect(find.byType(VoiceRoom),findsNothing);
 });
 testWidgets('Follow and unfollow persist only after store success',(tester)async{
  final store=FakeMembers();await tester.pumpWidget(MaterialApp(home:MemberDirectory(profile:const {'id':'own','uid':100001,'display_name':'Owner fixture'},store:store)));await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Follow'));await tester.pumpAndSettle();await tester.tap(find.text('Follow'));await tester.pumpAndSettle();expect(store.saved,contains('other'));expect(find.text('Unfollow'),findsOneWidget);
  await tester.tap(find.text('Unfollow'));await tester.pumpAndSettle();expect(store.saved,isEmpty);
  await tester.ensureVisible(find.byType(SwitchListTile));await tester.pumpAndSettle();await tester.tap(find.byType(Switch));await tester.pumpAndSettle();expect(store.visible,isTrue);
 });
 testWidgets('Role designs are local cosmetic choices',(tester)async{
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(useMaterial3:true),home:const RoleMedalCollection()));await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Show below levels').first);await tester.pumpAndSettle();await tester.tap(find.text('Show below levels').first);await tester.pumpAndSettle();expect(previewRoleStyles.value,{'manager'});
 });
 testWidgets('Export new room and role designs',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(()async{await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();final file=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');if(await file.exists())await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load();});
  final screens=<String,Widget>{'room-3d-muted':const VoiceRoom(name:'Sovera Sapphire',draft:RoomDraft(name:'Sovera Sapphire',seats:9,mySeat:0,partnerSeat:1,bond:SeatBond.cp,muted:true,messages:[])),'role-medals':Scaffold(appBar:AppBar(title:const Text('Sovera role medal designs')),body:ListView(padding:const EdgeInsets.all(20),children:[const Text('Staff & host collection',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold)),const SizedBox(height:12),const Text('Decorative previews · No staff permission assigned',style:TextStyle(color:Colors.white60)),const SizedBox(height:24),Wrap(spacing:8,runSpacing:24,alignment:WrapAlignment.center,children:[for(final style in roleStyles)RoleMedallion(style:style,width:106)])]))};
  previewAvatarFrame.value=effectPacks[4];addTearDown(()=>previewAvatarFrame.value=null);
  for(final screen in screens.entries){final key=GlobalKey();await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),home:MediaQuery(data:const MediaQueryData(disableAnimations:true),child:screen.value))));await tester.pumpAndSettle();expect(tester.takeException(),isNull);await tester.runAsync(()async{final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('build/design-review').create(recursive:true);await File('build/design-review/${screen.key}.png').writeAsBytes(data!.buffer.asUint8List());image.dispose();});}
 });
}
