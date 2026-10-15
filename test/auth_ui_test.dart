import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/auth_gate.dart';
import 'package:sovera/main.dart';

void main() {
 testWidgets('Signed-out entry shows Google sign-in without the account home', (tester) async {
  await tester.pumpWidget(const MaterialApp(home:GoogleLoginPage()));
  await tester.pumpAndSettle();
  expect(find.text('Continue with Google'),findsOneWidget);
  expect(find.byType(Home),findsNothing);
  expect(tester.takeException(),isNull);
 });
}
