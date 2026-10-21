import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sovera/firebase_login_main.dart';

void main() {
  testWidgets('Firebase login presents both methods without starting an SDK flow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FirebaseLoginPage()));
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
    await tester.tap(find.text('Sign in with email'));
    await tester.pump();
    expect(find.text('Enter your email and a Sovera password.'), findsOneWidget);
    expect(find.text('This build checks Google and email sign-in. Rooms, wallet and games are not connected in this build.'), findsNothing);
  });

  testWidgets('New accounts require a Sovera password before contacting Firebase', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FirebaseLoginPage()));
    await tester.ensureVisible(find.text('New to Sovera? Create an email account'));
    await tester.tap(find.text('New to Sovera? Create an email account'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'person@example.com');
    await tester.enterText(find.byType(TextField).last, 'short');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Enter your email and a Sovera password of at least 8 characters.'), findsOneWidget);
  });

  test('Account errors do not disclose whether an email exists', () {
    expect(firebaseLoginError('user-not-found'), firebaseLoginError('wrong-password'));
    expect(firebaseLoginError('invalid-credential'), firebaseLoginError('wrong-password'));
  });
}
