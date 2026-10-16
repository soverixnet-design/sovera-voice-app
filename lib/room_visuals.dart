import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'main.dart' show BrandLogo, cyan, gold;
import 'effects_studio.dart' show FramePreviewAdapter;

class RoomSeatAvatar extends StatelessWidget{
 final bool occupied,muted;final double size;
 const RoomSeatAvatar({super.key,this.occupied=false,this.muted=false,this.size=64});
 @override Widget build(BuildContext context)=>SizedBox(width:size+24,height:size+32,child:Stack(alignment:Alignment.center,children:[
 Positioned.fill(child:CustomPaint(painter:_SeatPainter(occupied))),
 Positioned(top:14,left:16,right:16,child:SizedBox(height:size-8,child:occupied?FramePreviewAdapter(size:size-8,child:BrandLogo(size:size-18)):Icon(Icons.weekend_rounded,color:gold,size:size*.52))),
 if(occupied&&muted)Positioned(right:1,bottom:14,child:Semantics(key:const ValueKey('muted-seat-badge'),label:'Microphone muted',child:Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:const Color(0xFFEF5678),shape:BoxShape.circle,border:Border.all(color:Colors.white70)),child:const Icon(Icons.mic_off_rounded,size:14,color:Colors.white)))),
 ]));
}
class _SeatPainter extends CustomPainter{
 final bool occupied;_SeatPainter(this.occupied);
 @override void paint(Canvas canvas,Size size){
 final rect=Rect.fromLTWH(6,7,size.width-12,size.height-24);final center=rect.center;
 canvas.drawOval(Rect.fromCenter(center:Offset(center.dx,size.height-7),width:size.width*.72,height:10),Paint()..shader=RadialGradient(colors:[cyan.withValues(alpha:occupied ? .5 : .16),Colors.transparent]).createShader(Rect.fromLTWH(0,size.height-14,size.width,14)));
 Path shape(double inset){final r=rect.deflate(inset);final p=Path();for(int i=0;i<8;i++){final a=-math.pi/8+i*math.pi/4;final x=r.center.dx+math.cos(a)*r.width/2;final y=r.center.dy+math.sin(a)*r.height/2;if(i==0){p.moveTo(x,y);}else{p.lineTo(x,y);}}return p..close();}
 canvas.drawShadow(shape(0),Colors.black,7,true);
 canvas.drawPath(shape(0),Paint()..shader=const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFFFFE8B4),Color(0xFFAD7A3A),Color(0xFF558897),Color(0xFFF5DA9A)]).createShader(rect));
 canvas.drawPath(shape(4),Paint()..shader=LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:occupied?[const Color(0xFF314C6A),const Color(0xFF10243B)]:[const Color(0xFF26364E),const Color(0xFF101826)]).createShader(rect));
 canvas.drawPath(shape(7),Paint()..style=PaintingStyle.stroke..strokeWidth=1..color=cyan.withValues(alpha:occupied ? .7 : .2));
 canvas.drawCircle(Offset(center.dx,5),4,Paint()..color=occupied?cyan:gold);
 }
 @override bool shouldRepaint(_SeatPainter old)=>occupied!=old.occupied;
}
class RoomTool extends StatelessWidget{
 final String label;final IconData icon;final Color color;final VoidCallback? onTap;
 const RoomTool({super.key,required this.label,required this.icon,required this.color,this.onTap});
 @override Widget build(BuildContext context)=>SizedBox(width:44,child:IconButton(tooltip:label,onPressed:onTap,padding:const EdgeInsets.all(5),icon:Container(width:32,height:32,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color.lerp(color,Colors.white,.3)!,Color.lerp(color,Colors.black,.6)!]),border:Border.all(color:color.withValues(alpha:.6)),boxShadow:[BoxShadow(color:color.withValues(alpha:.2),offset:const Offset(0,3),blurRadius:5)]),child:Icon(icon,size:19,color:Colors.white))));
}
