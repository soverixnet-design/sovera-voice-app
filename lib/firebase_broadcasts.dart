import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';

/// Lives above the Navigator, so room changes, dialogs and games keep the feed.
class GlobalCelebrationLayer extends StatefulWidget {
  final FirebaseProfileApi api;
  final Widget child;
  const GlobalCelebrationLayer({super.key,required this.api,required this.child});
  @override State<GlobalCelebrationLayer> createState()=>_GlobalCelebrationLayerState();
}
class _GlobalCelebrationLayerState extends State<GlobalCelebrationLayer> with SingleTickerProviderStateMixin,WidgetsBindingObserver {
  late final AnimationController motion=AnimationController(vsync:this,duration:const Duration(seconds:10));
  final queue=Queue<Map<String,dynamic>>();
  int? cursor;
  bool fetching=false,active=true;
  Map<String,dynamic>? current;
  Timer? timer,expiry;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);poll();timer=Timer.periodic(const Duration(seconds:3),(_)=>poll());}
  Future<void> poll()async{
    if(fetching||!active)return;
    fetching=true;
    try{
      final reply=await widget.api.call('GET',suffix:'/broadcasts${cursor==null?'':'?after=$cursor'}');
      if(!mounted||!active)return;
      final rows=reply['items'],newCursor=reply['cursor'],now=reply['server_now'];
      if(rows is! List||newCursor is! int||now is! int)return;
      for(final raw in rows.whereType<Map>()){
        final event=Map<String,dynamic>.from(raw);
        final id=event['id'],created=event['created_at'];
        if(id is! int||created is! int||(cursor!=null&&id<=cursor!)||now-created>90||!['win','gift'].contains(event['kind']))continue;
        if(queue.length<64)queue.add(event);
      }
      cursor=newCursor;
      if(current==null)next();
    }catch(_){/* A celebration outage never blocks rooms, games or the wallet. */}
    finally{fetching=false;}
  }
  void next(){
    if(!mounted||!active)return;
    expiry?.cancel();
    motion.stop();
    setState(()=>current=queue.isEmpty?null:queue.removeFirst());
    if(current!=null){motion.forward(from:0);expiry=Timer(const Duration(seconds:10),next);}
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    active=state==AppLifecycleState.resumed;
    if(!active){expiry?.cancel();motion.stop();queue.clear();setState(()=>current=null);}else{poll();}
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);timer?.cancel();expiry?.cancel();motion.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Stack(children:[widget.child,
    if(current!=null)Positioned(top:MediaQuery.paddingOf(context).top+46,left:0,right:0,
      child:IgnorePointer(child:LayoutBuilder(builder:(context,box){
        final width=box.maxWidth>470?450.0:box.maxWidth-20;
        return AnimatedBuilder(animation:motion,builder:(context,child){
          final reduced=MediaQuery.disableAnimationsOf(context);
          final x=reduced?(box.maxWidth-width)/2:box.maxWidth-(box.maxWidth+width)*motion.value;
          return Transform.translate(offset:Offset(x,0),child:Align(alignment:Alignment.centerLeft,child:SizedBox(width:width,child:child)));
        },child:CelebrationBanner(event:current!));
      }))),
  ]);
}

class CelebrationBanner extends StatelessWidget {
  final Map<String,dynamic> event;
  const CelebrationBanner({super.key,required this.event});
  Map<String,dynamic> person(String key)=>event[key] is Map?Map<String,dynamic>.from(event[key] as Map):{};
  Widget portrait(Map<String,dynamic> person)=>Container(width:40,height:40,
    decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:const Color(0xFFFFE1A0),width:2),boxShadow:const [BoxShadow(color:Colors.black54,offset:Offset(0,3),blurRadius:5)]),
    child:ClipOval(child:person['avatar_url'] is String?Image.network(person['avatar_url'] as String,fit:BoxFit.cover,errorBuilder:(_,error,stack)=>const Icon(Icons.person,color:Colors.white)):const Icon(Icons.person,color:Colors.white)));
  String label(Map<String,dynamic> p)=>'${p['name']??'Sovera member'}${p['public_id']==null?'':' · ID ${p['public_id']}'}';
  @override Widget build(BuildContext context){
    final win=event['kind']=='win';
    final first=person(win?'winner':'sender'),second=person('recipient');
    final gift=event['gift'] is Map?event['gift'] as Map:{};
    return Semantics(label:win?'${label(first)} won ${event['coins']} Coins in ${event['game']}':'${label(first)} sent ${gift['title']} to ${label(second)}',
      child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),
          gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:win?const [Color(0xFFAD6017),Color(0xFF6332A7),Color(0xFF20163C)]:const [Color(0xFFC6409D),Color(0xFF6534A7),Color(0xFF20234F)]),
          border:Border.all(color:const Color(0xFFFFD985),width:1.5),boxShadow:const [BoxShadow(color:Color(0xAA000000),blurRadius:14,offset:Offset(0,6)),BoxShadow(color:Color(0x554B1C97),blurRadius:18,spreadRadius:2)]),
        child:Row(children:[portrait(first),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          Text(label(first),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w800,decoration:TextDecoration.none)),
          const SizedBox(height:3),
          Text(win?'${event['game']} · Won ${event['coins']} Coins':'→ ${label(second)}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Color(0xFFFFE3A0),fontSize:11,fontWeight:FontWeight.bold,decoration:TextDecoration.none)),
          if(!win)Text('${gift['title']} × ${gift['count']??1}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:Colors.white,decoration:TextDecoration.none)),
        ])),const SizedBox(width:5),
          if(win)const Icon(Icons.emoji_events_rounded,color:Color(0xFFFFD46D),size:34)
          else ...[portrait(second),const SizedBox(width:4),SizedBox(width:30,height:30,child:gift['url'] is String?Image.network(gift['url'] as String,errorBuilder:(_,error,stack)=>const Icon(Icons.card_giftcard,color:Colors.amber)):const Icon(Icons.card_giftcard,color:Colors.amber))],
        ])));
  }
}
