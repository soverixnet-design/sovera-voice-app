import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoiceBackground {
  static const channel=MethodChannel('sovera/voice_background');
  static bool get supported=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  static Future<bool> start({bool microphone=false})async{
    if(!supported)return false;
    try{return await channel.invokeMethod<bool>('start',{'microphone':microphone}).timeout(const Duration(seconds:8))==true;}catch(_){return false;}
  }
  static Future<void> stop()async{if(supported){try{await channel.invokeMethod<void>('stop');}catch(_){}}}
}
