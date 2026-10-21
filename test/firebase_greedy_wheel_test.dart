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
    expect(find.text('Greedy Wheel · Same live round'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
