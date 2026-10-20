import 'package:flutter/material.dart';

const roomFrameAssets={
  'coins_seller':'assets/room-frames/coins-seller.webp',
  'official':'assets/room-frames/official.webp',
};

/// Decorative artwork only; never grants seller/admin account permissions.
class RoomCardArt extends StatelessWidget {
  final String frame;
  final Widget portrait;
  const RoomCardArt({super.key,required this.frame,required this.portrait});
  @override Widget build(BuildContext context){
    final asset=roomFrameAssets[frame];
    if(asset==null)return portrait;
    return Center(child:AspectRatio(aspectRatio:540/550,child:Stack(fit:StackFit.expand,children:[
      Positioned.fill(child:LayoutBuilder(builder:(context,box)=>Padding(
        padding:EdgeInsets.fromLTRB(box.maxWidth*.16,box.maxHeight*.22,box.maxWidth*.16,box.maxHeight*.25),
        child:ClipRRect(borderRadius:BorderRadius.circular(12),child:portrait)))),
      IgnorePointer(child:Image.asset(asset,fit:BoxFit.contain,excludeFromSemantics:true)),
    ])));
  }
}

class RoomActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  const RoomActionButton({super.key,required this.icon,required this.label,required this.color,required this.onPressed});
  @override Widget build(BuildContext context)=>Tooltip(message:label,child:Material(
    color:Colors.transparent,child:InkWell(onTap:onPressed,borderRadius:BorderRadius.circular(16),
      child:Container(width:58,height:58,decoration:BoxDecoration(
        gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[color,color.withValues(alpha:.45)]),
        borderRadius:BorderRadius.circular(16),border:Border.all(color:Colors.white38),
        boxShadow:[BoxShadow(color:color.withValues(alpha:.2),blurRadius:10,offset:const Offset(0,3))]),
        child:Semantics(button:true,label:label,enabled:onPressed!=null,child:Icon(icon,color:Colors.white,size:30)))));
}
