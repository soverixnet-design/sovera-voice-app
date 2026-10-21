import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_catalog.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_server_wallet.dart';

void main(){
  testWidgets('gift grid shows artwork and price, and returns chosen recipients',(tester)async{
    Map<String,dynamic>? chosen;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((_)async=>http.Response('{"source":"sovera-server","verified":true,"status":"active","canGift":true,"coins":"111111111"}',200)));
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(
      body:TextButton(onPressed:()async{
        chosen=await showModalBottomSheet<Map<String,dynamic>>(context:context,
          isScrollControlled:true,builder:(_)=>FirebaseCatalogGiftPicker(api:api,
            people:[{'uid':'alice','name':'Alice'},{'uid':'bob','name':'Bob'}],
            gifts:[{'id':'heart','title':'Love Heart','price':10,'url':'https://example.invalid/heart.webp'}]));
      },child:const Text('Open gifts'))))));
    await tester.tap(find.text('Open gifts'));await tester.pumpAndSettle();
    expect(find.text('Your Coins: 111111111'),findsOneWidget);
    expect(find.text('Love Heart'),findsOneWidget);
    expect(find.text('10 Coins'),findsOneWidget);
    expect(find.text('Send room effect'),findsNothing);
    await tester.tap(find.text('Bob'));await tester.pumpAndSettle();
    expect(find.text('Total: 20 Coins'),findsOneWidget);
    await tester.tap(find.text('Send · 2'));await tester.pumpAndSettle();
    expect(chosen,{'item_id':'heart','expected_price':10,'recipient_uids':['alice','bob']});
  });
  testWidgets('gift Coins refresh uses the wallet, blocks overspending and hides failed balances',(tester)async{
    var balance='111111111';var failed=false;var reads=0;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((request)async{
      expect(request.url.path,'/sovera/account/wallet');reads++;
      if(failed)return http.Response('',503);
      return http.Response(jsonEncode({'source':'sovera-server','verified':true,'status':'active','canGift':true,'coins':balance}),200);
    }));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FirebaseCatalogGiftPicker(api:api,
      people:const [{'uid':'alice','name':'Alice'}],gifts:const [{'id':'heart','title':'Heart','price':100,'url':'https://example.invalid/heart.webp'}]))));
    await tester.pumpAndSettle();
    expect(find.text('Your Coins: 111111111'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
    balance='99';await tester.tap(find.byTooltip('Refresh Coins'));await tester.pumpAndSettle();
    expect(find.text('Your Coins: 99'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    failed=true;await tester.tap(find.byTooltip('Refresh Coins'));await tester.pumpAndSettle();
    expect(find.text('Your Coins: 99'),findsNothing);
    expect(find.text('Coins unavailable'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    expect(reads,3);await tester.pumpWidget(const SizedBox());
  });
  testWidgets('exchange confirms fixed rate and refreshes server balances',(tester)async{
    Map<String,dynamic>? sent;
    final client=MockClient((request)async{
      if(request.url.path.endsWith('/exchange')){
        sent=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response('{"saved":true,"coins_received":"210"}',200);
      }
      if(request.url.path.endsWith('/history'))return http.Response('{"entries":[]}',200);
      return http.Response(jsonEncode({'source':'sovera-server','status':'active',
        'verified':true,'canSpend':true,'coins':sent==null?'20':'230',
        'diamonds':sent==null?'500':'200'}),200);
    });
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:client);
    await tester.pumpWidget(MaterialApp(home:FirebaseServerWalletPage(api:api)));await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange Diamonds → Coins'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField),'300');await tester.pumpAndSettle();
    expect(find.text('You receive: 210 Coins'),findsOneWidget);
    await tester.tap(find.text('Confirm exchange'));await tester.pumpAndSettle();
    expect(sent?['diamonds'],300);
    expect(sent?['request_id'],isNotNull);
    expect(sent!.containsKey('uid'),false);
    expect(find.text('230'),findsOneWidget);
    expect(find.text('200'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());client.close();
  });
}
