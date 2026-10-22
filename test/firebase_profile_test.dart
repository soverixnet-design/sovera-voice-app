import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';

Map<String,dynamic> profile() => {'firebase_uid':'alice','display_name':'Shakil','country':'BD','bio':'Hello','avatar_url':'https://example.com/avatar.png'};
void main() {
  test('fresh bearer token, fixed HTTPS endpoint, and no redirects or chosen UID',() async {
    var tokens=0;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token-${++tokens}',client:MockClient((r)async{
      expect(r.url.scheme,'https');expect(r.url.host,'voice.soverixnet.com');
      expect(r.followRedirects,false);expect(r.headers['Authorization'],'Bearer token-$tokens');
      if(r.method=='PUT') { final body=jsonDecode(r.body) as Map;expect(body.containsKey('firebase_uid'),false);expect(body.containsKey('coins'),false); }
      return http.Response(jsonEncode({'profile':profile()}),200);
    }));
    await api.load();await api.save(name:'Shakil',country:'BD',bio:'Hello');expect(tokens,2);
  });
  test('uploaded room chat photos keep their verified media URL',()async{
    const url='https://voice.soverixnet.com/sovera/account/chat-photo/abcdef';
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{
      expect(r.url.path,'/sovera/account/rooms/room/chat-photo');
      return http.Response(jsonEncode({'avatar_url':url}),200);
    }));
    expect(await api.uploadPhoto(XFile.fromData(Uint8List.fromList([1,2,3])),suffix:'/rooms/room/chat-photo'),url);
  });
  test('room errors preserve the server reason and rollout status',()async{
    for(final status in [403,422,503]){
      final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async=>http.Response('{"detail":"Room permission unavailable"}',status)));
      await expectLater(api.call('PUT',suffix:'/rooms/room'),throwsA(isA<ProfileApiError>().having((e)=>e.message,'reason','Room permission unavailable')));
    }
  });
  test('wrong-account response and redirects are rejected',()async{
    for(final response in [http.Response(jsonEncode({'profile':{...profile(),'firebase_uid':'bob'}}),200),http.Response('',302)]) {
      final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((_)async=>response));
      await expectLater(api.load(),throwsA(isA<ProfileApiError>()));
    }
  });
  testWidgets('failed load cannot save an empty replacement profile',(tester)async{
    var writes=0;
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{if(r.method=='PUT')writes++;return http.Response('',503);}));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FirebaseProfileEditor(api:api))));await tester.pumpAndSettle();
    expect(find.text('Retry profile connection'),findsOneWidget);expect(find.text('Save profile'),findsNothing);expect(writes,0);
  });
  testWidgets('failed save retains edits and existing avatar without success notice',(tester)async{
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((r)async{
      if(r.method=='GET')return http.Response(jsonEncode({'profile':profile()}),200);
      expect(jsonDecode(r.body)['avatar_url'],'https://example.com/avatar.png');return http.Response('',503);
    }));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:FirebaseProfileEditor(api:api)))));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first,'Edited name');
    await tester.ensureVisible(find.text('Save profile'));await tester.tap(find.text('Save profile'));await tester.pumpAndSettle();
    expect(find.text('Edited name'),findsOneWidget);expect(find.text('Profile saved to your server.'),findsNothing);
  });
}
