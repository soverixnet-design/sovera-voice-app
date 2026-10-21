import 'package:flutter/material.dart';

/// Local transparent 3D art; button labels and callbacks stay with the caller.
class SoveraIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const SoveraIcon(this.icon,{super.key,this.size=28,this.color});
  static String? assetFor(IconData icon){
    if(icon==Icons.card_giftcard_rounded)return 'diamond-gift';
    if(icon==Icons.redeem_rounded||icon==Icons.savings_rounded||icon==Icons.monetization_on_rounded)return 'coin-gift';
    if(icon==Icons.mic_rounded)return 'mic-on';
    if(icon==Icons.mic_off_rounded)return 'mic-off';
    if(icon==Icons.chat_rounded||icon==Icons.chat_bubble_outline||icon==Icons.chat_bubble_outline_rounded||icon==Icons.message_rounded)return 'messages';
    if(icon==Icons.campaign_rounded)return 'notice';
    return null;
  }
  @override Widget build(BuildContext context){
    final name=assetFor(icon);
    if(name==null)return Icon(icon,size:size,color:color);
    return Image.asset('assets/ui-icons/$name.webp',width:size,height:size,
      fit:BoxFit.contain,filterQuality:FilterQuality.medium,excludeFromSemantics:true,
      errorBuilder:(_,e,s)=>Icon(icon,size:size,color:color));
  }
}
