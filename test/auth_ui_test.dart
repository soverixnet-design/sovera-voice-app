import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/auth_gate.dart';
import 'package:sovera/main.dart';

void main() {
 testWidgets('Export Google login design',(tester)async{
 tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 await tester.runAsync(()async{final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));await icons.load();final file=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');if(await file.exists()){final font=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));await font.load();}});
 final key=GlobalKey();await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),home:RepaintBoundary(key:key,child:const SoveraLoginPage())));await tester.pumpAndSettle();await tester.runAsync(()async{final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('build/design-review').create(recursive:true);await File('build/design-review/google-login.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});expect(tester.takeException(),isNull);
 });
 testWidgets('Google sign-in prevents duplicate taps and allows retry',(tester)async{
 final pending=Completer<void>();final calls=<OAuthProvider>[];
 await tester.pumpWidget(MaterialApp(home:SoveraLoginPage(onSignIn:(provider){calls.add(provider);return pending.future;})));
 await tester.tap(find.text('Continue with Google'));await tester.pump();expect(calls,[OAuthProvider.google]);expect(find.text('Opening Google…'),findsOneWidget);
 final button=tester.widget<FilledButton>(find.ancestor(of:find.text('Opening Google…'),matching:find.byType(FilledButton)));expect(button.onPressed,isNull);
 pending.completeError(const AuthException('Please retry Google.'));await tester.pumpAndSettle();expect(find.text('Please retry Google.'),findsOneWidget);expect(find.text('Continue with Google'),findsOneWidget);
 });
 testWidgets('Google button selects the Google provider',(tester)async{
 OAuthProvider? selected;await tester.pumpWidget(MaterialApp(home:SoveraLoginPage(onSignIn:(provider)async{selected=provider;})));await tester.tap(find.text('Continue with Google'));await tester.pumpAndSettle();expect(selected,OAuthProvider.google);
 });
 testWidgets('Guest home has an accessible route to sign in',(tester)async{
 await tester.pumpWidget(const MaterialApp(home:Home()));await tester.pumpAndSettle();await tester.tap(find.text('Sign in / Create account'));await tester.pumpAndSettle();expect(find.text('Continue with Google'),findsOneWidget);
 });
 testWidgets('Compact sign-in supports large text',(tester)async{
 tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:const SoveraLoginPage()));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.text('Continue with Google'),200,scrollable:find.byType(Scrollable).first);expect(tester.takeException(),isNull);
 });
 testWidgets('Signed-out entry shows Google sign-in without the account home', (tester) async {
  await tester.pumpWidget(const MaterialApp(home:SoveraLoginPage()));
  await tester.pumpAndSettle();
  expect(find.text('Continue with Google'),findsOneWidget);
  expect(find.text('Continue with Google'),findsOneWidget);
  expect(find.text('Continue with Facebook'),findsOneWidget);
  expect(find.text('Continue with email'),findsOneWidget);
  expect(find.byType(Home),findsNothing);
  expect(tester.takeException(),isNull);
 });
 testWidgets('Design exploration opens only the guest home', (tester) async {
  await tester.pumpWidget(const MaterialApp(home:SoveraLoginPage()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Explore design preview'));
  await tester.pumpAndSettle();
  expect(find.text('DESIGN PREVIEW · NOT SIGNED IN'),findsOneWidget);
  expect(find.byType(Home),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
 testWidgets('Facebook remains a separate working sign-in choice',(tester)async{
 OAuthProvider? selected;await tester.pumpWidget(MaterialApp(home:SoveraLoginPage(onSignIn:(provider)async{selected=provider;})));await tester.tap(find.text('Continue with Facebook'));await tester.pumpAndSettle();expect(selected,OAuthProvider.facebook);
 });
 testWidgets('Email sign-in opens without starting an OAuth provider',(tester)async{
 var called=false;await tester.pumpWidget(MaterialApp(home:SoveraLoginPage(onSignIn:(_)async{called=true;})));await tester.tap(find.text('Continue with email'));await tester.pumpAndSettle();expect(find.text('Sign in with email'),findsOneWidget);expect(find.text('Email address'),findsOneWidget);expect(called,false);
 });
 test('Disabled Google cannot open the OAuth browser flow',(){expect(()=>requireSocialProvider({'external':{'google':false,'facebook':true}},OAuthProvider.google),throwsA(isA<AuthException>()));expect(()=>requireSocialProvider({'external':{'google':false,'facebook':true}},OAuthProvider.facebook),returnsNormally);});

}

