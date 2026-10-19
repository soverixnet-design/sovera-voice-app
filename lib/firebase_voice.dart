import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as rtc;
import 'firebase_profile.dart';
import 'startup_access.dart' show requestMicrophoneAccess;
import 'voice_connection.dart' show VoiceSeatState, voiceServerUrl;

/// The server grants microphone publishing asynchronously after a seat lease.
/// Do not discard a valid seat just because the RTC permission event is slow.
Future<bool> waitForMicPublishPermission({
  required bool Function() canPublish,
  required bool Function() canContinue,
  int checks=80,
  Duration interval=const Duration(milliseconds:100),
  Future<void> Function(Duration)? wait,
}) async {
  for(var i=0;i<checks;i++){
    if(!canContinue())return false;
    if(canPublish())return true;
    if(i+1<checks){
      if(wait!=null){await wait(interval);}
      else{await Future<void>.delayed(interval);}
    }
  }
  return false;
}

/// Live audio uses Firebase bearer authentication and server-owned seat leases.
class FirebaseVoicePanel extends StatefulWidget {
  final FirebaseProfileApi api;
  final String roomId;
  const FirebaseVoicePanel({super.key, required this.api, required this.roomId});
  @override State<FirebaseVoicePanel> createState()=>_FirebaseVoicePanelState();
}
class _FirebaseVoicePanelState extends State<FirebaseVoicePanel> with WidgetsBindingObserver {
  rtc.Room? room;
  VoiceSeatState seats=const VoiceSeatState(0,null,{});
  Timer? timer;
  bool busy=false, active=true, closing=false, muted=true;
  String? error;
  int epoch=0;
  bool get connected=>room?.connectionState==rtc.ConnectionState.connected;
  Future<Map<String,dynamic>> request(String action,{int? seat})=>widget.api.call('POST',suffix:'/voice',fields:{'room_id':widget.roomId,'action':action,if(seat!=null)'seat':seat});
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  void changed(){if(mounted&&!closing){if(!connected||room?.localParticipant?.permissions.canPublish!=true)muted=true;setState((){});}}
  Future<void> mute()async{try{await room?.localParticipant?.setMicrophoneEnabled(false);}catch(_){} muted=true;}
  Future<void> connect()async{
    if(busy||closing||!active)return;
    setState((){busy=true;error=null;});
    final generation=epoch;
    rtc.Room? candidate;
    try{
      await closeAudio();
      final data=await request('join');
      if(data['url']!=voiceServerUrl||data['token'] is! String)throw StateError('Invalid voice response');
      if(!mounted||closing||!active||generation!=epoch)return;
      candidate=rtc.Room();
      await candidate.connect(voiceServerUrl,data['token'] as String);
      if(!mounted||closing||!active||generation!=epoch){await candidate.disconnect();await candidate.dispose();candidate=null;return;}
      room=candidate;candidate=null;room!.addListener(changed);
      seats=VoiceSeatState.parse(await request('state'));
      timer=Timer.periodic(const Duration(seconds:8),(_)=>sync());
    }catch(_){if(candidate!=null){await candidate.disconnect();await candidate.dispose();}await closeAudio();error='Voice could not connect. Tap Connect to retry.';}
    finally{if(mounted&&!closing)setState(()=>busy=false);}
  }
  Future<void> sync()async{
    if(busy||!connected||!active||closing)return;
    busy=true;
    try{seats=VoiceSeatState.parse(await request(seats.mine==null?'state':'renew'));if(seats.mine==null)await mute();error=null;}
    catch(_){await mute();seats=VoiceSeatState(seats.count,null,seats.occupants);error='Seat connection lost. Take a seat again.';}
    finally{busy=false;if(mounted&&!closing)setState((){});}
  }
  bool get canUseMicrophone=>mounted&&active&&!closing&&connected;
  Future<bool> awaitPublishPermission(int generation)=>waitForMicPublishPermission(
    canPublish:()=>room?.localParticipant?.permissions.canPublish==true,
    canContinue:()=>canUseMicrophone&&generation==epoch,
  );

