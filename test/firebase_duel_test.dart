import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_duel.dart';

void main(){
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
