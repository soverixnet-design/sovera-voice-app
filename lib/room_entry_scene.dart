import 'dart:async';
import 'package:flutter/material.dart';
import 'firebase_catalog.dart';
import 'app_preferences.dart';

/// Arrival artwork occupies the room viewport, independently of mic geometry.
class RoomEntryScene extends StatefulWidget{
 final List<Map<String,dynamic>> events;final int serverNow;
 const RoomEntryScene({super.key,required this.events,required this.serverNow});
 @override State<RoomEntryScene> createState()=>_RoomEntrySceneState();
}
class _RoomEntrySceneState extends State<RoomEntryScene>{
 final seen=<Object>{};final queue=<Map<String,dynamic>>[];
 Map<String,dynamic>? current;Timer? expiry;
 @override void initState(){super.initState();collect();}
 @override void didUpdateWidget(covariant RoomEntryScene old){super.didUpdateWidget(old);collect();}
 void collect(){
  for(final e in widget.events.reversed){
   if(e['asset'] is! Map||(e['asset'] as Map)['kind']!='entry')continue;
   final id=e['event_id'];
   if(id==null||!seen.add(id as Object)||widget.serverNow-(e['created_at'] as num).toInt()>15)continue;
   if(queue.length<8)queue.add(e);
  }
  if(seen.length>400){seen.clear();for(final e in widget.events){if(e['event_id']!=null)seen.add(e['event_id'] as Object);}}
  if(current==null&&queue.isNotEmpty)next();
 }
 void next(){expiry?.cancel();current=queue.isEmpty?null:queue.removeAt(0);if(current!=null)expiry=Timer(const Duration(seconds:10),(){if(mounted)setState(next);});}
 @override void dispose(){expiry?.cancel();super.dispose();}
 @override Widget build(BuildContext context)=>ValueListenableBuilder<bool>(valueListenable:SoveraPreferences.lowData,builder:(context,lowData,child){
  if(current==null||lowData||MediaQuery.disableAnimationsOf(context))return const SizedBox.shrink();
  final asset=Map<String,dynamic>.from(current!['asset'] as Map);
  return IgnorePointer(child:RepaintBoundary(key:const ValueKey('full-room-entry'),child:Stack(fit:StackFit.expand,children:[
   const DecoratedBox(decoration:BoxDecoration(gradient:RadialGradient(colors:[Color(0x7725758a),Color(0x33101b32),Colors.transparent],radius:1))),
   CatalogImage(key:ValueKey(current!['event_id']),asset:asset,fit:BoxFit.contain),
   Positioned(bottom:70,left:20,right:20,child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xdd172a43),borderRadius:BorderRadius.circular(24),border:Border.all(color:const Color(0xffa5fff0)),boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:18,offset:Offset(0,7))]),child:Text('${current!['sender_name']} arrived · ${asset['title']}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold,color:Colors.white)))),
  ])));
 });
}
