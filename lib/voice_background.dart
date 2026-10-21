import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoiceBackground {
  static bool running=false;
  static const channel=MethodChannel('sovera/voice_background');
  static bool get supported=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  static Future<bool> start({bool microphone=false})async{
    if(!supported)return false;
    try{running=await channel.invokeMethod<bool>('start',{'microphone':microphone}).timeout(const Duration(seconds:8))==true;return running;}catch(_){running=false;try{channel.invokeMethod<void>('stop').catchError((Object _){});}catch(_){}return false;}
  }
  static Future<void> stop()async{if(supported&&running){running=false;try{await channel.invokeMethod<void>('stop').timeout(const Duration(seconds:2));}catch(_){}}}
}
