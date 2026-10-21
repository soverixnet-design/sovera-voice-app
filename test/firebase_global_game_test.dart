import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_global_game.dart';

Map<String,dynamic> result({bool revealed=false,String? myPick}){
  return <String,dynamic>{
    'game':'global-colors','round':44,
    'phase':revealed?'reveal':'pick',
    'server_now_ms':1000000,'phase_ends_ms':revealed?1025000:1020000,
    'round_ends_ms':1040000,
    'choices':['red','blue','green','gold'],
    'pick_count':myPick==null?3:4,
    'my_pick':myPick,'result':revealed?'red':null,
    'winner_count':revealed?2:0,
    'winners':revealed?[{'uid':'alice','name':'Shakil'},
      {'uid':'eve','name':'Friend'}]:[],
    'my_win':revealed&&myPick=='red',
    'history':revealed?[{'round':44,'result':'red',
      'winner_count':2,'settled_at_ms':1025000}]:[],
  };
}
void main(){
  testWidgets('shared game submits only round/color and renders server winners',(tester)async{
    Map<String,dynamic>? payload;
    var snapshot=result();
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'verified',
      client:MockClient((request)async{
        expect(request.headers['Authorization'],'Bearer verified');
        if(request.method=='POST'){
          payload=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
          snapshot=result(revealed:true,myPick:'red');
        }
        return http.Response(jsonEncode(snapshot),200);
      }));
    await tester.pumpWidget(MaterialApp(home:FirebaseGlobalColorGame(api:api)));
    await tester.pump(const Duration(milliseconds:120));
    expect(find.text('GLOBAL ROUND #44'),findsOneWidget);
    expect(find.textContaining('WINNING COLOR'),findsNothing);
    await tester.tap(find.text('RED'));
    await tester.pump(const Duration(milliseconds:150));
    expect(payload,{'round':44,'choice':'red'});
    expect(find.text('WINNING COLOR: RED'),findsOneWidget);
    expect(find.text('2 winners this round'),findsOneWidget);
    expect(find.text('Shakil'),findsOneWidget);
    expect(find.textContaining('No Coins are wagered'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('Friend'),200,
      scrollable:find.byType(Scrollable).first);
    expect(find.text('Friend'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a different signed-in spectator sees the same actual global result',(tester)async{
    final data=result(revealed:true,myPick:'blue');
    final api=FirebaseProfileApi(uid:'bob',token:()async=>'bob-token',
      client:MockClient((_)async=>http.Response(jsonEncode(data),200)));
    await tester.pumpWidget(MaterialApp(home:FirebaseGlobalColorGame(api:api)));
    await tester.pump(const Duration(milliseconds:120));
    expect(find.text('WINNING COLOR: RED'),findsOneWidget);
    expect(find.text('2 winners this round'),findsOneWidget);
    expect(find.text('Your pick: BLUE'),findsOneWidget);
    expect(find.text('Shakil'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
