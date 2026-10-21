import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/voice_background.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('screen wake belongs to live rooms and survives another room release',()async{
    final calls=<bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(VoiceBackground.channel,(call)async{
      if(call.method=='screenAwake')calls.add((call.arguments as Map)['enabled'] as bool);
      return null;
    });
    final a=Object(),b=Object();
    try{
      await RoomScreenAwake.set(a,true);
      await RoomScreenAwake.set(b,true);
      await RoomScreenAwake.set(a,false);
      expect(calls.last,isTrue);
      await RoomScreenAwake.set(b,false);
      expect(calls,[true,true,true,false]);
    }finally{
      await RoomScreenAwake.set(a,false);await RoomScreenAwake.set(b,false);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(VoiceBackground.channel,null);
    }
  });
}
