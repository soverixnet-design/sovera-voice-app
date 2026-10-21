import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_greedy_wheel.dart';
import 'package:sovera/firebase_profile.dart';

void main(){
  testWidgets('Greedy is fail-closed without a verified server wallet',(tester)async{
    var called=false;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'secret-firebase-token',
      client:MockClient((request)async{
        if(request.url.path.endsWith('/rankings')){
          expect(request.method,'GET');
          expect(request.url.queryParameters,{'metric':'play','period':'daily'});
          return http.Response('{"mine":{"score":"75000"},"items":[],"server_now":1,"ends_at":86400}',200);
        }
        called=true;
        expect(request.method,'POST');
        expect(request.url.path,endsWith('/sovera/account/greedy/access'));
        expect(request.headers['Authorization'],'Bearer secret-firebase-token');
        return http.Response('{"detail":"Greedy game is not active yet"}',503);
      }));
    await tester.pumpWidget(MaterialApp(home:FirebaseGreedyWheelPage(api:api)));
    await tester.pumpAndSettle();
    expect(called,isTrue);
    expect(find.textContaining('No fake coins or bets'),findsOneWidget);
    expect(find.text('Retry secure connection'),findsOneWidget);
    expect(find.text('Greedy Wheel'),findsOneWidget);
    expect(find.text("Today's total wins · 75000 Coins"),findsOneWidget);
    expect(find.byTooltip('Game wins ranking'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
