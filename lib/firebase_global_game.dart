import 'dart:async';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';

/// The server is the ONLY source of round IDs, winning colors and rewards.
/// Timers use the last verified server clock plus monotonic elapsed time.
class FirebaseGlobalColorGame extends StatefulWidget {
  final FirebaseProfileApi api;
  const FirebaseGlobalColorGame({super.key,required this.api});
  @override State<FirebaseGlobalColorGame> createState()=>_FirebaseGlobalColorGameState();
}
class _FirebaseGlobalColorGameState extends State<FirebaseGlobalColorGame>
    with WidgetsBindingObserver {
  Map<String,dynamic>? game;
  final Stopwatch syncedClock=Stopwatch();
  Timer? poller;
  Timer? ticker;
  bool fetching=false,sending=false;
  String? error;
  static const endpoint='/games/colors';
  static const shades=<String,Color>{
    'red':Colors.redAccent,'blue':Colors.lightBlueAccent,
    'green':Colors.greenAccent,'gold':Colors.amber,
  };
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    poller=Timer.periodic(const Duration(seconds:1),(_)=>refresh());
    ticker=Timer.periodic(const Duration(milliseconds:250),(_){if(mounted&&game!=null)setState((){});});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)refresh();
  }
  @override void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    poller?.cancel();ticker?.cancel();syncedClock.stop();
    super.dispose();
  }
  void accept(Map<String,dynamic> data){
    if(data['game']!='global-colors'||data['round'] is! int||
       data['server_now_ms'] is! int||data['phase_ends_ms'] is! int||
       data['phase'] is! String||data['history'] is! List){
      throw const ProfileApiError('Invalid global game response.');
    }
    // Only accept newer server revisions; never roll back the displayed round.
    if(game!=null&&(data['round'] as int)<(game!['round'] as int))return;
    syncedClock..reset()..start();
    setState((){game=data;error=null;});
  }
  Future<void> refresh()async{
    if(fetching||sending)return;
    fetching=true;
    try{final data=await widget.api.call('GET',suffix:endpoint);
      if(mounted)accept(data);
    }catch(e){
      if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Cannot connect to the game server.');
    }finally{fetching=false;}
  }
  Future<void> pick(String color)async{
    final round=game?['round'];
    if(sending||round is! int||game?['phase']!='pick'||game?['my_pick']!=null)return;
    setState(()=>sending=true);
    try{
      final data=await widget.api.call('POST',suffix:'$endpoint/pick',
        fields:{'round':round,'choice':color});
      if(mounted)accept(data);
    }catch(e){
      if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Pick could not be saved. Refresh and retry.');
      // A stale round/locked pick must be resolved from authoritative state.
    }finally{
      if(mounted)setState(()=>sending=false);
      refresh();
    }
  }
  int get remaining{
    if(game==null)return 0;
    final serverNow=game!['server_now_ms'] as int;
    final ends=game!['phase_ends_ms'] as int;
    final diff=ends-serverNow-syncedClock.elapsedMilliseconds;
    return diff>0?(diff+999)~/1000:0;
  }
  @override Widget build(BuildContext context){
    final g=game;
    final phase=g?['phase'] as String? ?? 'loading';
    final result=g?['result'] as String?;
    final choice=g?['my_pick'] as String?;
    final winners=(g?['winners'] as List?)??[];
    final history=(g?['history'] as List?)??[];
    final round=g?['round']?.toString()??'—';
    return Scaffold(appBar:AppBar(title:const Text('Global Color Game'),
      actions:[IconButton(tooltip:'Refresh global game',onPressed:refresh,
        icon:const Icon(Icons.refresh_rounded))]),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
        const Text('One round and one result for everyone, across all rooms.',
          textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold)),
        const Padding(padding:EdgeInsets.only(top:6),child:Text(
          'Free game only. No Coins are wagered and no Diamonds are awarded.',
          textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,fontSize:12))),
        if(error!=null)Padding(padding:const EdgeInsets.all(10),child:
          Text(error!,textAlign:TextAlign.center,style:const TextStyle(color:Colors.orange))),
        if(g==null)const Padding(padding:EdgeInsets.all(24),
          child:Center(child:CircularProgressIndicator()))
        else ...[
          Card(child:Padding(padding:const EdgeInsets.all(18),
            child:Column(children:[
              Text('GLOBAL ROUND #$round',style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
              const SizedBox(height:12),
              Text(phase=='pick'?'Choose a color':phase=='reveal'?'Round result':'Next round soon',
                style:const TextStyle(color:Colors.white70)),
              const SizedBox(height:5),
              Text('${remaining}s',style:const TextStyle(fontSize:36,fontWeight:FontWeight.bold,
                fontFeatures:[FontFeature.tabularFigures()])),
              Text('${g['pick_count']} verified picks',
                style:const TextStyle(color:Colors.white60)),
            ]))),
          const SizedBox(height:12),
          if(result==null) ...[
            const Text('Pick one color',textAlign:TextAlign.center,
              style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
            const SizedBox(height:8),
            GridView.count(crossAxisCount:2,shrinkWrap:true,
              physics:const NeverScrollableScrollPhysics(),
              crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:2.2,
              children:[for(final entry in shades.entries)
                FilledButton(
                  onPressed:phase!='pick'||choice!=null||sending?null:()=>pick(entry.key),
                  style:FilledButton.styleFrom(backgroundColor:entry.value,
                    disabledBackgroundColor:choice==entry.key?entry.value.withValues(alpha:.65):Colors.white10,
                    foregroundColor:Colors.black87,disabledForegroundColor:Colors.white),
                  child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                    if(choice==entry.key)const Icon(Icons.check_circle_outline,size:17),
                    const SizedBox(width:5),Flexible(child:Text(entry.key.toUpperCase(),maxLines:1,
                      overflow:TextOverflow.ellipsis)),
                  ]),
                ),
              ]),
            const SizedBox(height:10),
            Text(choice!=null?'Your pick is locked: ${choice.toUpperCase()}':
              phase=='pick'?'Your pick will be confirmed by the server.':'Picking has closed.',
              textAlign:TextAlign.center),
          ] else ...[
            Card(color:shades[result]?.withValues(alpha:.18),
              child:Padding(padding:const EdgeInsets.all(24),
                child:Column(children:[
                  const Icon(Icons.emoji_events_rounded,color:Colors.amber,size:45),
                  const SizedBox(height:8),
                  Text('WINNING COLOR: ${result.toUpperCase()}',
                    style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
                  const SizedBox(height:8),
                  Text('${g['winner_count']} winners this round',
                    style:const TextStyle(fontSize:18)),
                  if(choice!=null)Text(g['my_win']==true?'You picked the winning color!':
                    'Your pick: ${choice.toUpperCase()}',
                    style:const TextStyle(fontWeight:FontWeight.bold)),
                ]))),
            const SizedBox(height:12),
            const Text('Verified winners',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
            if(winners.isEmpty)const ListTile(title:Text('No winning picks this round.'))
            else for(final entry in winners)
              ListTile(leading:const Icon(Icons.emoji_events_rounded,color:Colors.amber),
                title:Text((entry as Map)['name'].toString(),maxLines:1,overflow:TextOverflow.ellipsis)),
          ],
          const SizedBox(height:18),
          const Text('Shared result history',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          for(final item in history.take(8))
            ListTile(dense:true,leading:CircleAvatar(radius:14,
              backgroundColor:shades[(item as Map)['result']]??Colors.grey),
              title:Text('Round #${item['round']}  ·  ${item['result'].toString().toUpperCase()}'),
              trailing:Text('${item['winner_count']} wins')),
        ],
      ])),
    );
  }
}


