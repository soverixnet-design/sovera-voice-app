import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/ranking_welcome.dart';

Map<String,dynamic> board(int seconds)=>{'enabled':true,'seconds':seconds,'items':[for(var i=1;i<=3;i++){'uid':'user$i','name':'Star $i','public_id':'10000$i','score':100*i,'rank':i,'country':'BD'}]};
void main(){
 for(final seconds in [5,10]){
  testWidgets('Top three IDs show for $seconds seconds before home', (tester)async{
   await tester.pumpWidget(MaterialApp(home:RankingWelcomeGate(load:()async=>board(seconds),child:const Scaffold(body:Text('Actual home')))));
   await tester.pump();
   expect(find.text('ID 100001'),findsOneWidget);expect(find.text('ID 100003'),findsOneWidget);
   expect(find.text('Actual home'),findsNothing);
   await tester.pump(Duration(seconds:seconds-1));expect(find.text('Actual home'),findsNothing);
   await tester.pump(const Duration(seconds:1));expect(find.text('Actual home'),findsOneWidget);
   expect(tester.takeException(),isNull);
  });
 }
 testWidgets('Empty ranking or failure does not block entering home',(tester)async{
  await tester.pumpWidget(MaterialApp(home:RankingWelcomeGate(key:const ValueKey('empty'),load:()async=>{'enabled':true,'items':[]},child:const Text('Home'))));
  await tester.pump();expect(find.text('Home'),findsOneWidget);
  await tester.pumpWidget(MaterialApp(home:RankingWelcomeGate(key:const ValueKey('error'),load:()async=>throw Exception('offline'),child:const Text('Home after error'))));
  await tester.pump();expect(find.text('Home after error'),findsOneWidget);
 });
 testWidgets('Skip cancels countdown and opening gate does not repeat on rebuild',(tester)async{
  final key=GlobalKey();var calls=0;
  Widget app()=>MaterialApp(home:RankingWelcomeGate(key:key,load:()async{calls++;return board(10);},child:const Text('Home')));
  await tester.pumpWidget(app());await tester.pump();
  await tester.tap(find.text('Enter now'));await tester.pump();expect(find.text('Home'),findsOneWidget);
  await tester.pumpWidget(app());await tester.pump(const Duration(seconds:12));expect(calls,1);expect(tester.takeException(),isNull);
 });
}
