import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/account_cards.dart';
import 'package:sovera/main.dart';

void main(){
 testWidgets('Guest identity shows no invented ID or level and supports large text',(tester)async{
  tester.view.physicalSize=const Size(320,740);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  var edits=0;
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:Scaffold(body:SingleChildScrollView(child:ProfileIdentityCard(name:'Sovera community member',bio:'A profile introduction',onEdit:()=>edits++)))));
  await tester.pumpAndSettle();
  expect(find.text('Lv. —'),findsNWidgets(3));
  expect(find.byTooltip('Copy user ID'),findsNothing);
  expect(tester.takeException(),isNull);
  await tester.ensureVisible(find.text('Edit profile'));
  await tester.tap(find.text('Edit profile'));expect(edits,1);
 });
 testWidgets('Reseller preview does not allow unverified application or recharge',(tester)async{
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:const ResellerCenter()));
  await tester.pumpAndSettle();
  expect(find.text('Sign in to apply for reseller access.'),findsOneWidget);
  expect(find.text('Submit application'),findsNothing);
  expect(find.text('No reseller access assigned'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
 testWidgets('Profile opens reseller center from the home navigation',(tester)async{
  await tester.pumpWidget(const Sovera(preview:true));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Me'));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Reseller center'),250,scrollable:find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(find.text('Reseller center')),alignment:0.35);await tester.pumpAndSettle();await tester.tap(find.text('Reseller center'));await tester.pumpAndSettle();
  expect(find.text('Grow with Sovera'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
}
