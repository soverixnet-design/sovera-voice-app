import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/room_entry_scene.dart';
void main(){
 testWidgets('An entry uses the whole room viewport, expires once, and does not replay on heartbeat',(tester)async{
  final events=<Map<String,dynamic>>[{'event_id':1,'created_at':100,'sender_name':'Alice','asset':{'kind':'entry','id':'entry','url':'https://example.invalid/entry.webp','title':'Royal arrival'}}];
  Widget page()=>MaterialApp(home:Scaffold(body:RoomEntryScene(events:events,serverNow:101)));
  await tester.pumpWidget(page());await tester.pump(const Duration(milliseconds:100));
  expect(tester.getSize(find.byKey(const ValueKey('full-room-entry'))).height,greaterThan(400));
  await tester.pump(const Duration(seconds:11));
  expect(find.byKey(const ValueKey('full-room-entry')),findsNothing);
  await tester.pumpWidget(page());
  expect(find.byKey(const ValueKey('full-room-entry')),findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
}
