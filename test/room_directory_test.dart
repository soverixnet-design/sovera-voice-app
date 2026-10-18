import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/room_card.dart';
import 'package:sovera/country_picker.dart';

void main(){
 testWidgets('Room directory shows country, listener count and opens room',(tester)async{
  var opened=false;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:180,height:300,child:RoomCard(name:'My room',country:'BD',memberCount:12,category:'Music',subtitle:'9 seats · Live voice',onOpen:()=>opened=true,onFollow:null)))));
  await tester.pumpAndSettle();
  expect(find.text('🇧🇩 My room'),findsOneWidget);expect(find.text('12'),findsOneWidget);
  await tester.tap(find.text('🇧🇩 My room'));expect(opened,true);expect(tester.takeException(),isNull);
 });
 testWidgets('Country search returns the selected country code',(tester)async{
  String? selected;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CountryPicker(value:'',onChanged:(value)=>selected=value))));
  await tester.tap(find.text('Choose your country'));await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField),'Oman');await tester.pumpAndSettle();
  await tester.tap(find.text('Oman'));await tester.pumpAndSettle();expect(selected,'OM');
 });
}
