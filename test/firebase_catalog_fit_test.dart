import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/firebase_catalog.dart';
import 'package:sovera/firebase_voice.dart';

Map<String,dynamic> art(String kind)=>{
  'id':'$kind-id','kind':kind,'media_id':'version-1',
  'url':'https://example.invalid/$kind.png',
  'avatar_scale':.46,'avatar_x':.5,'avatar_y':.5,
};
Map<String,dynamic> person(String uid)=>{
  'uid':uid,'name':uid,'avatar_url':null,
  'equipped':{'frame':art('frame'),'entry':art('entry')},
};
Finder artwork(String kind)=>find.byWidgetPredicate(
  (w)=>w is CatalogPortrait&&w.asset?['kind']==kind);

void main(){
  test('profile and seat preserve the same normalized avatar geometry',(){
    final profile=CatalogPortraitGeometry.forAsset(art('frame'),242);
    final seat=CatalogPortraitGeometry.forAsset(art('frame'),58);
    expect(profile.avatar.width/242,closeTo(seat.avatar.width/58,1e-10));
    expect(profile.avatar.center.dx/242,closeTo(seat.avatar.center.dx/58,1e-10));
    expect(profile.avatar.center.dy/242,closeTo(seat.avatar.center.dy/58,1e-10));
    final edge=CatalogPortraitGeometry.forAsset({
      'avatar_scale':.8,'avatar_x':.2,'avatar_y':.8},58);
    expect(edge.avatar.left,greaterThanOrEqualTo(-1e-8));
    expect(edge.avatar.top,greaterThanOrEqualTo(-1e-8));
    expect(edge.avatar.right,lessThanOrEqualTo(58+1e-8));
    expect(edge.avatar.bottom,lessThanOrEqualTo(58+1e-8));
  });
  testWidgets('a large profile portrait shrinks into a narrow square without cropping',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(
      child:SizedBox(width:52,height:52,child:CatalogPortrait(asset:art('frame'),size:242))))));
    await tester.pumpAndSettle();
    final canvas=tester.getRect(find.byKey(const ValueKey('catalog-canvas')));
    final avatar=tester.getRect(find.byKey(const ValueKey('catalog-avatar')));
    expect(canvas.size,const Size(52,52));
    expect(avatar.width,closeTo(52*.46,.01));
    expect(avatar.center.dx,closeTo(canvas.center.dx,.01));
    expect(avatar.center.dy,closeTo(canvas.center.dy,.01));
    expect(tester.takeException(),isNull);
  });
  testWidgets('seat frame uses the full seat canvas and entry does not replay on heartbeat',(tester)async{
    Future<void> show(String uid)=>tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(
      child:FirebaseSeatPortrait(uid:uid,person:person(uid),size:72)))));
    await show('alice');
    expect(artwork('entry'),findsOneWidget);
    await tester.pump(const Duration(milliseconds:3201));
    await tester.pumpAndSettle();
    expect(artwork('entry'),findsNothing);
    expect(artwork('frame'),findsOneWidget);
    expect(tester.getSize(artwork('frame')),const Size(72,72));
    await show('alice');
    await tester.pump(const Duration(milliseconds:500));
    expect(artwork('entry'),findsNothing);
    await show('bob');
    expect(artwork('entry'),findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home:SizedBox.shrink()));
    await tester.pump(const Duration(seconds:5));
    expect(tester.takeException(),isNull);
  });
  testWidgets('late member details play entry once after an occupied seat is identified',(tester)async{
    Widget tile(Map<String,dynamic>? value)=>MaterialApp(home:Scaffold(body:Center(
      child:FirebaseSeatPortrait(uid:'alice',person:value,size:58))));
    await tester.pumpWidget(tile(null));
    expect(artwork('entry'),findsNothing);
    await tester.pumpWidget(tile(person('alice')));
    expect(artwork('entry'),findsOneWidget);
    await tester.pump(const Duration(milliseconds:3201));
    await tester.pumpAndSettle();
    await tester.pumpWidget(tile(person('alice')));
    expect(artwork('entry'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
