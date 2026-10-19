import 'dart:async';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';

/// Room-based XO duel. The server owns turns and results; no wallet API is used.
class FirebaseDuelPage extends StatefulWidget {
  final FirebaseProfileApi api;
  final String roomId;
  const FirebaseDuelPage({super.key,required this.api,required this.roomId});
  @override State<FirebaseDuelPage> createState()=>_FirebaseDuelPageState();
}
class _FirebaseDuelPageState extends State<FirebaseDuelPage>{
  Timer? poller;
  Map<String,dynamic>? game;
  bool busy=false;
  String? error;
  String get endpoint=>'/rooms/${Uri.encodeComponent(widget.roomId)}/duel';
  @override void initState(){super.initState();load();poller=Timer.periodic(const Duration(seconds:2),(_)=>load());}
  @override void dispose(){poller?.cancel();super.dispose();}
  Future<void> load()async{
    if(busy)return;
    try{
      final data=await widget.api.call('GET',suffix:endpoint);
      if(mounted)setState((){game=data;error=null;});
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load this room game.');}
  }
  Future<void> action(String operation,[Map<String,dynamic> data=const {}])async{
    if(busy)return;
    setState((){busy=true;error=null;});
    try{
      final result=await widget.api.call('POST',suffix:'$endpoint/$operation',fields:data);
      if(mounted)setState(()=>game=result);
    }catch(e){
      if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Game changed. Refresh to try again.');
      await loadAfterError();
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> loadAfterError()async{
    try{
      final fresh=await widget.api.call('GET',suffix:endpoint);
      if(mounted)setState(()=>game=fresh);
    }catch(_){}
  }
  @override Widget build(BuildContext context){
    final current=game;
    final board=(current?['board'] is List)
      ? List<String>.from(current!['board'] as List)
      : List<String>.filled(9,'.');
    final x=current?['player_x'] as String?;
    final o=current?['player_o'] as String?;
    final winner=current?['winner'] as String?;
    final ready=current?['ready']==true;
    final member=widget.api.uid==x||widget.api.uid==o;
    final myTurn=ready&&winner==null&&current?['turn_uid']==widget.api.uid;
    final revision=current?['revision'] as int? ?? 0;
    final waitingCount=current?['waiting_count'] as int? ?? 0;
    final queuePosition=current?['my_waiting_position'] as int?;
    final nextAllowedAt=current?['next_allowed_at_ms'] as int?;
    final canNext=winner!=null&&
      (nextAllowedAt==null||DateTime.now().millisecondsSinceEpoch>=nextAllowedAt);
    final xName=current?['name_x']?.toString()??'Waiting…';
    final oName=current?['name_o']?.toString()??'Waiting…';
    return Scaffold(appBar:AppBar(title:const Text('XO Duel · 1v1'),actions:[
      IconButton(tooltip:'Refresh game',onPressed:busy?null:load,icon:const Icon(Icons.refresh_rounded)),
    ]),body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Any room member can play · free game · no coin betting',
        style:TextStyle(color:Colors.white70),textAlign:TextAlign.center),
      if(busy)const LinearProgressIndicator(),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),
        child:Text(error!,style:const TextStyle(color:Colors.orange))),
      Card(child:ListTile(leading:const Icon(Icons.groups_rounded),
        title:Text('X: $xName'),
        subtitle:Text('O: $oName'),
      )),
      if(current==null)const Padding(padding:EdgeInsets.all(22),child:Center(child:CircularProgressIndicator()))
      else if(!member&&queuePosition==null)
        FilledButton.icon(onPressed:busy?null:()=>action('join'),
          icon:const Icon(Icons.play_arrow_rounded),
          label:Text(ready?'Join next match queue':'Join 1v1 game')),
      if(queuePosition!=null)
        Card(child:ListTile(
          leading:const Icon(Icons.hourglass_bottom_rounded,color:Colors.amber),
          title:Text('Your queue position: #$queuePosition'),
          subtitle:Text('$waitingCount user(s) waiting for the next match'),
          trailing:TextButton(onPressed:busy?null:()=>action('cancel'),
            child:const Text('Cancel')),
        )),
      if(current!=null&&!ready)
        const Padding(padding:EdgeInsets.symmetric(vertical:12),
          child:Text('Waiting for a second player in this room.',textAlign:TextAlign.center)),
      if(current!=null&&ready&&winner==null)
        Text(myTurn?'Your turn':member?'Opponent’s turn':'Spectating',
          textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(winner!=null)
        Padding(padding:const EdgeInsets.all(10),
          child:Text(winner=='draw'?'Draw!':'$winner wins!',
            textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.amber))),
      if(waitingCount>0&&queuePosition==null)
        Text('$waitingCount player(s) queued for the next match.',
          textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70)),
      const SizedBox(height:8),
      Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:340),child:
        AspectRatio(aspectRatio:1,child:GridView.builder(
          physics:const NeverScrollableScrollPhysics(),itemCount:9,
          gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:3,mainAxisSpacing:5,crossAxisSpacing:5),
          itemBuilder:(context,i)=>OutlinedButton(
            onPressed:busy||!myTurn||board[i]!='.'?null:()=>action('move',{'cell':i,'revision':revision}),
            style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
              backgroundColor:const Color(0xFF312452)),
            child:Text(board[i]=='.'?'':board[i],
              style:TextStyle(fontSize:42,fontWeight:FontWeight.bold,
                color:board[i]=='X'?Colors.cyanAccent:Colors.pinkAccent)),
          ),
        )))),
      const SizedBox(height:20),
      if(winner!=null)FilledButton.icon(
        onPressed:busy||!canNext?null:()=>action('restart'),
        icon:const Icon(Icons.replay_rounded),
        label:Text(canNext?'Start next match · Queue first':'Showing winner…')),
      if(winner!=null)const Padding(padding:EdgeInsets.only(top:8),
        child:Text('Waiting players get priority; any room member may start the next match.',
          textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Colors.white70))),
      const Padding(padding:EdgeInsets.symmetric(vertical:12),
        child:Text('Moves, turns and wins are confirmed by the server. Players can join the waiting queue and rotate after a completed match.',
          style:TextStyle(color:Colors.white60,fontSize:12),textAlign:TextAlign.center)),
    ])));
  }
}
