import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serialize native commands and bind them to one live room instance. A late
/// permission/service reply from a closed room must not stop a newer room.
class VoiceBackground {
  static const channel=MethodChannel('sovera/voice_background');
  static bool running=false;
  static Object? current;
  static Future<void> queue=Future<void>.value();
  static bool get supported=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  static Future<T> serial<T>(Future<T> Function() operation){
    final result=queue.then((_)=>operation());
    queue=result.then<void>((_) {},onError:(Object _,StackTrace __){});
    return result;
  }
  static Future<void> nativeStop()async{
    running=false;
    try{await channel.invokeMethod<void>('stop').timeout(const Duration(seconds:2));}catch(_){}
  }
  static Future<bool> start({required Object owner,bool microphone=false}){
    if(!supported)return Future.value(false);
    current=owner;
    return serial(()async{
      if(!identical(current,owner))return false;
      try{
        final ready=await channel.invokeMethod<bool>('start',{'microphone':microphone}).timeout(const Duration(seconds:8))==true;
        if(!identical(current,owner)){if(ready)await nativeStop();return false;}
        running=ready;return ready;
      }catch(_){await nativeStop();return false;}
    });
  }
  static Future<void> stop({required Object owner}){
    if(!supported||!identical(current,owner))return Future.value();
    current=null;
    return serial(()async{if(current==null&&running)await nativeStop();});
  }
}

/// A live room holds the foreground display awake, including in-app minimize.
/// Android ignores this window flag while another app is in the foreground.
class RoomScreenAwake {
  static final owners=<Object>{};
  static Future<void> set(Object owner,bool enabled)async{
    if(!VoiceBackground.supported)return;
    if(enabled){owners.add(owner);}else{owners.remove(owner);}
    await VoiceBackground.serial(()async{
      try{await VoiceBackground.channel.invokeMethod<void>('screenAwake',{'enabled':owners.isNotEmpty});}catch(_){}
    });
  }
}
