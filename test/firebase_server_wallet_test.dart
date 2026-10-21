import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_server_wallet.dart';

void main(){
  test('history cursor stays in query and bearer token stays on trusted host',()async{
    final client=MockClient((request)async{
      expect(request.url.host,'voice.soverixnet.com');
      expect(request.url.path,'/sovera/account/wallet/history');
      expect(request.url.queryParameters,{'before_time':'1000','before_ref':'win/a+b'});
      expect(request.headers['Authorization'],'Bearer verified');
      return http.Response('{"entries":[],"has_more":false}',200);
    });
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'verified',client:client);
    await api.call('GET',suffix:'/wallet/history?before_time=1000&before_ref=win%2Fa%2Bb');
    client.close();
  });

  testWidgets('Firebase only authenticates; unavailable server wallet never fakes zero',
    (tester)async{
      final calls=<String>[];
      final client=MockClient((request)async{
        calls.add(request.url.path);
        expect(request.method,'GET');
        expect(request.headers['Authorization'],'Bearer alice-firebase-id');
        expect(request.url.host,'voice.soverixnet.com');
        return http.Response(jsonEncode({
          'status':'not_migrated','verified':false,
          'coins':null,'diamonds':null,'canSpend':false,'source':'sovera-server',
        }),200);
      });
      final api=FirebaseProfileApi(uid:'alice',token:()async=>'alice-firebase-id',client:client);
      await tester.pumpWidget(MaterialApp(home:FirebaseServerWalletPage(api:api)));
      await tester.pumpAndSettle();
      expect(find.text('My Sovera Wallet'),findsOneWidget);
      expect(find.textContaining('No balance has been reset'),findsOneWidget);
      expect(find.text('0'),findsNothing);
      expect(find.textContaining('Wallet verified'),findsNothing);
      expect(calls,['/sovera/account/wallet']);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
  testWidgets('display only real signed-in server ledger, never fake client balances',
    (tester)async{
      final calls=<String>[];
      final client=MockClient((request)async{
        calls.add(request.url.path);
        expect(request.headers['Authorization'],'Bearer verified');
        if(request.url.path.endsWith('/history')){
          return http.Response(jsonEncode({'entries':[{
            'reference':'trusted-import-1','kind':'verified_import',
            'coin_delta':12345,'diamond_delta':70,'created_at':1000,
          }]}),200);
        }
        return http.Response(jsonEncode({
          'status':'active','verified':true,
          'coins':'12345','diamonds':'70','canSpend':false,'source':'sovera-server',
        }),200);
      });
      final api=FirebaseProfileApi(uid:'alice',token:()async=>'verified',client:client);
      await tester.pumpWidget(MaterialApp(home:FirebaseServerWalletPage(api:api)));
      await tester.pumpAndSettle();
      expect(find.text('12,345'),findsOneWidget);
      expect(find.text('70'),findsOneWidget);
      expect(find.textContaining('Wallet verified'),findsOneWidget);
      expect(find.textContaining('Coin games are not yet enabled'),findsOneWidget);
      await tester.scrollUntilVisible(find.text('Server transaction history'),200);
      expect(find.text('Server transaction history'),findsOneWidget);
      expect(calls,['/sovera/account/wallet','/sovera/account/wallet/history']);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
}
