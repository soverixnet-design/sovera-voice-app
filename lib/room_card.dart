import 'room_media.dart';
import 'package:flutter/material.dart';
import 'main.dart';

class RoomCard extends StatelessWidget {
 final String name,category,subtitle;
 final String? roomId;
 final Color color;
 final bool followed;
 final VoidCallback onOpen;
 final VoidCallback? onFollow;
 const RoomCard({super.key,this.roomId,required this.name,required this.category,required this.subtitle,required this.onOpen,required this.onFollow,this.followed=false,this.color=violet});
 @override Widget build(BuildContext context)=>Material(
  color:Colors.transparent,
  borderRadius:BorderRadius.circular(24),
  clipBehavior:Clip.antiAlias,
  child:InkWell(onTap:onOpen,child:Ink(
   decoration:BoxDecoration(
    gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[color.withValues(alpha:.38),const Color(0xFF1A1534),const Color(0xFF121327)]),
    border:Border.all(color:color.withValues(alpha:.4)),borderRadius:BorderRadius.circular(24),
   ),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(child:Stack(fit:StackFit.expand,children:[
     Positioned(right:-24,top:24,child:Container(width:115,height:115,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:color.withValues(alpha:.2),width:16)))),
     Center(child:roomId==null?const BrandLogo(size:76):RoomPhoto(roomId:roomId,size:90)),
     Positioned(left:10,top:10,right:46,child:Align(alignment:Alignment.topLeft,child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:Colors.black38,borderRadius:BorderRadius.circular(20)),child:Text(category,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Colors.white))))),
     Positioned(right:0,top:0,child:IconButton(tooltip:followed?'Unfollow room':'Follow room',onPressed:onFollow,icon:Icon(followed?Icons.favorite_rounded:Icons.favorite_border_rounded,color:followed?pink:Colors.white,size:21))),
     Positioned(left:12,bottom:9,child:Row(children:[Icon(Icons.multitrack_audio_rounded,size:15,color:color),const SizedBox(width:5),const Text('VOICE ROOM',style:TextStyle(fontSize:8,letterSpacing:1.2,color:Colors.white70))])),
    ])),
    Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(12,12,12,14),decoration:const BoxDecoration(color:Colors.black12,border:Border(top:BorderSide(color:Colors.white10))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w700)),
     const SizedBox(height:6),Text(subtitle,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,height:1.4,color:Colors.white60)),
     const SizedBox(height:10),Row(children:[Text('Explore room',style:TextStyle(fontSize:10,fontWeight:FontWeight.w600,color:color)),const Spacer(),Icon(Icons.arrow_forward_rounded,size:15,color:color)]),
    ])),
   ]),
  )),
 );
}
