import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_sovera_home.dart';

class _FakeUser implements User {
  @override String get uid => 'alice';
  @override String? get email => 'alice@example.com';
  @override String? get displayName => 'Alice';
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main(){
  testWidgets('original Sovera four-tab design opens with real server rooms',(tester)async{
    final paths=<String>[];
    final client=MockClient((request)async{
      expect(request.headers['Authorization'],'Bearer fake-id-token');
      paths.add(request.url.path);
      if(request.url.path.endsWith('/rooms')){
        return http.Response(jsonEncode({'rooms':[
          {'id':'room-7','owner_uid':'bob','owner_name':'Friend',
           'name':'Sunset Lounge','seats':9,'country':'BD','occupants':2,
           'avatar_url':null,'created_at':1000},
          {'id':'room-8','owner_uid':'carol','owner_name':'Omani',
           'name':'Muscat Lounge','seats':6,'country':'OM','occupants':3,
           'avatar_url':null,'created_at':1001},
        ]}),200);
      }
      if(request.url.path.endsWith('/account')){
        return http.Response(jsonEncode({'profile':{
          'firebase_uid':'alice','display_name':'Alice','country':'BD','bio':'Hello',
          'avatar_url':null,
        }}),200);
      }
      return http.Response('{"saved":true}',200);
    });
    final api=FirebaseProfileApi(uid:'alice',token:()async=>'fake-id-token',
      client:client);
    await tester.pumpWidget(MaterialApp(home:
      FirebaseSoveraHome(user:_FakeUser(),apiOverride:api)));
    await tester.pumpAndSettle();

    expect(find.text('Sovera'),findsOneWidget);
    expect(find.text('SOVERA COMMUNITY'),findsOneWidget);
    expect(find.text('Home'),findsOneWidget);
    expect(find.text('Moments'),findsOneWidget);
    expect(find.text('Messages'),findsOneWidget);
    expect(find.text('Me'),findsOneWidget);
    expect(find.text('🇧🇩 Sunset Lounge'),findsOneWidget);
    expect(find.text('🇴🇲 Muscat Lounge'),findsOneWidget);
    expect(find.text('2'),findsOneWidget);
    expect(find.text('3'),findsOneWidget);
    expect(find.text('Explore room'),findsNothing);
    expect(find.text('Games'),findsOneWidget);
    expect(paths.any((p)=>p.endsWith('/rooms')),isTrue);
    expect(paths.any((p)=>p.endsWith('/account')),isTrue);

    await tester.tap(find.text('Moments'));await tester.pumpAndSettle();
    expect(find.text('Write a moment'),findsOneWidget);
    await tester.tap(find.text('Messages'));await tester.pumpAndSettle();
    expect(find.text('Official support'),findsOneWidget);
    await tester.tap(find.text('Me'));await tester.pumpAndSettle();
    expect(find.text('My profile'),findsOneWidget);
    expect(find.text('Edit Profile'),findsOneWidget);
    expect(find.text('Style preview'),findsNothing);
    expect(find.text('Not active'),findsOneWidget);
    expect(find.text('My connections'),findsOneWidget);
    expect(find.text('Your profile'),findsNothing);
    expect(find.text('Country'),findsNothing);
    expect(find.text('Save profile'),findsNothing);
    await tester.ensureVisible(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Profile'));await tester.pumpAndSettle();
    expect(find.text('Your profile'),findsOneWidget);
    expect(find.text('Country'),findsOneWidget);
    expect(find.text('Save profile'),findsOneWidget);
    await tester.pageBack();await tester.pumpAndSettle();
    expect(find.text('Your profile'),findsNothing);
    expect(find.text('Edit Profile'),findsOneWidget);
    await tester.ensureVisible(find.text('Frames & effects'));
    await tester.pumpAndSettle();
    expect(find.text('Frames & effects'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
}
