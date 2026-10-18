import 'package:flutter/material.dart';

class RoleStyle{
 final String id,label;final IconData icon;final Color color;
 const RoleStyle(this.id,this.label,this.icon,this.color);
}
const roleStyles=[
 RoleStyle('manager','Manager',Icons.diamond_rounded,Color(0xFFE5C180)),
 RoleStyle('super-admin','Super Admin',Icons.shield_rounded,Color(0xFFCB8CFF)),
 RoleStyle('assistant','Assistant',Icons.support_agent_rounded,Color(0xFF68DDE4)),
 RoleStyle('admin','Admin',Icons.verified_user_rounded,Color(0xFFFF8FA6)),
 RoleStyle('bd-host','BD Host',Icons.mic_rounded,Color(0xFF6BD7AA)),
 RoleStyle('host','Host',Icons.headset_mic_rounded,Color(0xFF89AFFA)),
];
final previewRoleStyles=ValueNotifier<Set<String>>({});
class RoleMedallion extends StatelessWidget{
 final RoleStyle style;final double width;
 const RoleMedallion({super.key,required this.style,this.width=96});
 @override Widget build(BuildContext context)=>Semantics(label:'${style.label} medal design preview',child:SizedBox(width:width,child:Column(mainAxisSize:MainAxisSize.min,children:[
 SizedBox(width:width,height:width*.8,child:Stack(alignment:Alignment.center,children:[
 Positioned(left:0,child:Transform.rotate(angle:-.65,child:Icon(Icons.auto_awesome_rounded,color:style.color,size:width*.4))),Positioned(right:0,child:Transform.rotate(angle:.65,child:Icon(Icons.auto_awesome_rounded,color:style.color,size:width*.4))),
 Container(width:width*.64,height:width*.64,decoration:BoxDecoration(shape:BoxShape.circle,gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color.lerp(style.color,Colors.white,.6)!,style.color,Color.lerp(style.color,Colors.black,.65)!]),border:Border.all(color:style.color,width:3),boxShadow:[BoxShadow(color:style.color.withValues(alpha:.3),blurRadius:12,offset:const Offset(0,5))]),padding:const EdgeInsets.all(6),child:DecoratedBox(decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF162139),border:Border.all(color:Colors.white38)),child:Icon(style.icon,color:style.color,size:width*.29))),
 Positioned(top:0,child:Icon(Icons.workspace_premium_rounded,color:style.color,size:width*.23)),
 ])),
 Container(width:width,padding:const EdgeInsets.symmetric(vertical:5,horizontal:3),decoration:BoxDecoration(gradient:LinearGradient(colors:[style.color.withValues(alpha:.15),style.color.withValues(alpha:.45),style.color.withValues(alpha:.15)]),borderRadius:BorderRadius.circular(8),border:Border.all(color:style.color.withValues(alpha:.5))),child:Text(style.label,maxLines:2,textAlign:TextAlign.center,style:TextStyle(color:style.color,fontWeight:FontWeight.w800,fontSize:width>100?14:10))),
 ])));
}
class ProfileRoleStyles extends StatelessWidget{
 const ProfileRoleStyles({super.key});
 @override Widget build(BuildContext context)=>ValueListenableBuilder<Set<String>>(valueListenable:previewRoleStyles,builder:(context,selected,_)=>selected.isEmpty?const SizedBox.shrink():Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:12,children:[for(final style in roleStyles)if(selected.contains(style.id))RoleMedallion(style:style)])));
}
class RoleMedalCollection extends StatelessWidget{
 const RoleMedalCollection({super.key});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Staff & host medal designs')),body:ListView(padding:const EdgeInsets.all(20),children:[
 const Text('Sovera signature roles',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800)),const SizedBox(height:10),const Text('Decorative previews only. Selecting a design does not assign a staff role or permission.',style:TextStyle(color:Colors.white60,height:1.5)),const SizedBox(height:20),
 for(final style in roleStyles)Padding(padding:const EdgeInsets.only(bottom:16),child:Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[RoleMedallion(style:style,width:150),const SizedBox(height:16),ValueListenableBuilder<Set<String>>(valueListenable:previewRoleStyles,builder:(context,selected,_)=>FilterChip(label:Text(selected.contains(style.id)?'Remove medal preview':'Show below levels'),selected:selected.contains(style.id),onSelected:(value){final next={...selected};value?next.add(style.id):next.remove(style.id);previewRoleStyles.value=next;}))])))),
 ]));
}
