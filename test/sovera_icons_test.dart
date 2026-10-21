import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/sovera_icons.dart';
void main(){
 testWidgets('all six local 3D icons fit compact buttons and preserve hit targets',(tester)async{
  var tapped=0;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Wrap(children:[
   for(final icon in [Icons.card_giftcard_rounded,Icons.redeem_rounded,Icons.mic_rounded,Icons.mic_off_rounded,Icons.chat_rounded,Icons.campaign_rounded])IconButton(tooltip:SoveraIcon.assetFor(icon),onPressed:()=>tapped++,icon:SoveraIcon(icon,size:34)),
  ]))));
  await tester.pumpAndSettle();
  expect(find.byType(Image),findsNWidgets(6));expect(tester.takeException(),isNull);
  await tester.tap(find.byTooltip('diamond-gift'));expect(tapped,1);
  expect(SoveraIcon.assetFor(Icons.mic_rounded),'mic-on');
  expect(SoveraIcon.assetFor(Icons.mic_off_rounded),'mic-off');
  expect(SoveraIcon.assetFor(Icons.settings),isNull);
 });
}
