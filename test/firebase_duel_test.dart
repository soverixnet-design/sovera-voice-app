import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_duel.dart';

void main(){
  testWidgets('third room member joins queue, waits, and can cancel',(tester)async{
    var waiting=false;
    var calls=0;
    final api=FirebaseProfileApi(uid:'eve',token:()async=>'eve-session',
      client:MockClient((request)async{
        expect(request.headers['Authorization'],'Bearer eve-session');
        if(request.url.path.endsWith('/duel/join')){
          waiting=true;calls++;
        }
        if(request.url.path.endsWith('/duel/cancel')){
          waiting=false;calls++;
        }
        return http.Response(jsonEncode({
          'ready':true,'board':List.filled(9,'.'),
          'player_x':'alice','player_o':'bob',
          'name_x':'Shakil','name_o':'Friend',
          'turn_uid':'alice','winner':null,'revision':2,
          'waiting_count':waiting?1:0,
          'my_waiting_position':waiting?1:null,
          'next_allowed_at_ms':null,
        }),200);
      }));
    await tester.pumpWidget(MaterialApp(home:FirebaseDuelPage(api:api,roomId:'room-1')));
    await tester.pumpAndSettle();
    expect(find.text('Join next match queue'),findsOneWidget);
    await tester.tap(find.text('Join next match queue'));await tester.pumpAndSettle();
    expect(find.text('Your queue position: #1'),findsOneWidget);
    expect(find.text('Cancel'),findsOneWidget);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    expect(find.text('Join next match queue'),findsOneWidget);
    expect(calls,2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('XO duel is server-driven and moves include its revision',(tester)async{
    Map<String,dynamic>? sent;
    final game=<String,dynamic>{
      'ready':true,'board':List.filled(9,'.'),
      'player_x':'alice','player_o':'bob','name_x':'Shakil','name_o':'Friend',
      'turn_uid':'alice','winner':null,'revision':2,
    };
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'signed-session',
      client:MockClient((request)async{
        expect(request.headers['Authorization'],'Bearer signed-session');
        if(request.method=='POST'&&request.url.path.endsWith('/duel/move')){
          sent=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
          game['board']=['X','.','.','.','.','.','.','.','.'];
          game['turn_uid']='bob';
          game['revision']=3;
        }
        return http.Response(jsonEncode(game),200);
      }));
    await tester.pumpWidget(MaterialApp(home:FirebaseDuelPage(api:api,roomId:'room-1')));
    await tester.pumpAndSettle();
    expect(find.text('Your turn'),findsOneWidget);
    final cell=find.descendant(of:find.byType(GridView),matching:find.byType(OutlinedButton)).first;
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(sent,{'cell':0,'revision':2});
    expect(find.text('Opponent’s turn'),findsOneWidget);
    expect(find.text('X'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
