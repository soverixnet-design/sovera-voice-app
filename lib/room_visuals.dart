import 'package:flutter/material.dart';
import 'main.dart' show BrandLogo, cyan, gold;
import 'effects_studio.dart' show FramePreviewAdapter, previewAvatarFrame;

class RoomSeatAvatar extends StatelessWidget{
 final bool occupied,muted;final double size;
 const RoomSeatAvatar({super.key,this.occupied=false,this.muted=false,this.size=64});
 @override Widget build(BuildContext context)=>SizedBox(width:size+24,height:size+32,child:Stack(alignment:Alignment.center,children:[
 Positioned(top:0,left:0,right:0,height:size+24,child:ValueListenableBuilder(valueListenable:previewAvatarFrame,builder:(context,pack,_)=>occupied&&pack!=null
 ?FramePreviewAdapter(size:size+24,child:BrandLogo(size:size))
 :Stack(alignment:Alignment.center,children:[Positioned.fill(child:CustomPaint(painter:_SeatPainter(occupied))),occupied?ClipOval(child:BrandLogo(size:size-16)):Icon(Icons.weekend_rounded,color:gold,size:size*.52)]))),
 if(occupied&&muted)Positioned(right:1,bottom:4,child:Semantics(key:const ValueKey('muted-seat-badge'),label:'Microphone muted',child:Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:const Color(0xFFEF5678),shape:BoxShape.circle,border:Border.all(color:Colors.white70)),child:const Icon(Icons.mic_off_rounded,size:14,color:Colors.white)))),
 ]));
}
class _SeatPainter extends CustomPainter{
 final bool occupied;_SeatPainter(this.occupied);
 @override void paint(Canvas canvas,Size size){
 final rect=Rect.fromLTWH(6,6,size.width-12,size.width-12);final center=rect.center;
 canvas.drawOval(Rect.fromCenter(center:Offset(center.dx,size.height-3),width:size.width*.72,height:6),Paint()..color=cyan.withValues(alpha:occupied ? .22 : .08));
 final shape=Path()..addOval(rect);
 canvas.drawShadow(shape,Colors.black,5,true);
 canvas.drawOval(rect,Paint()..shader=const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFFFFE8B4),Color(0xFFAD7A3A),Color(0xFF558897),Color(0xFFF5DA9A)]).createShader(rect));
 canvas.drawOval(rect.deflate(4),Paint()..shader=LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:occupied?[const Color(0xFF314C6A),const Color(0xFF10243B)]:[const Color(0xFF26364E),const Color(0xFF101826)]).createShader(rect));
 canvas.drawOval(rect.deflate(7),Paint()..style=PaintingStyle.stroke..strokeWidth=1..color=cyan.withValues(alpha:occupied ? .7 : .2));
 }
 @override bool shouldRepaint(_SeatPainter old)=>occupied!=old.occupied;
}
class RoomTool extends StatelessWidget{
 final String label;final IconData icon;final Color color;final VoidCallback? onTap;
 const RoomTool({super.key,required this.label,required this.icon,required this.color,this.onTap});
 @override Widget build(BuildContext context)=>SizedBox(width:44,child:IconButton(tooltip:label,onPressed:onTap,padding:const EdgeInsets.all(5),icon:Container(width:32,height:32,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color.lerp(color,Colors.white,.3)!,Color.lerp(color,Colors.black,.6)!]),border:Border.all(color:color.withValues(alpha:.6)),boxShadow:[BoxShadow(color:color.withValues(alpha:.2),offset:const Offset(0,3),blurRadius:5)]),child:Icon(icon,size:19,color:Colors.white))));
}
