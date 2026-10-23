import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_room_rewards.dart';
void main(){
 testWidgets('Room rewards show real gift totals, shares and contributor IDs',(tester)async{
  final api=FirebaseProfileApi(uid:'owner',token:()async=>'token',client:MockClient((r)async=>http.Response(jsonEncode({'current':{'percent':10,'gift_coins':'100000','reward_coins':'10000','ends_at':1800000000,'allocations':[{'uid':'owner','name':'Room owner','public_id':'100001','coins':'5000'}],'contributors':[{'uid':'alice','name':'Alice','public_id':'100002','score':'20000'}]},'history':[]}),200)));
  await tester.pumpWidget(MaterialApp(home:FirebaseRoomRewards(api:api,roomId:'room')));await tester.pumpAndSettle();
  expect(find.text('Gift Coins: 100000'),findsOneWidget);expect(find.text('5000 Coins'),findsOneWidget);expect(find.text('ID 100002'),findsOneWidget);expect(tester.takeException(),isNull);
 });
}
