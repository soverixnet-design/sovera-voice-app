import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_rewards.dart' show RewardAvatar;
import 'sovera_visuals.dart' show Glass,cyan,gold;

class FirebaseRoomRewards extends StatefulWidget{
 final FirebaseProfileApi api;final String roomId;
 const FirebaseRoomRewards({super.key,required this.api,required this.roomId});
 @override State<FirebaseRoomRewards> createState()=>_FirebaseRoomRewardsState();
}
class _FirebaseRoomRewardsState extends State<FirebaseRoomRewards>{
 Map<String,dynamic>? data;String? error;
 @override void initState(){super.initState();load();}
 Future<void> load()async{try{final value=await widget.api.call('GET',suffix:'/rooms/${Uri.encodeComponent(widget.roomId)}/rewards');if(mounted)setState((){data=value;error=null;});}catch(_){if(mounted)setState(()=>error='Could not load room rewards. Please retry.');}}
 Widget person(Map p,String amount)=>ListTile(leading:RewardAvatar(person:Map<String,dynamic>.from(p),size:42),title:Text('${p['name']}',maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('ID ${p['public_id']}'),trailing:Text(amount,style:const TextStyle(color:gold,fontWeight:FontWeight.bold)));
 @override Widget build(BuildContext context){
 final current=data?['current'] as Map?;
 return Scaffold(appBar:AppBar(title:const Text('Weekly Room Rewards')),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
  if(data==null&&error==null)const Center(child:CircularProgressIndicator()),
  if(error!=null)...[Text(error!),TextButton(onPressed:load,child:const Text('Retry'))],
  if(current!=null)...[
   Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.workspace_premium_rounded,color:gold,size:45),const Text('THIS WEEK',style:TextStyle(color:cyan)),Text('${current['percent']}% Room Reward',style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),Text('Gift Coins: ${current['gift_coins']}'),Text('Estimated reward: ${current['reward_coins']} Coins'),Text('Ends: ${DateTime.fromMillisecondsSinceEpoch((current['ends_at'] as num).toInt()*1000,isUtc:true)}'),const SizedBox(height:8),const Text('50% to the room owner. Remaining 50%: five equal shares for the top five other gift senders. Empty shares are not issued. Paid automatically after the week ends; current totals are estimates.')])),
   const SizedBox(height:18),const Text('Estimated shares',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
   for(final p in current['allocations'] as List)person(p as Map,'${p['coins']} Coins'),
   const SizedBox(height:18),const Text('Gift contributors',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
   for(final p in current['contributors'] as List)person(p as Map,'${p['score']}'),
   if((current['contributors'] as List).isEmpty)const Text('No qualifying gifts this week.'),
   const SizedBox(height:18),const Text('Previous weeks',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
   for(final history in data!['history'] as List)Padding(padding:const EdgeInsets.only(top:12),child:Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Week ending ${DateTime.fromMillisecondsSinceEpoch((history['ends_at'] as num).toInt()*1000,isUtc:true)}'),Text('${history['reward_coins']} reward Coins · ${history['percent']}%'),for(final p in history['payouts'] as List)person(p as Map,'${p['coins']} · ${p['paid_at']==null?'Pending':'Paid'}')]))),
  ],
 ])));
 }
}
