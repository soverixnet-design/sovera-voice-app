import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('original Food Wheel artwork and server-only results are packaged',()async{
    final html=await rootBundle.loadString('assets/games/food-wheel.html');
    expect(html,contains('id="wheel"'));
    expect(html,contains('id="winners"'));
    expect(html,contains('id="chips"'));
    expect(html,contains('id="banner"'));
    expect(html,contains('SoveraWheelBridge.postMessage'));
    expect(html,contains("rpc('state')"));
    expect(html,contains("rpc('pick'"));
    expect(html,contains('serverNow'));
    expect(html,contains('visualIndex'));
    expect(html,contains('winnerCount'));
    // Old browser-side random outcomes, local coin accounting and bots are gone.
    expect(html,isNot(contains('function plan(id)')));
    expect(html,isNot(contains('const NAMES=')));
    expect(html,isNot(contains('function pick(){')));
    expect(html,isNot(contains('bal-=chip')));
    expect(html,isNot(contains('Math.random()*tot')));
    expect(html,contains('realCoinsEnabled'));
  });
}
