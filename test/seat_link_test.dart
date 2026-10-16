import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/main.dart';
import 'package:sovera/seat_link.dart';
void main(){
 test('Links only connect neighbours in the same row',(){expect(adjacentSeats(0,1,9),isTrue);expect(adjacentSeats(1,2,9),isTrue);expect(adjacentSeats(2,3,9),isFalse);expect(adjacentSeats(0,2,9),isFalse);expect(adjacentSeats(4,5,5),isFalse);});
 testWidgets('Room switches between hand holding and CP heart previews',(tester)async{
 await tester.pumpWidget(const MaterialApp(home:VoiceRoom(name:'Seat preview')));await tester.pumpAndSettle();
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();await tester.tap(find.text('Apply seat preview'));await tester.pumpAndSettle();expect(find.byTooltip('Friendship holding-hands preview'),findsOneWidget);
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();await tester.tap(find.text('CP Love'));await tester.tap(find.text('Apply seat preview'));await tester.pumpAndSettle();expect(find.byTooltip('CP heart preview'),findsOneWidget);
 await tester.tap(find.text('Friendship & CP preview'));await tester.pumpAndSettle();await tester.tap(find.text('Clear seat link'));await tester.pumpAndSettle();expect(find.byType(SeatLinkMarker),findsNothing);expect(tester.takeException(),isNull);
 });
}