  /// Retry publishing without discarding the already-authorized room seat.
  Future<void> enableMic()async{
    if(busy||!canUseMicrophone||seats.mine==null)return;
    setState(()=>busy=true);
    final generation=epoch;
    try{
      if(!await requestMicrophoneAccess())throw StateError('Microphone denied');
      seats=VoiceSeatState.parse(await request('renew'));
      if(seats.mine==null)throw StateError('Seat expired');
      if(!await awaitPublishPermission(generation))throw StateError('Publish permission delayed');
      if(!canUseMicrophone||generation!=epoch)return;
      await room!.localParticipant!.setMicrophoneEnabled(true);
      muted=false;error=null;
    }catch(_){
      await mute();
      error='Microphone could not start. Check phone permission, then tap Enable mic again.';
    }finally{busy=false;if(mounted&&!closing)setState((){});}
  }

  Future<void> take(int index)async{
    if(busy||!canUseMicrophone)return;
    setState(()=>busy=true);
    final generation=epoch;
    try{
      if(!await requestMicrophoneAccess())throw StateError('Microphone denied');
      await mute();
      seats=VoiceSeatState.parse(await request('take',seat:index));
      if(seats.mine!=index)throw StateError('Seat not granted');
      if(!await awaitPublishPermission(generation))throw StateError('Publish permission delayed');
      if(!canUseMicrophone||generation!=epoch)return;
      await room!.localParticipant!.setMicrophoneEnabled(true);
      muted=false;error=null;
    }catch(_){
      await mute();
      error=seats.mine==index
        ?'Seat reserved, but microphone is off. Tap Enable mic to retry or Leave seat.'
        :'Could not take this seat. Check permission and retry.';
    }finally{busy=false;if(mounted&&!closing)setState((){});}
  }

  Future<void> leave()async{
    if(busy)return;setState(()=>busy=true);
    await mute();
    try{seats=VoiceSeatState.parse(await request('leave'));error=null;}
    catch(_){error='Could not confirm seat release. Microphone is off.';}
    finally{busy=false;if(mounted&&!closing)setState((){});}
  }
  Future<void> closeAudio()async{
    timer?.cancel();timer=null;
    final old=room;room=null;
    if(old!=null){old.removeListener(changed);try{await old.localParticipant?.setMicrophoneEnabled(false);await old.disconnect();}finally{await old.dispose();}}
    muted=true;seats=const VoiceSeatState(0,null,{});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    active=state==AppLifecycleState.resumed;
    if(!active){epoch++;unawaited(closeAudio().catchError((Object _){}));unawaited(request('leave').then<void>((_){}).catchError((Object _){}));}
    if(mounted)setState((){});
  }
  @override void dispose(){closing=true;WidgetsBinding.instance.removeObserver(this);unawaited(closeAudio().catchError((Object _){}));unawaited(request('leave').then<void>((_){}).catchError((Object _){}));super.dispose();}
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisSize:MainAxisSize.min,children:[
    Row(children:[const Icon(Icons.headset),const SizedBox(width:8),Expanded(child:Text(connected?(muted?'Live audio · Listening':'Live audio · Microphone on'):'Audio disconnected')),if(!connected)TextButton(onPressed:busy||!active?null:connect,child:Text(busy?'Connecting…':'Connect')),]),
    if(connected&&seats.mine!=null)Align(alignment:Alignment.centerRight,child:Wrap(spacing:8,runSpacing:4,children:[
      TextButton(onPressed:busy?null:muted?enableMic:()async{await mute();if(mounted)setState((){});},child:Text(muted?'Enable mic':'Mute')),
      TextButton(onPressed:busy?null:leave,child:const Text('Leave seat')),
    ])),
    if(connected)Wrap(spacing:6,children:[for(var i=0;i<seats.count;i++)OutlinedButton(onPressed:busy||seats.occupants.containsKey(i)?null:()=>take(i),child:Text(seats.mine==i?'${i+1} · You':seats.occupants.containsKey(i)?'${i+1} · Busy':'Seat ${i+1}'))]),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.orange)),
  ]));
}