/// Compact cross-room live result; spectators see the exact same server draw.
/// Polling is bounded and never computes a device-side winner.
class GlobalColorsResultStrip extends StatefulWidget {
  final FirebaseProfileApi api;
  const GlobalColorsResultStrip({super.key,required this.api});
  @override State<GlobalColorsResultStrip> createState()=>_GlobalColorsResultStripState();
}
class _GlobalColorsResultStripState extends State<GlobalColorsResultStrip>{
  Timer? poller;
  bool busy=false;
  Map<String,dynamic>? result;
  @override void initState(){
    super.initState();
    update();
    poller=Timer.periodic(const Duration(seconds:2),(_)=>update());
  }
  @override void dispose(){poller?.cancel();super.dispose();}
  Future<void> update()async{
    if(busy)return;
    busy=true;
    try{
      final round=await widget.api.call('GET',suffix:'/games/colors');
      if(mounted)setState(()=>result=round['game']=='global-colors'?round:null);
    }catch(_){
      if(mounted)setState(()=>result=null);
    }finally{busy=false;}
  }
  @override Widget build(BuildContext context){
    final row=result;
    final winning=row?['result'];
    if(winning is! String)return const SizedBox.shrink();
    return Card(
      color:const Color(0xFF40331C),
      child:ListTile(
        leading:const Icon(Icons.emoji_events_rounded,color:Colors.amber),
        title:Text('GLOBAL WIN · ${winning.toUpperCase()} · Round #${row!['round']}',
          maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text('${row['winner_count']} verified winners · Same in every room',
          maxLines:1,overflow:TextOverflow.ellipsis),
        trailing:const Icon(Icons.chevron_right_rounded),
        onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
          builder:(_)=>FirebaseGlobalColorGame(api:widget.api))),
      ),
    );
  }
}
