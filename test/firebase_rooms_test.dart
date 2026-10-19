import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_rooms.dart';
import 'package:sovera/firebase_voice.dart';
void main(){
  test('RTC publishing permission may arrive after the old two-second limit',()async{
    var ticks=0;
    final granted=await waitForMicPublishPermission(
      canPublish:()=>ticks>=26,
      canContinue:()=>true,
      wait:(_)async{ticks++;},
    );
    expect(granted,isTrue);
    expect(ticks,26);
  });
  test('RTC permission wait aborts if the room closes or timeouts',()async{
    var active=true;
    var checks=0;
    final aborted=await waitForMicPublishPermission(
      canPublish:()=>false,
      canContinue:()=>active,
      wait:(_)async{active=false;checks++;},
    );
    expect(aborted,isFalse);
    expect(checks,1);
    final timedOut=await waitForMicPublishPermission(
      canPublish:()=>false,
      canContinue:()=>true,
      checks:3,
      wait:(_)async{checks++;},
    );
    expect(timedOut,isFalse);
    expect(checks,3);
  });

  testWidgets('voice requires explicit connection and shows no fake seats',(tester)async{
    var calls=0;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{calls++;return http.Response('',503);}));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FirebaseVoicePanel(api:api,roomId:'room'))));
    expect(calls,0);expect(find.text('Audio disconnected'),findsOneWidget);
    await tester.tap(find.text('Connect'));await tester.pumpAndSettle();
    expect(find.textContaining('could not connect'),findsOneWidget);
    expect(find.text('Live audio · Microphone on'),findsNothing);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
  testWidgets('owner edits room capacity and name through authenticated PUT',(tester)async{
    Map<String,dynamic>? sent;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((request)async{
      if(request.method=='PUT'&&request.url.path.endsWith('/rooms/room-1')){
        sent=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(jsonEncode({'room':{'name':sent!['name'],'seats':sent!['seats']}}),200);
      }
      if(request.url.path.endsWith('/messages'))return http.Response('{"messages":[]}',200);
      return http.Response('{"saved":true}',200);
    }));
    const room={'id':'room-1','name':'Original room','owner_uid':'alice','seats':9};
    await tester.pumpWidget(MaterialApp(home:FirebaseRoomChat(api:api,room:room)));await tester.pumpAndSettle();
    expect(find.text('9 seats · Owner settings'),findsOneWidget);
    await tester.tap(find.byTooltip('Room settings'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last,'Renamed room');
    await tester.tap(find.text('12 seats'));await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));await tester.pumpAndSettle();
    expect(sent,{'name':'Renamed room','seats':12});
    expect(find.text('Renamed room'),findsOneWidget);
    expect(find.text('12 seats · Owner settings'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
  testWidgets('non-owner cannot open room settings',(tester)async{
    final api=FirebaseProfileApi(uid:'bob',token:()async=>'token',client:MockClient((request)async{
      if(request.url.path.endsWith('/messages'))return http.Response('{"messages":[]}',200);
      return http.Response('{"saved":true}',200);
    }));
    await tester.pumpWidget(MaterialApp(home:FirebaseRoomChat(api:api,room:const {'id':'room-1','name':'Room','owner_uid':'alice','seats':9})));await tester.pumpAndSettle();
    expect(find.byTooltip('Room settings'),findsNothing);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
  testWidgets('gift effect selects actual online recipient and never submits coins',(tester)async{
    Map<String,dynamic>? sent;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((request)async{
      if(request.url.path.endsWith('/people')){
        return http.Response(jsonEncode({'people':[
          {'uid':'alice','name':'Shakil','country':'BD'},
          {'uid':'bob','name':'Friend','country':'OM'}]}),200);
      }
      if(request.url.path.endsWith('/effects') && request.method=='POST'){
        sent=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response('{"id":1,"saved":true,"visual_only":true}',200);
      }
      if(request.url.path.endsWith('/effects')){
        return http.Response(jsonEncode({'effects':sent==null?[]:[{
          'id':1,'kind':'rose','sender_name':'Shakil','recipient_name':'Friend',
          'sender_uid':'alice','recipient_uid':'bob','created_at':1,
        }],'server_now':1}),200);
      }
      if(request.url.path.endsWith('/messages'))return http.Response('{"messages":[]}',200);
      return http.Response('{"saved":true}',200);
    }));
    await tester.pumpWidget(MaterialApp(home:FirebaseRoomChat(api:api,room:const {
      'id':'room-1','name':'Friends','owner_uid':'alice','seats':9
    })));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Gift effects'));await tester.pumpAndSettle();
    expect(find.textContaining('No Coins'),findsOneWidget);
    await tester.tap(find.text('Friend'));await tester.pumpAndSettle();
    await tester.tap(find.text('Send effect'));await tester.pumpAndSettle();
    expect(sent?['recipient_uid'],'bob');
    expect(sent?['kind'],'rose');
    expect(sent!.containsKey('coins'),isFalse);
    expect(sent!['request_id'],isNotNull);
    expect(find.textContaining('Shakil → Friend'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });

  testWidgets('directory uses server country and participant count',(tester)async{
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async=>http.Response(jsonEncode({'rooms':[{'id':'room-1','name':'My room','owner_uid':'alice','owner_name':'Shakil','country':'BD','avatar_url':null,'occupants':2,'seats':9}]}),200)));
    await tester.pumpWidget(MaterialApp(home:FirebaseRoomsPage(api:api)));await tester.pumpAndSettle();
    expect(find.textContaining('My room'),findsOneWidget);expect(find.textContaining('2 members'),findsOneWidget);expect(find.textContaining('Bangladesh'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed chat send retains input and never fabricates a delivered message',(tester)async{
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{
      if(r.method=='POST')return http.Response('',503);
      if(r.url.path.endsWith('/messages'))return http.Response('{"messages":[]}',200);
      return http.Response('{"saved":true}',200);
    }));
    await tester.pumpWidget(MaterialApp(home:FirebaseRoomChat(api:api,room:{'id':'room-1','name':'My room','owner_uid':'alice','seats':9})));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Keep my message');await tester.tap(find.byIcon(Icons.send));await tester.pumpAndSettle();
    expect(find.text('Keep my message'),findsOneWidget);expect(find.byType(ListTile),findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly,true);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
}
