import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

/// Display-only online presence. Never used for seat or microphone permission.
class RoomPresence {
 static final instance=RoomPresence._();RoomPresence._();
 final counts=ValueNotifier<Map<String,int>?>(null);
 RealtimeChannel? channel;String? roomId;bool subscribed=false;
 void start(){
  if(channel!=null||soveraClient.auth.currentUser==null)return;
  final next=soveraClient.channel('sovera-room-directory-v1');channel=next;
  next.onPresenceSync((_){
   final users=<String,Set<String>>{};
   for(final state in next.presenceState()){
    for(final entry in state.presences){
     final room=entry.payload['room_id'],user=entry.payload['user_id'];
     if(room is String&&user is String)users.putIfAbsent(room,()=>{}).add(user);
    }
   }
   counts.value={for(final entry in users.entries)entry.key:entry.value.length};
  }).subscribe((status,error){
   subscribed=status==RealtimeSubscribeStatus.subscribed;
   if(subscribed){unawaited(publish());}else{counts.value=null;}
  });
 }
 Future<void> publish()async{
  if(!subscribed||channel==null)return;
  try{if(roomId==null){await channel!.untrack();}else{await channel!.track({'room_id':roomId,'user_id':soveraClient.auth.currentUser?.id});}}catch(_){}
 }
 void enter(String room){roomId=room;start();unawaited(publish());}
 void leave(String? room){if(room!=roomId)return;roomId=null;unawaited(publish());}
 Future<void> stop()async{roomId=null;subscribed=false;counts.value=null;final old=channel;channel=null;if(old!=null)await soveraClient.removeChannel(old);}
}
