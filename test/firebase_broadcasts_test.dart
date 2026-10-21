import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_broadcasts.dart';

void main(){
  testWidgets('global confirmed events queue across routes and leave after ten seconds each',(tester)async{
    var calls=0;
    final api=FirebaseProfileApi(uid:'viewer',token:()async=>'token',client:MockClient((request)async{
      calls++;
      expect(request.headers['Authorization'],'Bearer token');
      return http.Response(jsonEncode({'cursor':2,'server_now':100,'items':calls==1?[
        {'id':1,'kind':'win','created_at':100,'winner':{'name':'Winner','public_id':'10000001'},'coins':'5000','game':'Greedy Wheel'},
        {'id':2,'kind':'gift','created_at':100,'sender':{'name':'Sender','public_id':'10000002'},'recipient':{'name':'Receiver','public_id':'10000003'},'gift':{'title':'Royal Crown','count':1}},
      ]:[]}),200);
    }));
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>GlobalCelebrationLayer(api:api,child:child!),home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const Scaffold(body:Text('Another room')))),child:const Text('Open room'))))));
    await tester.pump();await tester.pump(const Duration(milliseconds:100));
    expect(find.text('Winner · ID 10000001'),findsOneWidget);
    await tester.tap(find.text('Open room'));await tester.pump();await tester.pump(const Duration(milliseconds:400));
    expect(find.text('Another room'),findsOneWidget);
    expect(find.text('Winner · ID 10000001'),findsOneWidget);
    await tester.pump(const Duration(seconds:10));await tester.pump();
    expect(find.text('Winner · ID 10000001'),findsNothing);
    expect(find.text('Sender · ID 10000002'),findsOneWidget);
    expect(find.text('→ Receiver · ID 10000003'),findsOneWidget);
    await tester.pump(const Duration(seconds:10));await tester.pump();
    expect(find.byType(CelebrationBanner),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
