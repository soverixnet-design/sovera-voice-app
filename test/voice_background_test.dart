import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/voice_background.dart';

void main(){
 testWidgets('Late start from a closed room is stopped before a newer room starts',(tester)async{
  debugDefaultTargetPlatformOverride=TargetPlatform.android;
  addTearDown(()=>debugDefaultTargetPlatformOverride=null);
  final firstReply=Completer<bool>();final calls=<String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(VoiceBackground.channel,(call)async{
    calls.add(call.method);
    if(call.method=='start'&&calls.length==1)return firstReply.future;
    return true;
  });
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(VoiceBackground.channel,null));
  await tester.runAsync(()async{
    final oldOwner=Object(),newOwner=Object();
    final oldStart=VoiceBackground.start(owner:oldOwner);
    await Future<void>.delayed(Duration.zero);
    final stopOld=VoiceBackground.stop(owner:oldOwner);
    final newStart=VoiceBackground.start(owner:newOwner,microphone:true);
    firstReply.complete(true);
    expect(await oldStart,false);await stopOld;
    expect(await newStart,true);
    expect(calls,['start','stop','start']);
    await VoiceBackground.stop(owner:oldOwner);
    expect(VoiceBackground.running,true);
    await VoiceBackground.stop(owner:newOwner);
    expect(calls,['start','stop','start','stop']);
    expect(VoiceBackground.running,false);
  });
 });
}
