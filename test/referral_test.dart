import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/referral.dart';
class FakeReferrals extends ReferralStore {
 int calls=0; String? claimed;
 @override Future<ReferralSnapshot> load(String id) async {calls++;return ReferralSnapshot(code:'SV123456ABCDEF',count:2,claimedCode:claimed);}
 @override Future<void> claim(String code) async {claimed=code;}
}
class FailingReferrals extends ReferralStore {
 bool failLoad=true;
 @override Future<ReferralSnapshot> load(String id) async {if(failLoad)throw Exception('offline');return const ReferralSnapshot(code:'SV123456ABCDEF',count:0);}
 @override Future<void> claim(String code) async {throw Exception('offline');}
}
void main(){
 testWidgets('load and claim errors remain retryable',(tester)async{final store=FailingReferrals();await tester.pumpWidget(MaterialApp(home:ReferralPage(profile:const {'id':'test'},store:store)));await tester.pumpAndSettle();expect(find.text('Retry'),findsOneWidget);store.failLoad=false;await tester.tap(find.text('Retry'));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.byType(TextField),300);await tester.enterText(find.byType(TextField),'SVABCDEF123456');await tester.ensureVisible(find.text('Apply invitation'));await tester.tap(find.text('Apply invitation'));await tester.pumpAndSettle();expect(find.byType(TextField),findsOneWidget);expect(find.textContaining('Could not save your invitation'),findsOneWidget);});
 testWidgets('referral design review',(tester)async{
 tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));await icons.load();
 final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');if(font.existsSync()){final loader=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));await loader.load();}
 final key=GlobalKey();await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true).copyWith(scaffoldBackgroundColor:const Color(0xFF12172D),colorScheme:const ColorScheme.dark(primary:Color(0xFF9268F4))),home:RepaintBoundary(key:key,child:ReferralPage(profile:const {'id':'test'},store:FakeReferrals()))));await tester.pumpAndSettle();
 final boundary=key.currentContext!.findRenderObject() as RenderRepaintBoundary;final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await tester.runAsync(()async{await Directory('build/design-review').create(recursive:true);await File('build/design-review/referrals.png').writeAsBytes(bytes!.buffer.asUint8List());});image.dispose();expect(tester.takeException(),isNull);
 });
 test('invitation parsing preserves manual referral code',(){expect(parseReferralCode('https://example.com?ref=sv123456abcdef'),'SV123456ABCDEF');expect(parseReferralCode('bad'),isNull);expect(referralInvitation('SV123456ABCDEF'),contains('enter my code'));});
 testWidgets('guest never queries referrals',(tester)async{final store=FakeReferrals();await tester.pumpWidget(MaterialApp(home:ReferralPage(store:store)));expect(store.calls,0);expect(find.textContaining('Sign in to get'),findsOneWidget);});
 testWidgets('self code denied and friend claim saved',(tester)async{final store=FakeReferrals();await tester.pumpWidget(MaterialApp(home:ReferralPage(profile:const {'id':'test'},store:store)));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.byType(TextField),300);await tester.enterText(find.byType(TextField),'SV123456ABCDEF');await tester.ensureVisible(find.text('Apply invitation'));await tester.tap(find.text('Apply invitation'));await tester.pumpAndSettle();expect(store.claimed,isNull);await tester.scrollUntilVisible(find.byType(TextField),300);await tester.enterText(find.byType(TextField),'SVABCDEF123456');await tester.tap(find.text('Apply invitation'));await tester.pumpAndSettle();expect(store.claimed,'SVABCDEF123456');expect(find.byType(TextField),findsNothing);expect(find.text('Invitation saved: SVABCDEF123456'),findsOneWidget);});
 testWidgets('compact large text layout',(tester)async{tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:ReferralPage(profile:const {'id':'test'},store:FakeReferrals())));await tester.pumpAndSettle();expect(tester.takeException(),isNull);});
}
