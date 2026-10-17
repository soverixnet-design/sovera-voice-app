import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/referral.dart';
class FakeReferrals extends ReferralStore {
 int calls=0; String? claimed;
 @override Future<ReferralSnapshot> load(String id) async {calls++;return ReferralSnapshot(code:'SV123456ABCDEF',count:2,claimedCode:claimed);}
 @override Future<void> claim(String code) async {claimed=code;}
}
void main(){
 test('invitation parsing preserves manual referral code',(){expect(parseReferralCode('https://example.com?ref=sv123456abcdef'),'SV123456ABCDEF');expect(parseReferralCode('bad'),isNull);expect(referralInvitation('SV123456ABCDEF'),contains('enter my code'));});
 testWidgets('guest never queries referrals',(tester)async{final store=FakeReferrals();await tester.pumpWidget(MaterialApp(home:ReferralPage(store:store)));expect(store.calls,0);expect(find.textContaining('Sign in to get'),findsOneWidget);});
 testWidgets('self code denied and friend claim saved',(tester)async{final store=FakeReferrals();await tester.pumpWidget(MaterialApp(home:ReferralPage(profile:const {'id':'test'},store:store)));await tester.pumpAndSettle();await tester.enterText(find.byType(TextField),'SV123456ABCDEF');await tester.ensureVisible(find.text('Apply invitation'));await tester.tap(find.text('Apply invitation'));await tester.pumpAndSettle();expect(store.claimed,isNull);await tester.enterText(find.byType(TextField),'SVABCDEF123456');await tester.tap(find.text('Apply invitation'));await tester.pumpAndSettle();expect(store.claimed,'SVABCDEF123456');expect(find.byType(TextField),findsNothing);expect(find.text('Invitation saved: SVABCDEF123456'),findsOneWidget);});
 testWidgets('compact large text layout',(tester)async{tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:ReferralPage(profile:const {'id':'test'},store:FakeReferrals())));await tester.pumpAndSettle();expect(tester.takeException(),isNull);});
}
