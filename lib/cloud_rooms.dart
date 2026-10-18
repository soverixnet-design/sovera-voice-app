import 'package:flutter/material.dart';
import 'main.dart';
import 'room_card.dart';
import 'auth_gate.dart';

/// Authenticated directory. Demo rooms stay separate from persisted rooms.
class CloudRooms extends StatefulWidget {
 final String query, filter;
 const CloudRooms({super.key,required this.query,required this.filter});
 @override State<CloudRooms> createState()=>CloudRoomsState();
}
class CloudRoomsState extends State<CloudRooms>{
 List<Map<String,dynamic>> rows=[];
 Set<String> follows={};
 bool loading=true,writing=false;
 String? error;int revision=0;
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{
  final ticket=++revision;
  setState((){loading=true;error=null;});
  try{
   final data=await soveraClient.from('sovera_rooms').select().eq('is_closed',false).order('created_at',ascending:false).limit(100);
   final saved=await soveraClient.from('sovera_room_follows').select('room_id');
   if(mounted&&ticket==revision)setState((){rows=data;follows=saved.map((r)=>r['room_id'] as String).toSet();loading=false;});
  }catch(_){if(mounted&&ticket==revision)setState((){error='Could not load rooms. Please retry.';loading=false;});}
 }
 void notice(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
 Future<void> myRoom()async{
  if(writing)return;
  final user=soveraClient.auth.currentUser;
  if(user==null)return;
  setState(()=>writing=true);
  try{
   final existing=await soveraClient.from('sovera_rooms').select().eq('owner_id',user.id).maybeSingle();
   if(!mounted)return;
   if(existing!=null){await open(existing);return;}
   final name=await showDialog<String>(context:context,builder:(_)=>const TextEntryDialog(title:'Create your room',maxLength:40,saveLabel:'Create'));
   if(!mounted||name==null)return;
   final room=await soveraClient.from('sovera_rooms').insert({'owner_id':user.id,'name':name}).select().single();
   if(mounted){await refresh();if(mounted)await open(room);}
  }catch(_){notice('Could not open your room. Check your connection and retry.');}
  finally{if(mounted)setState(()=>writing=false);}
 }
 Future<void> open(Map<String,dynamic> room)async{
  await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>VoiceRoom(name:room['name'] as String,roomId:room['id'] as String,ownerId:room['owner_id'] as String,initialSeats:room['seat_count'] as int)));
  if(mounted)await refresh();
 }
 Future<void> follow(Map<String,dynamic> room)async{
  if(writing)return;
  final id=room['id'] as String;
  final user=soveraClient.auth.currentUser;
  if(user==null)return;
  setState(()=>writing=true);
  try{
   if(follows.contains(id)){
    await soveraClient.from('sovera_room_follows').delete().eq('user_id',user.id).eq('room_id',id);
    if(mounted)setState(()=>follows.remove(id));
   }else{
    await soveraClient.from('sovera_room_follows').insert({'user_id':user.id,'room_id':id});
    if(mounted)setState(()=>follows.add(id));
   }
  }catch(_){notice('Could not save your room follow. Please retry.');}
  finally{if(mounted)setState(()=>writing=false);}
 }
 @override Widget build(BuildContext context){
  final visible=rows.where((r)=>(r['name'] as String).toLowerCase().contains(widget.query.trim().toLowerCase())&&(widget.filter!='Following'||follows.contains(r['id']))).toList();
  if(widget.filter=='All')visible.sort((a,b)=>(a['name'] as String).compareTo(b['name'] as String));
  return Column(children:[
   Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[const Text('Community rooms',style:TextStyle(fontWeight:FontWeight.bold)),IconButton(tooltip:'Refresh rooms',onPressed:loading?null:refresh,icon:const Icon(Icons.refresh_rounded)),FilledButton.icon(onPressed:writing?null:myRoom,icon:const Icon(Icons.add),label:const Text('My room'))]),
   const SizedBox(height:12),
   if(loading)const Padding(padding:EdgeInsets.all(24),child:CircularProgressIndicator())
   else if(error!=null)TextButton(onPressed:refresh,child:Text(error!))
   else if(visible.isEmpty)const Glass(child:Text('No rooms here yet. Create your room or follow a community room.'))
   else LayoutBuilder(builder:(context,c)=>GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:visible.length,gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:c.maxWidth<300?1:2,mainAxisExtent:260+30*(MediaQuery.textScalerOf(context).scale(1)-1),crossAxisSpacing:12,mainAxisSpacing:12),itemBuilder:(context,i){
    final room=visible[i],id=visible[i]['id'] as String;
    return RoomCard(name:room['name'] as String,category:room['category'] as String,subtitle:'${room['seat_count']} seats · Voice coming soon',color:i.isEven?violet:cyan,followed:follows.contains(id),onOpen:()=>open(room),onFollow:writing?null:()=>follow(room));
   })),

  ]);
 }
}
