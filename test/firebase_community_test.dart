import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_community.dart';
import 'package:sovera/firebase_profile.dart';

void main(){
  testWidgets('support only confirms after server success and reuses retry identity',(tester)async{
    final requests=<Map<String,dynamic>>[];
    final client=MockClient((request)async{
      expect(request.headers['Authorization'],'Bearer session');
      if(request.method=='GET')return http.Response('{"items":[]}',200);
      requests.add(jsonDecode(request.body) as Map<String,dynamic>);
      return requests.length==1?http.Response('{}',503):http.Response('{"saved":true}',200);
    });
    addTearDown(client.close);
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'session',client:client);
    await tester.pumpWidget(MaterialApp(home:FirebaseCommunity(api:api,section:'support',title:'Official support')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Please check my room audio');
    await tester.tap(find.text('Send to support'));await tester.pumpAndSettle();
    expect(find.text('Message sent to support.'),findsNothing);
    expect(find.text('Retry send'),findsOneWidget);
    await tester.tap(find.text('Retry send'));await tester.pumpAndSettle();
    expect(requests.length,2);
    expect(requests[0]['request_id'],requests[1]['request_id']);
    expect(requests[0]['text'],'Please check my room audio');
    expect(find.text('Message sent to support.'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('official publications render server content and expose no publish action',(tester)async{
    final client=MockClient((request)async=>http.Response(jsonEncode({'items':[
      {'id':1,'title':'Community gathering','text':'Meet in the official room','created_at':1000},
    ]}),200));
    addTearDown(client.close);
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'session',client:client);
    await tester.pumpWidget(MaterialApp(home:FirebaseCommunity(api:api,section:'events',title:'Community events')));
    await tester.pumpAndSettle();
    expect(find.text('Community gathering'),findsOneWidget);
    expect(find.text('Meet in the official room'),findsOneWidget);
    expect(find.byType(TextField),findsNothing);
    expect(find.text('Publish'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
