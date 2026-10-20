import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as rtc;
import 'firebase_profile.dart';
import 'firebase_catalog.dart';
import 'sovera_visuals.dart' show gold,cyan,pink;
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

/// A native permission sheet temporarily makes Android inactive. Keep RTC
/// connected during that sheet, but always disconnect on real backgrounding.
bool shouldDisconnectVoice(AppLifecycleState state, {required bool requestingMicrophone}) =>
  state != AppLifecycleState.resumed &&
  !(state == AppLifecycleState.inactive && requestingMicrophone);

/// Live audio uses Firebase bearer authentication and server-owned seat leases.
class FirebaseVoicePanel extends StatefulWidget {
  final FirebaseProfileApi api;
  final String roomId;
  final int seatCount;
  final List<Map<String,dynamic>> people;
  const FirebaseVoicePanel({
    super.key,required this.api,required this.roomId,this.seatCount=9,this.people=const [],
  });
  @override State<FirebaseVoicePanel> createState()=>_FirebaseVoicePanelState();
}
class _FirebaseVoicePanelState extends State<FirebaseVoicePanel> with WidgetsBindingObserver {
  rtc.Room? room;
  VoiceSeatState seats=const VoiceSeatState(0,null,{});
  Timer? timer;
  bool busy=false, active=true, closing=false, muted=true;
  bool requestingMicrophone=false;
  String? error;
  int epoch=0;
  bool get connected=>room?.connectionState==rtc.ConnectionState.connected;
  Future<Map<String,dynamic>> request(String action,{int? seat})=>widget.api.call('POST',suffix:'/voice',fields:{'room_id':widget.roomId,'action':action,if(seat!=null)'seat':seat});
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  Map<String,dynamic>? seatPerson(int index){for(final person in widget.people){if(person['uid']==seats.occupants[index])return person;}return null;}
  Widget seatPortrait(int index){final person=seatPerson(index);return person==null?const Icon(Icons.person_rounded,color:gold,size:29):CatalogPortrait(asset:catalogAsset(person['equipped'],'frame'),avatarUrl:person['avatar_url'] as String?,size:56);}
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

  Future<bool> microphonePermission(int generation)async{
    requestingMicrophone=true;
    try{
      if(!await requestMicrophoneAccess())return false;
      // Permission completion and Flutter's resumed event may arrive in either
      // order. Never take/renew a seat until this same room is active again.
      return await waitForMicPublishPermission(
        canPublish:()=>active,
        canContinue:()=>mounted&&!closing&&connected&&generation==epoch,
        checks:30,
      );
    }finally{requestingMicrophone=false;}
  }

  /// Retry publishing without discarding the already-authorized room seat.
  Future<void> enableMic()async{
    if(busy||!canUseMicrophone||seats.mine==null)return;
    setState(()=>busy=true);
    final generation=epoch;
    try{
      if(!await microphonePermission(generation))throw StateError('Microphone denied or room closed');
      if(!canUseMicrophone||generation!=epoch)return;
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
      if(!await microphonePermission(generation))throw StateError('Microphone denied or room closed');
      await mute();
      if(!canUseMicrophone||generation!=epoch)return;
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
    if(shouldDisconnectVoice(state,requestingMicrophone:requestingMicrophone)){epoch++;unawaited(closeAudio().catchError((Object _){}));unawaited(request('leave').then<void>((_){}).catchError((Object _){}));}
    if(mounted)setState((){});
  }
  @override void dispose(){closing=true;WidgetsBinding.instance.removeObserver(this);unawaited(closeAudio().catchError((Object _){}));unawaited(request('leave').then<void>((_){}).catchError((Object _){}));super.dispose();}
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisSize:MainAxisSize.min,children:[
    Row(children:[const Icon(Icons.headset),const SizedBox(width:8),Expanded(child:Text(connected?(muted?'Live audio · Listening':'Live audio · Microphone on'):'Audio disconnected')),if(!connected)TextButton(onPressed:busy||!active?null:connect,child:Text(busy?'Connecting…':'Connect')),]),
    if(connected&&seats.mine!=null)Align(alignment:Alignment.centerRight,child:Wrap(spacing:8,runSpacing:4,children:[
      TextButton(onPressed:busy?null:muted?enableMic:()async{await mute();if(mounted)setState((){});},child:Text(muted?'Enable mic':'Mute')),
      TextButton(onPressed:busy?null:leave,child:const Text('Leave seat')),
    ])),
    // The original Sovera gold-and-blue circular room-seat layout remains
    // visible before voice connects. Seats are interactable ONLY after the
    // LiveKit + server lease session reports an available microphone seat.
    LayoutBuilder(builder:(context,constraints){
      final count=connected&&seats.count>0?seats.count:widget.seatCount;
      final columns=constraints.maxWidth<295?3:4;
      final tileWidth=(constraints.maxWidth-(columns-1)*8)/columns;
      return Wrap(spacing:8,runSpacing:13,children:[
        for(var i=0;i<count;i++)SizedBox(width:tileWidth,
          child:InkWell(
            borderRadius:BorderRadius.circular(52),
            onTap:!connected||busy||seats.occupants.containsKey(i)?null:()=>take(i),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              Container(width:tileWidth.clamp(58.0,80.0).toDouble(),
                height:tileWidth.clamp(58.0,80.0).toDouble(),
                padding:const EdgeInsets.all(5),
                decoration:BoxDecoration(shape:BoxShape.circle,
                  gradient:const LinearGradient(
                    begin:Alignment.topLeft,end:Alignment.bottomRight,
                    colors:[gold,Color(0xFF316F87),Color(0xFFCEA86C)])),
                child:Container(
                  decoration:BoxDecoration(shape:BoxShape.circle,
                    color:const Color(0xFF19263B),
                    border:Border.all(color:cyan.withValues(alpha:.4),width:2)),
                  child:Center(child:seats.occupants.containsKey(i)?seatPortrait(i):const Icon(Icons.weekend_rounded,color:gold,size:29)),
                )),
              const SizedBox(height:6),
              Text(seats.mine==i?'You':seats.occupants.containsKey(i)
                ?'Occupied':'${i+1}',maxLines:1,
                overflow:TextOverflow.ellipsis,
                textAlign:TextAlign.center,
                style:const TextStyle(fontSize:11,color:Colors.white70)),
              if(seats.mine==i&&muted)const Icon(Icons.mic_off_rounded,
                color:pink,size:14),
            ]),
          )),
      ]);
    }),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.orange)),
  ]));
}
