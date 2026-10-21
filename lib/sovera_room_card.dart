import 'package:flutter/material.dart';
import 'country_picker.dart' show soveraCountries;
import 'firebase_catalog.dart';
import 'room_card_art.dart';

String roomFlag(String code)=>soveraCountries.containsKey(code)?String.fromCharCodes(code.codeUnits.map((c)=>c+127397)):'';
class SoveraRoomPhoto extends StatelessWidget {
  final Map<String,dynamic> room;
  const SoveraRoomPhoto({super.key,required this.room});
  @override Widget build(BuildContext context){
    final url=room['image_url']??room['avatar_url'];
    return url is String&&url.startsWith('https://')?Image.network(url,fit:BoxFit.cover,cacheWidth:768,errorBuilder:(_,error,stack)=>const Center(child:Icon(Icons.mic_rounded,size:42,color:Color(0xFF8ADFE4)))):const Center(child:Icon(Icons.mic_rounded,size:42,color:Color(0xFF8ADFE4)));
  }
}
class SoveraRoomCard extends StatelessWidget {
  final Map<String,dynamic> room;
  final VoidCallback onTap;
  final VoidCallback? onFollow;
  final bool followed;
  const SoveraRoomCard({super.key,required this.room,required this.onTap,this.onFollow,this.followed=false});
  @override Widget build(BuildContext context){
    final country=(room['country']??'').toString().toUpperCase();
    final frame=catalogAsset(room['equipped'],'room_frame');
    return Container(decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),boxShadow:const [BoxShadow(color:Color(0x99030715),offset:Offset(0,7),blurRadius:12),BoxShadow(color:Color(0x222CD9D4),offset:Offset(-1,-1),blurRadius:6)]),child:Material(
      color:const Color(0xFF141D35),borderRadius:BorderRadius.circular(22),clipBehavior:Clip.antiAlias,child:InkWell(onTap:onTap,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Expanded(child:Container(decoration:BoxDecoration(border:Border.all(color:const Color(0xFF5E718E),width:1.5),borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[Color(0xFF284A60),Color(0xFF271C4C)])),child:ClipRRect(borderRadius:BorderRadius.circular(20),child:Stack(fit:StackFit.expand,children:[
          if(frame==null)RoomCardArt(frame:(room['room_frame']??'none') as String,portrait:SoveraRoomPhoto(room:room))
          else LayoutBuilder(builder:(context,box)=>Center(child:CatalogPortrait(asset:frame,avatarUrl:(room['image_url']??room['avatar_url']) as String?,size:box.biggest.shortestSide,still:true))),
          Positioned(right:8,bottom:8,child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(14)),child:Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.graphic_eq_rounded,color:Color(0xFF76E6D4),size:15),const SizedBox(width:4),Text('${room['occupants']??0}',style:const TextStyle(color:Colors.white,fontSize:11))]))),
          if(onFollow!=null)Positioned(right:0,top:0,child:IconButton(tooltip:followed?'Unfollow room':'Follow room',onPressed:onFollow,icon:Icon(followed?Icons.favorite:Icons.favorite_border,color:followed?const Color(0xFFFF82BD):Colors.white,size:21))),
        ])))),
        Padding(padding:const EdgeInsets.fromLTRB(10,9,10,2),child:Text('${roomFlag(country)} ${room['name']??'Voice room'}'.trim(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14))),
        Padding(padding:const EdgeInsets.fromLTRB(10,0,10,10),child:Text(soveraCountries[country]??country,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white54,fontSize:11))),
      ]))));
  }
}
