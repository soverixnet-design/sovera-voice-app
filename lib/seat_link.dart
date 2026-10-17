import 'package:flutter/material.dart';

/// A local two-seat demonstration, never a server relationship or gift award.
const roomSeatColumns = 4;
enum SeatBond { friendship, cp }
bool adjacentSeats(int a,int b,int count)=>a>=0&&b>=0&&a<count&&b<count&&a!=b&&a~/roomSeatColumns==b~/roomSeatColumns&&(a-b).abs()==1;
class SeatLinkMarker extends StatelessWidget{
 final SeatBond bond;
 const SeatLinkMarker({super.key,required this.bond});
 @override Widget build(BuildContext context)=>Tooltip(message:bond==SeatBond.cp?'CP heart preview':'Friendship holding-hands preview',child:Container(width:36,height:32,decoration:BoxDecoration(color:const Color(0xFF171322),borderRadius:BorderRadius.circular(18),border:Border.all(color:bond==SeatBond.cp?Colors.pinkAccent:Colors.cyanAccent),boxShadow:[BoxShadow(color:(bond==SeatBond.cp?Colors.pinkAccent:Colors.cyanAccent).withValues(alpha:.3),blurRadius:12)]),child:Icon(bond==SeatBond.cp?Icons.favorite_rounded:Icons.handshake_rounded,color:bond==SeatBond.cp?Colors.pinkAccent:Colors.cyanAccent,size:23)));
}
