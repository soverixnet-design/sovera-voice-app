import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_rooms.dart';

/// The room subtree stays in one place while its navigation portal comes/goes.
/// Offstage hides pixels only: voice, seat heartbeat and room presence stay live.
class PersistentRoomLayer extends StatefulWidget {
  final FirebaseProfileApi api;
  final Widget child;
  final Widget Function(FirebaseProfileApi,Map<String,dynamic>,VoidCallback,VoidCallback)? roomBuilder;
  const PersistentRoomLayer({super.key,required this.api,required this.child,this.roomBuilder});
  static Future<void> open(BuildContext context,FirebaseProfileApi api,Map<String,dynamic> room)async{
    final host=context.dependOnInheritedWidgetOfExactType<_RoomScope>()?.host;
    if(host!=null){await host.open(context,room);return;}
    await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>FirebaseRoomChat(api:api,room:room)));
  }
  @override State<PersistentRoomLayer> createState()=>_PersistentRoomLayerState();
}
class _RoomScope extends InheritedWidget {
  final _PersistentRoomLayerState host;
  const _RoomScope({required this.host,required super.child});
  @override bool updateShouldNotify(_RoomScope oldWidget)=>false;
}
class _PersistentRoomLayerState extends State<PersistentRoomLayer> {
  Map<String,dynamic>? room;
  bool minimized=false,leaving=false;
  NavigatorState? root;
  Route<void>? portal;
  GlobalKey<NavigatorState> roomNavigator=GlobalKey<NavigatorState>();
  Future<void> open(BuildContext context,Map<String,dynamic> next)async{
    if(leaving)return;
    if(room!=null&&room!['id']!=next['id']){
      final replace=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Switch rooms?'),content:const Text('Leave your current seat and join this room?'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Stay')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Switch room'))]));
      if(replace!=true||!mounted||!context.mounted)return;
      await leave();
      if(!mounted||!context.mounted)return;
    }
    root=Navigator.of(context,rootNavigator:true);
    if(room==null)setState((){room=Map<String,dynamic>.from(next);roomNavigator=GlobalKey<NavigatorState>();});
    restore();
  }
  void restore(){
    if(room==null||leaving||root==null)return;
    setState(()=>minimized=false);
    if(portal!=null)return;
    portal=MaterialPageRoute<void>(settings:const RouteSettings(name:'/active-room'),builder:(_)=>PopScope<void>(canPop:false,onPopInvokedWithResult:(didPop,result)async{
      if(didPop)return;
      final popped=await roomNavigator.currentState?.maybePop()??false;
      if(!popped&&mounted)minimize();
    },child:const SizedBox.expand()));
    final activePortal=portal!;
    root!.push<void>(activePortal).whenComplete((){if(identical(portal,activePortal))portal=null;});
  }
  void removePortal(){final old=portal;portal=null;if(old!=null&&old.isActive)root?.removeRoute(old);}
  void minimize(){if(room==null||leaving)return;FocusManager.instance.primaryFocus?.unfocus();setState(()=>minimized=true);removePortal();}
  Future<void> leave()async{
    if(room==null||leaving)return;
    setState(()=>leaving=true);
    final old=room!['id'].toString();
    // Settle the old seat before allowing a second room to publish.
    try{await widget.api.call('POST',suffix:'/voice',fields:{'room_id':old,'action':'leave'});}catch(_){}
    if(!mounted)return;
    removePortal();setState((){room=null;minimized=false;leaving=false;});
    await WidgetsBinding.instance.endOfFrame;
  }
  @override void dispose(){
    final old=portal, navigator=root;
    WidgetsBinding.instance.addPostFrameCallback((_){if(navigator?.mounted==true&&old?.isActive==true)navigator!.removeRoute(old!);});
    super.dispose();
  }
  @override Widget build(BuildContext context)=>_RoomScope(host:this,child:Stack(children:[
    widget.child,
    if(room!=null)Offstage(offstage:minimized,child:TickerMode(enabled:!minimized,child:HeroControllerScope.none(child:Navigator(key:roomNavigator,onGenerateRoute:(_)=>MaterialPageRoute<void>(builder:(_)=>widget.roomBuilder?.call(widget.api,room!,minimize,()=>leave())??FirebaseRoomChat(useUploadedDesign:true,api:widget.api,room:room!,onMinimize:minimize,onLeave:()=>leave())))))),
    if(room!=null&&minimized)Positioned(right:14,bottom:90,child:SafeArea(child:Material(color:Colors.transparent,child:InkWell(key:const ValueKey('restore-active-room'),onTap:restore,borderRadius:BorderRadius.circular(24),child:Container(width:174,padding:const EdgeInsets.all(12),decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xff397f89),Color(0xff23254b)]),borderRadius:BorderRadius.circular(24),border:Border.all(color:const Color(0xff90fff0),width:1.5),boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:18,offset:Offset(0,9)),BoxShadow(color:Color(0x554debd4),blurRadius:14)]),child:Row(children:[const Icon(Icons.graphic_eq_rounded,color:Color(0xffa9fff2),size:30),const SizedBox(width:9),Expanded(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${room!['name']}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),const Text('Return to room',style:TextStyle(color:Colors.white70,fontSize:11))]))])))))),
    if(leaving)const Positioned.fill(child:ColoredBox(color:Colors.black54,child:Center(child:CircularProgressIndicator()))),
  ]));
}

class RoomDepthButton extends StatelessWidget {
  final String tooltip;final IconData icon;final VoidCallback onPressed;final bool exit;
  const RoomDepthButton({super.key,required this.tooltip,required this.icon,required this.onPressed,this.exit=false});
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(horizontal:3,vertical:7),child:Tooltip(message:tooltip,child:Material(color:Colors.transparent,child:InkWell(onTap:onPressed,borderRadius:BorderRadius.circular(13),child:Container(width:38,height:38,decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:exit?const [Color(0xffbd637d),Color(0xff542a4f)]:const [Color(0xff478c97),Color(0xff263353)]),borderRadius:BorderRadius.circular(13),border:Border.all(color:Colors.white38),boxShadow:const [BoxShadow(color:Colors.black45,blurRadius:6,offset:Offset(0,4))]),child:Icon(icon,size:23,color:Colors.white))))));
}
