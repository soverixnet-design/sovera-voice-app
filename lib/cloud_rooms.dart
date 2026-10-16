import 'package:flutter/material.dart';
import 'main.dart';
import 'supabase_config.dart';

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
 String? error;
 @override void initState(){super.initState();refresh();}
 Future<void> refresh()async{
  setState((){loading=true;error=null;});
  try{
   final data=await soveraClient.from('sovera_rooms').select().order('created_at',ascending:false).limit(100);
   final saved=await soveraClient.from('sovera_room_follows').select('room_id');
   if(mounted)setState((){rows=data;follows=saved.map((r)=>r['room_id'] as String).toSet();loading=false;});
  }catch(_){if(mounted)setState((){error='Could not load rooms. Please retry.';loading=false;});}
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
   final controller=TextEditingController();
   final name=await showDialog<String>(context:context,builder:(context)=>AlertDialog(title:const Text('Create your room'),content:TextField(controller:controller,maxLength:40,decoration:const InputDecoration(labelText:'Room name')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){final name=controller.text.trim();if(name.isNotEmpty)Navigator.pop(context,name);},child:const Text('Create'))]));
   await Future<void>.delayed(const Duration(milliseconds:300));
   controller.dispose();
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
  final visible=rows.where((r)=>(r['name'] as String).toLowerCase().contains(widget.query.toLowerCase())&&(widget.filter!='Following'||follows.contains(r['id']))).toList();
  if(widget.filter=='All')visible.sort((a,b)=>(a['name'] as String).compareTo(b['name'] as String));
  return Column(children:[
   Row(children:[const Expanded(child:Text('Community rooms',style:TextStyle(fontWeight:FontWeight.bold))),IconButton(tooltip:'Refresh rooms',onPressed:loading?null:refresh,icon:const Icon(Icons.refresh_rounded)),FilledButton.icon(onPressed:writing?null:myRoom,icon:const Icon(Icons.add),label:const Text('My room'))]),
   const SizedBox(height:12),
   if(loading)const Padding(padding:EdgeInsets.all(24),child:CircularProgressIndicator())
   else if(error!=null)TextButton(onPressed:refresh,child:Text(error!))
   else if(visible.isEmpty)const Glass(child:Text('No rooms here yet. Create your room or follow a community room.'))
   else GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:visible.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,mainAxisExtent:210,crossAxisSpacing:12,mainAxisSpacing:12),itemBuilder:(context,i){
    final room=visible[i],id=visible[i]['id'] as String;
    return InkWell(onTap:()=>open(room),borderRadius:BorderRadius.circular(26),child:Glass(tint:i.isEven?violet:cyan,padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Row(children:[Expanded(child:Text(room['category'] as String,style:const TextStyle(fontSize:10,color:Colors.white60))),IconButton(tooltip:follows.contains(id)?'Unfollow room':'Follow room',onPressed:writing?null:()=>follow(room),icon:Icon(follows.contains(id)?Icons.favorite:Icons.favorite_border,color:pink))]),
     const Expanded(child:Center(child:BrandLogo(size:70))),
     Text(room['name'] as String,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold)),
     const SizedBox(height:6),Text('${room['seat_count']} seats · Voice coming soon',style:const TextStyle(fontSize:10,color:Colors.white60)),
    ])));
   }),
  ]);
 }
}
