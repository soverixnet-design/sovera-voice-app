import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/sovera_room_card.dart';
import 'package:sovera/firebase_rooms.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main(){
  testWidgets('room cover and country appear below the image without repeating identity',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:180,height:235,child:SoveraRoomCard(room:const {'name':'Blue Lounge','country':'BD','occupants':3},onTap:(){})))));
    expect(find.text('🇧🇩 Blue Lounge'),findsOneWidget);
    expect(find.text('Bangladesh'),findsOneWidget);
    expect(find.text('3'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('owner seat opens branded microphone and lock dialog',(tester)async{
    final api=FirebaseProfileApi(uid:'owner',token:()async=>'token',client:MockClient((request)async{
      if(request.url.path.endsWith('/messages'))return http.Response('{"messages":[]}',200);
      return http.Response('{"saved":true}',200);
    }));
    await tester.pumpWidget(MaterialApp(home:FirebaseRoomChat(api:api,room:const {'id':'room','name':'Blue Lounge','country':'BD','owner_uid':'owner','seats':9}))));
    await tester.pumpAndSettle();
    expect(find.text('🇧🇩 Blue Lounge'),findsOneWidget);
    expect(find.text('Tap a mic to join'),findsNothing);
    await tester.tap(find.text('Mic 1'));await tester.pumpAndSettle();
    expect(find.text('Take mic'),findsOneWidget);
    expect(find.text('Lock seat'),findsOneWidget);
    expect(find.text('Lock all seats'),findsOneWidget);
    expect(find.text('Unlock all seats'),findsOneWidget);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
