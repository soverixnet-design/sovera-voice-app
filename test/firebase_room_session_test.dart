import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sovera/firebase_profile.dart';
import 'package:sovera/firebase_room_session.dart';

class _LiveSeat extends StatefulWidget {
 final VoidCallback minimize,leave;final VoidCallback mountedSeat,removedSeat;
 const _LiveSeat({required this.minimize,required this.leave,required this.mountedSeat,required this.removedSeat});
 @override State<_LiveSeat> createState()=>_LiveSeatState();
}
class _LiveSeatState extends State<_LiveSeat>{
 @override void initState(){super.initState();widget.mountedSeat();}
 @override void dispose(){widget.removedSeat();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(body:Column(children:[const Text('Seat ID 10000001'),TextButton(onPressed:widget.minimize,child:const Text('Minimize')),TextButton(onPressed:widget.leave,child:const Text('Leave'))]));
}
void main(){
 testWidgets('Minimize and restore retain the same live seat; only leave disposes it',(tester)async{
  var joins=0,leaves=0,serverLeaves=0;
  final api=FirebaseProfileApi(uid:'alice',token:()async=>'token',client:MockClient((request)async{serverLeaves++;return http.Response('{}',200);}));
  await tester.pumpWidget(MaterialApp(builder:(context,child)=>PersistentRoomLayer(api:api,child:child!,roomBuilder:(_,room,minimize,leave)=>_LiveSeat(minimize:minimize,leave:leave,mountedSeat:()=>joins++,removedSeat:()=>leaves++)),home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>PersistentRoomLayer.open(context,api,{'id':'room-a','name':'My room'}),child:const Text('Open room'))))));
  await tester.tap(find.text('Open room'));await tester.pumpAndSettle();
  expect(joins,1);expect(leaves,0);
  await tester.tap(find.text('Minimize'));await tester.pumpAndSettle();
  expect(find.text('Open room'),findsOneWidget);expect(find.byKey(const ValueKey('restore-active-room')),findsOneWidget);
  expect(joins,1);expect(leaves,0);expect(serverLeaves,0);
  final chip=find.byKey(const ValueKey('draggable-room-chip'));
  final before=tester.getTopLeft(chip);
  await tester.drag(chip,const Offset(-180,-150));await tester.pumpAndSettle();
  expect(tester.getTopLeft(chip).dx,lessThan(before.dx));
  expect(joins,1);expect(leaves,0);expect(serverLeaves,0);
  await tester.drag(chip,const Offset(-2000,-2000));await tester.pumpAndSettle();
  expect(tester.getTopLeft(chip).dx,greaterThanOrEqualTo(0));
  expect(tester.getTopLeft(chip).dy,greaterThanOrEqualTo(0));
  await tester.tap(find.byKey(const ValueKey('restore-active-room')));await tester.pumpAndSettle();
  expect(find.text('Seat ID 10000001'),findsOneWidget);expect(joins,1);expect(leaves,0);
  await tester.binding.handlePopRoute();await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('restore-active-room')),findsOneWidget);expect(leaves,0);
  await tester.tap(find.byKey(const ValueKey('restore-active-room')));await tester.pumpAndSettle();
  await tester.tap(find.text('Leave'));await tester.pumpAndSettle();
  expect(leaves,1);expect(serverLeaves,1);expect(find.byKey(const ValueKey('restore-active-room')),findsNothing);
 });
}
