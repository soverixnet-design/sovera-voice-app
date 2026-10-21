import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_programs.dart';
void main(){
 testWidgets('membership requires explicit confirmation before spending Coins',(tester)async{
  SharedPreferences.setMockInitialValues({});var buys=0;
  final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{
   if(r.url.path.endsWith('/buy')){buys++;return http.Response('{"saved":true}',200);}
   if(r.url.path.endsWith('/programs'))return http.Response(jsonEncode({'items':[{'id':'offer','kind':'vip','title':'VIP One','coins':5,'days':7,'level':1,'item_ids':[]}],'membership':null}),200);
   return http.Response('{"items":[]}',200);
  }));
  await tester.pumpWidget(MaterialApp(home:FirebaseProgramsPage(api:api)));await tester.pumpAndSettle();
  await tester.tap(find.text('Review membership'));await tester.pumpAndSettle();expect(buys,0);
  await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(buys,0);
  await tester.tap(find.text('Review membership'));await tester.pumpAndSettle();await tester.tap(find.text('Confirm purchase'));await tester.pumpAndSettle();expect(buys,1);expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox.shrink());api.client.close();
 });
 testWidgets('unconfirmed request resolves on server before allowing another purchase',(tester)async{
  SharedPreferences.setMockInitialValues({'sovera.programs.pending.alice':jsonEncode({'type':'buy','fields':{'request_id':'pending-id','item_id':'offer','expected_coins':5}})});var cancels=0;
  final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{
   if(r.url.path.contains('/cancel/')){cancels++;return http.Response('{"applied":false}',200);}
   return http.Response('{"items":[],"membership":null}',200);
  }));
  await tester.pumpWidget(MaterialApp(home:FirebaseProgramsPage(api:api)));await tester.pumpAndSettle();await tester.tap(find.text('Resolve / cancel this request'));await tester.pumpAndSettle();expect(cancels,1);expect(find.text('Retry same request'),findsNothing);expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox.shrink());api.client.close();
 });
}
