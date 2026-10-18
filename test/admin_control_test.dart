import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/admin_control.dart';
void main(){
 testWidgets('VIP ID has its own badge and is not a main ID',(tester)async{
 await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Column(children:[Text('User ID · 10000001'),VipIdentityBadge(value:'7')]))));
 expect(find.text('User ID · 10000001'),findsOneWidget);expect(find.text('♛ VIP ID · 7'),findsOneWidget);
 });
 testWidgets('Unassigned VIP ID does not invent a badge',(tester)async{
 await tester.pumpWidget(const MaterialApp(home:Scaffold(body:VipIdentityBadge())));expect(find.byType(Text),findsNothing);
 });
 testWidgets('Admin code screen fits a compact large-text phone',(tester)async{
 tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:const AdminControlPage()));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.text('Generate one-time code'),180,scrollable:find.byType(Scrollable).first);expect(tester.takeException(),isNull);expect(find.text('Generate one-time code'),findsOneWidget);
 });
}
