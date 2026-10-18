import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/community_services.dart';
void main(){
 test('Country flags accept ISO-style codes only',(){expect(countryFlag('BD'),'🇧🇩');expect(countryFlag('om'),'🇴🇲');expect(countryFlag('Bangladesh'),'');expect(countryFlag(null),'');});
 test('Request IDs are distinct UUID v4 values',(){final ids=List.generate(50,(_)=>requestId());expect(ids.toSet().length,50);for(final id in ids){expect(RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$').hasMatch(id),true);}});
 testWidgets('Onboarding requires a name and fits a compact screen',(tester)async{
 tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 await tester.pumpWidget(MaterialApp(home:ProfileSetupPage(profile:{'id':'test','display_name':'','bio':'','country':''})));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.text('Save profile'),180,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('Save profile'));await tester.pumpAndSettle();expect(find.text('Enter your display name.'),findsOneWidget);expect(tester.takeException(),isNull);
 });
}
