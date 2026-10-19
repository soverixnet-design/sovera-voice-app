import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as rtc;
import 'firebase_profile.dart';
import 'startup_access.dart' show requestMicrophoneAccess;
import 'voice_connection.dart' show VoiceSeatState, voiceServerUrl;

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
  Future<void> take(int index)async{
    if(busy||!connected||!active||closing)return;
    setState(()=>busy=true);
    try{
      if(!await requestMicrophoneAccess())throw StateError('Microphone denied');
      await mute();
      seats=VoiceSeatState.parse(await request('take',seat:index));
      for(var i=0;i<20&&mounted&&active&&!closing;i++){
        if(room?.localParticipant?.permissions.canPublish==true)break;
        await Future<void>.delayed(const Duration(milliseconds:100));
      }
      if(!mounted||!active||closing){await request('leave');return;}
      if(seats.mine!=index||room?.localParticipant?.permissions.canPublish!=true)throw StateError('No speaking permission');
      await room!.localParticipant!.setMicrophoneEnabled(true);muted=false;error=null;
    }catch(_){await mute();try{await request('leave');}catch(_){} seats=VoiceSeatState(seats.count,null,seats.occupants);error='Could not enable microphone. Check permission and retry.';}
    finally{busy=false;if(mounted&&!closing)setState((){});}
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
    Row(children:[const Icon(Icons.headset),const SizedBox(width:8),Expanded(child:Text(connected?(muted?'Live audio · Listening':'Live audio · Microphone on'):'Audio disconnected')),if(!connected)TextButton(onPressed:busy||!active?null:connect,child:Text(busy?'Connecting…':'Connect')),if(connected&&seats.mine!=null)TextButton(onPressed:busy?null:leave,child:const Text('Leave seat'))]),
    if(connected)Wrap(spacing:6,children:[for(var i=0;i<seats.count;i++)OutlinedButton(onPressed:busy||seats.occupants.containsKey(i)?null:()=>take(i),child:Text(seats.mine==i?'${i+1} · You':seats.occupants.containsKey(i)?'${i+1} · Busy':'Seat ${i+1}'))]),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.orange)),
  ]));
}
