import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'main.dart';

String soveraFlag(String? code) {
 final c=(code??'').toUpperCase();
 if(!RegExp(r'^[A-Z]{2}$').hasMatch(c))return '🌐';
 return String.fromCharCodes(c.codeUnits.map((v)=>v+127397));
}

class RoomCard extends StatelessWidget {
 final String name,category,subtitle;
 final String? country;
 final int? onlineCount;
 final Uint8List? coverBytes;
 final Color color;
 final bool followed;
 final VoidCallback onOpen;
 final VoidCallback? onFollow;
 const RoomCard({super.key,required this.name,required this.category,required this.subtitle,required this.onOpen,required this.onFollow,this.followed=false,this.color=violet,this.country,this.onlineCount,this.coverBytes});
 @override Widget build(BuildContext context)=>Material(
  color:Colors.transparent,borderRadius:BorderRadius.circular(20),clipBehavior:Clip.antiAlias,
  child:InkWell(onTap:onOpen,child:Ink(
   decoration:BoxDecoration(color:const Color(0xFF181923),border:Border.all(color:color.withValues(alpha:.4)),borderRadius:BorderRadius.circular(20)),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(child:Stack(fit:StackFit.expand,children:[
     if(coverBytes!=null)Image.memory(coverBytes!,fit:BoxFit.cover,gaplessPlayback:true,errorBuilder:(_,__,___)=>const Center(child:BrandLogo(size:68)))
     else Container(decoration:BoxDecoration(gradient:LinearGradient(colors:[color.withValues(alpha:.5),const Color(0xFF131626)])),child:const Center(child:BrandLogo(size:70))),
     Positioned.fill(child:IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.black45,Colors.transparent,Colors.transparent,Colors.black38]))))),
     Positioned(left:8,top:8,right:42,child:Align(alignment:Alignment.topLeft,child:Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(16)),child:Text(category,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:10))))),
     Positioned(right:0,top:0,child:IconButton(tooltip:followed?'Unfollow room':'Follow room',onPressed:onFollow,icon:Icon(followed?Icons.favorite_rounded:Icons.favorite_border_rounded,color:followed?pink:Colors.white,size:20))),
    ])),
    Padding(padding:const EdgeInsets.fromLTRB(10,8,10,9),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w800)),
     const SizedBox(height:5),
     Row(children:[
      Flexible(child:Text('${soveraFlag(country)} ${country==null||country!.isEmpty?'Country not set':country!.toUpperCase()}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Colors.white70))),
      const Spacer(),
      const Icon(Icons.people_alt_rounded,size:13,color:Colors.white70),const SizedBox(width:3),
      Text(onlineCount==null?'—':'$onlineCount',style:const TextStyle(fontWeight:FontWeight.w700,fontSize:11,color:Colors.white)),
     ]),
    ])),
   ]),
  )),
 );
}
