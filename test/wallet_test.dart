import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/wallet.dart';

const profile={'id':'fixture-owner','uid':100001};
class FixtureStore extends CoinStore {
 bool fail=false;String lastSearch='',lastCountry='',lastCurrency='';int balanceCalls=0;
 @override Future<Map<String,dynamic>?> balance(String id) async {balanceCalls++;if(fail)throw Exception('offline');return {'coins':'123456','diamonds':'4200','status':'active'};}
 @override Future<List<Map<String,dynamic>>> entries(String id,int offset,String currency)async {lastCurrency=currency;return [{'kind':'exchange','coin_delta':70,'diamond_delta':-100,'reference':'test-receipt','created_at':'2026-10-16T12:00:00Z'}];}
 @override Future<List<Map<String,dynamic>>> sellers(String search,String country,int offset)async {lastSearch=search;lastCountry=country;if(search=='missing')return [];return [{'seller_uid':100001,'display_name':'Test seller','country':'Oman','languages':'Bangla, English','description':'Test listing only.'}];}
}
void main(){
 testWidgets('Wallet reads balances, hides values and retries errors',(tester)async{
  final store=FixtureStore()..fail=true;
  await tester.pumpWidget(MaterialApp(home:WalletPage(profile:profile,store:store)));await tester.pumpAndSettle();
  expect(find.text('Could not load your wallet. Retry'),findsOneWidget);
  store.fail=false;await tester.tap(find.text('Could not load your wallet. Retry'));await tester.pumpAndSettle();
  expect(find.text('123,456'),findsOneWidget);expect(find.text('4,200'),findsOneWidget);
  await tester.tap(find.byTooltip('Hide balances'));await tester.pump();expect(find.text('••••'),findsNWidgets(2));
  await tester.tap(find.byTooltip('Show balances'));await tester.pump();expect(find.text('123,456'),findsOneWidget);
 });
 testWidgets('Seller search and country filters query the store',(tester)async{
  final store=FixtureStore();await tester.pumpWidget(MaterialApp(home:CoinSellerList(store:store)));await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField),'missing');await tester.tap(find.byTooltip('Search sellers'));await tester.pumpAndSettle();
  expect(store.lastSearch,'missing');expect(find.text('No approved sellers found'),findsOneWidget);
  await tester.enterText(find.byType(TextField),'100001');await tester.tap(find.byTooltip('Search sellers'));await tester.pumpAndSettle();
  await tester.tap(find.text('Oman'));await tester.pumpAndSettle();expect(store.lastCountry,'Oman');expect(store.lastSearch,'100001');
  await tester.ensureVisible(find.text('Test seller'));await tester.pumpAndSettle();await tester.tap(find.text('Test seller'));await tester.pumpAndSettle();
  expect(find.text('Copy seller ID'),findsOneWidget);
 });
 testWidgets('History filters and guest wallet do not invent activity',(tester)async{
  final store=FixtureStore();await tester.pumpWidget(MaterialApp(home:WalletHistory(profile:profile,store:store)));await tester.pumpAndSettle();
  expect(find.text('+70 Coins'),findsOneWidget);expect(find.text('-100 Diamonds'),findsOneWidget);
  await tester.tap(find.text('Diamonds'));await tester.pumpAndSettle();expect(store.lastCurrency,'Diamonds');
  await tester.pumpWidget(MaterialApp(home:WalletPage(store:store)));await tester.pumpAndSettle();expect(store.balanceCalls,0);expect(find.text('—'),findsNWidgets(2));
 });
 testWidgets('Compact wallet and seller list support large text',(tester)async{
  tester.view.physicalSize=const Size(320,740);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final store=FixtureStore();
  for(final screen in [WalletPage(profile:profile,store:store),CoinSellerList(store:store),WalletHistory(profile:profile,store:store)]){
   await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:screen));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  }
 });
 testWidgets('Export wallet and seller design',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(()async{
   await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
   final file=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
   if(await file.exists())await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load();
  });
  for(final pair in <String,Widget>{'wallet':const WalletPage(),'coin-sellers':CoinSellerList(store:FixtureStore())}.entries){
   final key=GlobalKey();await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(useMaterial3:true),home:pair.value)));await tester.pumpAndSettle();
   await tester.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    await Directory('build/design-review').create(recursive:true);await File('build/design-review/${pair.key}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
   });expect(tester.takeException(),isNull);
  }
 });
}
