import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_rewards.dart';
void main(){
 testWidgets('real podium, period controls and server-qualified reward claim',(tester)async{
  var claimed=false;final paths=<String>[];final now=DateTime.now().millisecondsSinceEpoch~/1000;
  final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{
   paths.add(r.url.toString());
   if(r.method=='POST'){claimed=true;return http.Response('{"saved":true}',200);}
   if(r.url.path.endsWith('rankings'))return http.Response(jsonEncode({'items':[for(var i=1;i<=3;i++){'uid':'user$i','name':'Winner $i','public_id':'10000$i','country':'BD','rank':i,'score':'${4000-i}'}],'server_now':now,'ends_at':now+3600}),200);
   return http.Response(jsonEncode({'server_now':now,'items':[{'id':'campaign','title':'Recharge spotlight','category':'recharge','metric':'recharge','status':'active','starts_at':now-100,'ends_at':now+3600,'threshold':100,'score':'100','eligible':!claimed,'claimed':claimed,'prizes':[{'rank':1,'coins':50,'days':7,'items':[]}],'winners':[]}]}),200);
  }));
  await tester.pumpWidget(MaterialApp(home:FirebaseRewardsPage(api:api)));await tester.pumpAndSettle();
  expect(find.text('Winner 1'),findsOneWidget);expect(find.text('ID 100001'),findsOneWidget);expect(find.text('Daily'),findsOneWidget);
  await tester.tap(find.text('Daily'));await tester.pumpAndSettle();expect(paths.any((p)=>p.contains('period=daily')),isTrue);
  await tester.tap(find.text('Recharge Rewards'));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Claim reward'),300,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('Claim reward'));await tester.pumpAndSettle();
  expect(claimed,isTrue);expect(find.text('✓ Reward received'),findsOneWidget);expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox.shrink());api.client.close();
 });
}
