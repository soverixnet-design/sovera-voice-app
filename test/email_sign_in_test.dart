import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sovera/email_sign_in.dart';
void main(){
 testWidgets('Email validates input before contacting auth',(tester)async{
 var calls=0;await tester.pumpWidget(MaterialApp(home:EmailSignInPage(onSubmit:(_,__,___)async{calls++;return null;})));
 await tester.tap(find.widgetWithText(FilledButton,'Sign in'));await tester.pumpAndSettle();expect(find.text('Enter a valid email address.'),findsOneWidget);expect(calls,0);
 });
 testWidgets('Email password signs in and preserves server errors for retry',(tester)async{
 final calls=<String>[];await tester.pumpWidget(MaterialApp(home:EmailSignInPage(onSubmit:(email,password,create)async{calls.add('$email:$create');throw const AuthException('Invalid login credentials');})));
 await tester.enterText(find.byType(TextField).at(0),' member@example.com ');await tester.enterText(find.byType(TextField).at(1),'example-test-password');await tester.tap(find.widgetWithText(FilledButton,'Sign in'));await tester.pumpAndSettle();expect(calls,['member@example.com:false']);expect(find.text('Invalid login credentials'),findsOneWidget);
 });
 testWidgets('Email signup reports email confirmation without claiming a session',(tester)async{
 await tester.pumpWidget(MaterialApp(home:EmailSignInPage(onSubmit:(_,__,create)async=>create?'Check your email to confirm your account.':null)));
 await tester.tap(find.text('New here? Create an email account'));await tester.pumpAndSettle();await tester.enterText(find.byType(TextField).at(0),'member@example.com');await tester.enterText(find.byType(TextField).at(1),'example-test-password');await tester.tap(find.widgetWithText(FilledButton,'Create account'));await tester.pumpAndSettle();expect(find.text('Check your email to confirm your account.'),findsOneWidget);
 });
}
