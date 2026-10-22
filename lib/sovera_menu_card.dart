import 'package:flutter/material.dart';
import 'sovera_visuals.dart' show Jewel, violet;

/// The Me and wallet menus share Sovera's existing colours and real routes.
class SoveraMenuCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;
  const SoveraMenuCard({super.key,required this.label,required this.icon,
    required this.onTap,this.color=violet,this.trailing,this.compact=false});
  @override Widget build(BuildContext context)=>Semantics(button:true,
    child:Container(margin:const EdgeInsets.only(bottom:12),
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),
        gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
          colors:[color.withValues(alpha:.23),const Color(0xff192137)]),
        border:Border.all(color:color.withValues(alpha:.34)),
        boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.25),
          offset:const Offset(0,7),blurRadius:12)]),
      child:Material(color:Colors.transparent,borderRadius:BorderRadius.circular(24),
        child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(24),
          child:Padding(padding:EdgeInsets.all(compact?12:16),
            child:compact?Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Jewel(icon,color:color,size:40),const SizedBox(height:10),
              Text(label,textAlign:TextAlign.center,maxLines:2,
                style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
            ]):Row(children:[Jewel(icon,color:color,size:40),const SizedBox(width:14),
              Expanded(child:Text(label,style:const TextStyle(fontWeight:FontWeight.w700))),
              if(trailing!=null)Flexible(child:trailing!),
              const SizedBox(width:6),const Icon(Icons.chevron_right_rounded),
            ]))))));
}
