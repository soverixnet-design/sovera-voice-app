import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_original_coin_sellers.dart';
import 'package:sovera/firebase_messaging.dart';

void main(){
 testWidgets('Approved seller shows real balance and opens authenticated private chat',(tester)async{
  final api=FirebaseProfileApi(uid:'buyer',token:()async=>'fresh-token',client:MockClient((request)async{
   expect(request.headers['Authorization'],'Bearer fresh-token');
   if(request.url.path.endsWith('/sellers'))return http.Response(jsonEncode({'items':[{'uid':'seller','name':'Approved seller','country':'BD','public_id':'10000002','coins':'111111111','avatar_url':null}]}),200);
   return http.Response(jsonEncode({'person':{'name':'Approved seller'},'blocked':false,'items':[],'has_more':false}),200);
  }));
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:FirebaseOriginalCoinSellers(api:api)));
  await tester.pumpAndSettle();
  expect(find.textContaining('111,111,111 Coins'),findsOneWidget);
  await tester.tap(find.text('Approved seller'));await tester.pumpAndSettle();
  expect(find.byType(FirebaseDirectChat),findsOneWidget);
  expect(find.text('Start a private conversation.'),findsOneWidget);
  await tester.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('Official inbox displays private receipt and published update',(tester)async{
  final api=FirebaseProfileApi(uid:'buyer',token:()async=>'token',client:MockClient((request)async=>http.Response(jsonEncode({'items':[{'title':'Coins received','text':'You received 70 Coins.'},{'title':'App update','text':'New room design'}]}),200)));
  await tester.pumpWidget(MaterialApp(home:FirebaseMessageInbox(api:api,official:true)));
  await tester.pumpAndSettle();
  expect(find.text('You received 70 Coins.'),findsOneWidget);
  expect(find.text('New room design'),findsOneWidget);
 });
}
