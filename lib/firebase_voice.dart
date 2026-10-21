import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as rtc;
import 'firebase_profile.dart';
import 'app_preferences.dart';
import 'firebase_catalog.dart';
import 'sovera_visuals.dart' show cyan,pink;
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
  final Set<String> blockedUids;
  final bool autoConnect;
  final String roomRole;
  final Set<int> lockedSeats;
  final VoidCallback? onControlsChanged;
  final List<Map<String,dynamic>> people;
  const FirebaseVoicePanel({
    super.key,required this.api,required this.roomId,this.seatCount=9,this.people=const [],this.blockedUids=const {},this.autoConnect=false,this.roomRole='member',this.lockedSeats=const {},this.onControlsChanged,
  });
  @override State<FirebaseVoicePanel> createState()=>_FirebaseVoicePanelState();
}
/// Seat artwork owns the full available square; it is never nested inside
/// another cropped portrait. Entry playback is cosmetic and keyed to occupant.
class FirebaseSeatPortrait extends StatefulWidget {
  final String? uid;
  final Map<String,dynamic>? person;
  final double size;
  const FirebaseSeatPortrait({super.key,this.uid,this.person,this.size=80});
  @override State<FirebaseSeatPortrait> createState()=>_FirebaseSeatPortraitState();
}
class _FirebaseSeatPortraitState extends State<FirebaseSeatPortrait> {
  Timer? timer;
  bool pending=false,playing=false;
  @override void initState(){super.initState();pending=widget.uid!=null;startEntry();}
  void startEntry(){
    if(pending&&widget.person?['uid']==widget.uid&&
        catalogAsset(widget.person?['equipped'],'entry')!=null){
      pending=false;playing=true;
      timer?.cancel();
      timer=Timer(const Duration(milliseconds:3200),(){
        if(mounted)setState(()=>playing=false);
      });
    }
  }
  @override void didUpdateWidget(covariant FirebaseSeatPortrait oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.uid!=widget.uid){timer?.cancel();playing=false;pending=widget.uid!=null;}
    startEntry();
  }
  @override void dispose(){timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    final frame=catalogAsset(widget.person?['equipped'],'frame');
    final entry=catalogAsset(widget.person?['equipped'],'entry');
    final showingEntry=playing&&entry!=null&&!SoveraPreferences.lowData.value&&!MediaQuery.disableAnimationsOf(context);
    Widget portrait(String mode,Map<String,dynamic>? art)=>CatalogPortrait(
      key:ValueKey('${widget.uid}:$mode'),asset:art,
      avatarUrl:widget.person?['avatar_url'] as String?,size:widget.size);
    final content=showingEntry?portrait('entry',entry):
      widget.uid!=null&&frame!=null?portrait('frame',frame):
      Container(key:ValueKey('${widget.uid}:default'),width:widget.size,height:widget.size,
        padding:const EdgeInsets.all(5),
        decoration:const BoxDecoration(shape:BoxShape.circle,
          color:Color(0x4838CFC4)),
        child:Container(decoration:BoxDecoration(shape:BoxShape.circle,
          color:const Color(0xFF20364A),
          border:Border.all(color:Colors.white38,width:1.5)),
          child:widget.uid==null?const Icon(Icons.chair_rounded,color:Colors.white54,size:28):
            portrait('avatar',null)));
    return SizedBox(width:widget.size,height:widget.size,child:AnimatedSwitcher(
      duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:
        const Duration(milliseconds:180),
      child:content));
  }
}
class _FirebaseVoicePanelState extends State<FirebaseVoicePanel> with WidgetsBindingObserver {
  rtc.Room? room;
  VoiceSeatState seats=const VoiceSeatState(0,null,{});
  Timer? timer,retryTimer;
  final suppressed=<String>{};
  int reconnectAttempts=0;
  bool pausedForReconnect=false;
  bool busy=false, active=true, closing=false, muted=true;
  bool requestingMicrophone=false,listeningMuted=false;
  String? error;
  int epoch=0;
  bool get connected=>room?.connectionState==rtc.ConnectionState.connected;
  Future<Map<String,dynamic>> request(String action,{int? seat})=>widget.api.call('POST',suffix:'/voice',fields:{'room_id':widget.roomId,'action':action,if(seat!=null)'seat':seat});
  @override void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    if(widget.autoConnect)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)connect();});
  }
  Map<String,dynamic>? seatPerson(int index){for(final person in widget.people){if(person['uid']==seats.occupants[index])return person;}return null;}
  @override void didUpdateWidget(covariant FirebaseVoicePanel oldWidget){
    super.didUpdateWidget(oldWidget);applyBlocks();
  }
  void applyBlocks(){
    final current=room;
    if(current==null||closing)return;
    for(final participant in current.remoteParticipants.values){
      final blocked=listeningMuted||widget.blockedUids.contains(participant.identity);
      for(final publication in participant.trackPublications.values){
        if(blocked&&publication.subscribed&&suppressed.add(publication.sid)){
          unawaited(publication.unsubscribe().catchError((Object _){
            unawaited(closeAudio().catchError((Object _){}));
          }));
        }else if(!blocked&&suppressed.remove(publication.sid)){
          unawaited(publication.subscribe().catchError((Object _){}));
        }
      }
    }
  }
  void scheduleReconnect(){
    if(closing||!active||reconnectAttempts>=3||retryTimer?.isActive==true)return;
    retryTimer=Timer(Duration(seconds:2*(reconnectAttempts+1)),(){
      if(mounted&&active&&!connected&&!busy)connect();
    });
  }
  void changed(){
    if(!mounted||closing)return;
    applyBlocks();
    if(room?.connectionState==rtc.ConnectionState.reconnecting&&!pausedForReconnect){
      pausedForReconnect=true;muted=true;unawaited(mute());
    }
    if(connected&&pausedForReconnect){
      pausedForReconnect=false;muted=true;unawaited(mute());
      error='Audio restored. Tap Unmute to speak.';
    }
    if(!connected||room?.localParticipant?.permissions.canPublish!=true)muted=true;
    if(room?.connectionState==rtc.ConnectionState.disconnected)scheduleReconnect();
    setState((){});
  }
  Future<void> mute()async{try{await room?.localParticipant?.setMicrophoneEnabled(false);}catch(_){} muted=true;}
  Future<void> connect()async{
    if(busy||closing||!active)return;
    retryTimer?.cancel();
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
      room=candidate;candidate=null;reconnectAttempts=0;room!.addListener(changed);applyBlocks();
      seats=VoiceSeatState.parse(await request('state'));
      timer=Timer.periodic(const Duration(seconds:8),(_)=>sync());
    }catch(_){if(candidate!=null){await candidate.disconnect();await candidate.dispose();}await closeAudio();reconnectAttempts++;error='Voice could not connect. Tap Retry audio or a mic seat.';scheduleReconnect();}
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
      error='Microphone could not start. Check phone permission, then tap Unmute again.';
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
        ?'Seat reserved, but microphone is off. Tap Unmute to retry or Leave seat.'
        :'Could not take this seat. Check permission and retry.';
    }finally{busy=false;if(mounted&&!closing)setState((){});}
  }
  Future<void> seatMenu(int index) async {
    final locked=widget.lockedSeats.contains(index);
    final action=await showDialog<String>(context:context,builder:(dialogContext){
      Widget choice(IconData icon,String label,String value)=>Padding(padding:const EdgeInsets.only(top:12),child:FilledButton.icon(
        style:FilledButton.styleFrom(minimumSize:const Size(double.infinity,48),backgroundColor:const Color(0xEAF3F7FF),foregroundColor:const Color(0xFF214E68),elevation:4,shadowColor:Colors.black54),
        onPressed:()=>Navigator.pop(dialogContext,value),icon:Icon(icon),label:Text(label)));
      return Dialog(backgroundColor:Colors.transparent,child:SingleChildScrollView(child:Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(28),border:Border.all(color:const Color(0xFF8EE7DD)),
        gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF226B78),Color(0xFF34315E),Color(0xFF171D37)]),
        boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:24,offset:Offset(0,10))]),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Mic ${index+1}',style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:Colors.white)),
        if(!seats.occupants.containsKey(index))choice(Icons.mic_rounded,'Take mic','take'),
        choice(locked?Icons.lock_open:Icons.lock_rounded,locked?'Unlock seat':'Lock seat',locked?'unlock':'lock'),
        choice(Icons.lock_outline,'Lock all seats','lockAll'),
        choice(Icons.lock_open,'Unlock all seats','unlockAll'),
        const SizedBox(height:12),TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel',style:TextStyle(color:Colors.white70))),
      ]))));
    });
    if(action==null||!mounted)return;
    if(action=='take'){await seatTap(index);return;}
    try{
      await widget.api.call('PUT',suffix:'/rooms/${widget.roomId}/seat-lock',fields:{'locked':action=='lock'||action=='lockAll',if(!action.endsWith('All'))'seat':index});
      widget.onControlsChanged?.call();
    }catch(_){if(mounted)setState(()=>error='Could not change seat lock. Please retry.');}
  }
  Future<void> seatTap(int index)async{
    if(widget.lockedSeats.contains(index)&&widget.roomRole=='member'){setState(()=>error='This mic seat is locked.');return;}
    if(busy||closing||!active)return;
    if(!connected)await connect();
    if(!mounted||!connected)return;
    if(seats.occupants.containsKey(index))return;
    await take(index);
  }

  Future<void> leave()async{
    if(busy)return;setState(()=>busy=true);
    await mute();
    try{seats=VoiceSeatState.parse(await request('leave'));error=null;}
    catch(_){error='Could not confirm seat release. Microphone is off.';}
    finally{busy=false;if(mounted&&!closing)setState((){});}
  }
  Future<void> closeAudio()async{
    timer?.cancel();timer=null;suppressed.clear();
    final old=room;room=null;
    if(old!=null){old.removeListener(changed);try{await old.localParticipant?.setMicrophoneEnabled(false);await old.disconnect();}finally{await old.dispose();}}
    muted=true;seats=const VoiceSeatState(0,null,{});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    active=state==AppLifecycleState.resumed;
    retryTimer?.cancel();
    if(active){reconnectAttempts=0;if(room==null)scheduleReconnect();}
    if(shouldDisconnectVoice(state,requestingMicrophone:requestingMicrophone)){epoch++;unawaited(closeAudio().catchError((Object _){}));unawaited(request('leave').then<void>((_){}).catchError((Object _){}));}
    if(mounted)setState((){});
  }
  @override void dispose(){closing=true;retryTimer?.cancel();WidgetsBinding.instance.removeObserver(this);unawaited(closeAudio().catchError((Object _){}));unawaited(request('leave').then<void>((_){}).catchError((Object _){}));super.dispose();}
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisSize:MainAxisSize.min,children:[
    Row(children:[
      Icon(connected?Icons.graphic_eq:Icons.wifi_tethering,color:connected?cyan:Colors.white38,size:17),
      const SizedBox(width:6),
      const Spacer(),
      if(busy)const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)),
      IconButton(tooltip:listeningMuted?'Enable room sound':'Mute room sound',onPressed:()=>setState((){listeningMuted=!listeningMuted;applyBlocks();}),icon:Icon(listeningMuted?Icons.volume_off_rounded:Icons.volume_up_rounded,size:20)),
      if(error!=null&&!connected)TextButton(onPressed:busy?null:connect,child:const Text('Retry audio')),
    ]),
    if(connected&&seats.mine!=null)Align(alignment:Alignment.centerRight,child:Wrap(spacing:8,runSpacing:4,children:[
      TextButton.icon(onPressed:busy?null:muted?enableMic:()async{await mute();if(mounted)setState((){});},icon:Icon(muted?Icons.mic_off_rounded:Icons.mic_rounded),label:Text(muted?'Unmute':'Mute')),
      TextButton(onPressed:busy?null:leave,child:const Text('Leave seat')),
    ])),
    // The original Sovera gold-and-blue circular room-seat layout remains
    // visible before voice connects. Seats are interactable ONLY after the
    // LiveKit + server lease session reports an available microphone seat.
    LayoutBuilder(builder:(context,constraints){
      final count=connected&&seats.count>0?seats.count:widget.seatCount;
      final preferred=count==6||count==9?3:count>=15?5:count==12?4:5;
      final columns=min(preferred,max(1,(constraints.maxWidth/62).floor()));
      final tileWidth=(constraints.maxWidth-(columns-1)*8)/columns;
      return Wrap(spacing:8,runSpacing:13,children:[
        for(var i=0;i<count;i++)SizedBox(width:tileWidth,
          child:InkWell(
            borderRadius:BorderRadius.circular(52),
            onTap:busy?null:widget.roomRole!='member'?()=>seatMenu(i):seats.occupants.containsKey(i)?null:()=>seatTap(i),
            onLongPress:busy||widget.roomRole=='member'?null:()=>seatMenu(i),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              Stack(alignment:Alignment.center,children:[FirebaseSeatPortrait(
                key:ValueKey('seat-portrait-$i'),
                uid:seats.occupants[i],person:seatPerson(i),
                size:tileWidth.clamp(48.0,66.0).toDouble()),
                if(widget.lockedSeats.contains(i)&&!seats.occupants.containsKey(i))const Icon(Icons.lock_rounded,color:Color(0xFFFFD785),size:30),
              ]),
              const SizedBox(height:6),
              Text(seats.mine==i?'You':seats.occupants.containsKey(i)
                ?(seatPerson(i)?['name']?.toString()??'Occupied'):'Mic ${i+1}',maxLines:1,
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
