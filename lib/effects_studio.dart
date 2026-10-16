import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'main.dart';
import 'medal_collection.dart';

class EffectPack {
 final String name,asset;
 final Color color;
 const EffectPack(this.name,this.asset,this.color);
}
const effectPacks=[
 EffectPack('Phoenix Fire','assets/effects/phoenix.png',Color(0xFFFF8B3D)),
 EffectPack('Ice Wings','assets/effects/ice.png',cyan),
 EffectPack('Royal Dragon','assets/effects/dragon.png',Color(0xFF50D9A0)),
];
/// Local visual preference only. It does not grant account inventory.
final previewAvatarFrame=ValueNotifier<EffectPack?>(null);

class EffectPortrait extends StatelessWidget{
 final EffectPack pack;
 final Widget child;
 final double size,phase;
 final bool speaking;
 const EffectPortrait({super.key,required this.pack,required this.child,this.size=240,this.phase=0,this.speaking=false});
 @override Widget build(BuildContext context)=>SizedBox(width:size,height:size,child:Stack(clipBehavior:Clip.none,children:[
  Positioned(left:size*.285,top:size*.315,width:size*.43,height:size*.43,child:ClipOval(child:ColoredBox(color:const Color(0xFF131522),child:FittedBox(fit:BoxFit.contain,child:child)))),
  Positioned.fill(child:Image.asset(pack.asset,fit:BoxFit.contain,filterQuality:FilterQuality.high)),
  if(speaking)Positioned.fill(child:IgnorePointer(child:CustomPaint(painter:_SpeakingPainter(pack.color,phase)))),
 ]));
}
class FramePreviewAdapter extends StatelessWidget{
 final Widget child;
 final double size;
 final bool enabled;
 const FramePreviewAdapter({super.key,required this.child,this.size=160,this.enabled=true});
 @override Widget build(BuildContext context)=>ValueListenableBuilder<EffectPack?>(valueListenable:previewAvatarFrame,builder:(context,pack,_)=>pack==null||!enabled?child:EffectPortrait(pack:pack,size:size,child:child));
}
class _SpeakingPainter extends CustomPainter{
 final Color color;final double phase;
 _SpeakingPainter(this.color,this.phase);
 @override void paint(Canvas canvas,Size size){
  final center=Offset(size.width*.5,size.height*.53);
  for(int i=0;i<3;i++){
   final t=(phase+i/3)%1;
   final paint=Paint()..style=PaintingStyle.stroke..strokeWidth=2.5*(1-t)+0.5..color=color.withValues(alpha:(1-t)*.65);
   canvas.drawCircle(center,size.width*(.23+t*.21),paint);
  }
  final paint=Paint()..color=color;
  for(int i=0;i<16;i++){
   final angle=i*math.pi/8+phase*math.pi*2;
   final radius=size.width*(.38+.035*math.sin(angle*3));
   canvas.drawCircle(center+Offset(math.cos(angle),math.sin(angle))*radius,1.5+1.5*math.sin(angle).abs(),paint);
  }
 }
 @override bool shouldRepaint(_SpeakingPainter old)=>old.phase!=phase||old.color!=color;
}

Future<void> showEntryPreview(BuildContext context,EffectPack pack)=>showGeneralDialog<void>(
 context:context,barrierDismissible:true,barrierLabel:'Close entry preview',barrierColor:Colors.black87,
 transitionDuration:const Duration(milliseconds:180),pageBuilder:(context,_,__)=>_EntryPreview(pack:pack),
);
class _EntryPreview extends StatefulWidget{
 final EffectPack pack;
 const _EntryPreview({required this.pack});
 @override State<_EntryPreview> createState()=>_EntryPreviewState();
}
class _EntryPreviewState extends State<_EntryPreview> with SingleTickerProviderStateMixin{
 late final AnimationController motion;
 bool started=false;
 @override void initState(){super.initState();motion=AnimationController(vsync:this,duration:const Duration(milliseconds:3200))..addStatusListener((status){if(status==AnimationStatus.completed&&mounted)Navigator.of(context).pop();});}
 @override void didChangeDependencies(){super.didChangeDependencies();if(!started){started=true;if(MediaQuery.disableAnimationsOf(context))motion.duration=const Duration(milliseconds:1);motion.forward();}}
 @override void dispose(){motion.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Material(color:Colors.transparent,child:SafeArea(child:Stack(children:[
  Center(child:AnimatedBuilder(animation:motion,builder:(context,_){
   final t=motion.value;
   final fade=(t<.18?t/.18:t>.82?(1-t)/.18:1.0).clamp(0.0,1.0).toDouble();
   final entrance=Curves.easeOutCubic.transform((t*3).clamp(0.0,1.0).toDouble());
   return Opacity(opacity:fade,child:Transform.translate(offset:Offset(0,65*(1-entrance)),child:Transform.scale(scale:.65+.35*entrance,child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
    EffectPortrait(pack:widget.pack,size:math.min(MediaQuery.sizeOf(context).width-40,340.0),phase:t,speaking:true,child:const BrandLogo(size:100)),
    const SizedBox(height:20),Text(widget.pack.name,textAlign:TextAlign.center,style:TextStyle(color:widget.pack.color,fontSize:28,fontWeight:FontWeight.w800)),
    const SizedBox(height:10),const Text('Sovera arrival preview',style:TextStyle(color:Colors.white70,fontSize:15)),
   ])))));
  })),
  Positioned(top:8,right:8,child:IconButton(tooltip:'Close entry preview',onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))),
 ])));
}

class EffectsStudio extends StatefulWidget{
 const EffectsStudio({super.key});
 @override State<EffectsStudio> createState()=>_EffectsStudioState();
}
class _EffectsStudioState extends State<EffectsStudio> with SingleTickerProviderStateMixin{
 int selected=0,kind=0;
 late final AnimationController pulse;
 @override void initState(){super.initState();pulse=AnimationController(vsync:this,duration:const Duration(seconds:3));}
 @override void dispose(){pulse.dispose();super.dispose();}
 void play(){if(kind==1){showEntryPreview(context,effectPacks[selected]);}else if(!MediaQuery.disableAnimationsOf(context)){pulse.forward(from:0);}}
 @override Widget build(BuildContext context){
  final pack=effectPacks[selected];
  return Scaffold(appBar:AppBar(title:const Text('Frames & effects')),body:ListView(padding:const EdgeInsets.all(20),children:[
   OutlinedButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const MedalCollection())),icon:const Icon(Icons.military_tech_rounded),label:const Text('Animated medals')),
   const SizedBox(height:16),
   const Text('Sovera signature collection',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800)),
   const SizedBox(height:10),const Text('Three themes · Nine visual previews',style:TextStyle(color:Colors.white60)),
   const SizedBox(height:20),
   SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[for(int i=0;i<effectPacks.length;i++)Padding(padding:const EdgeInsets.only(right:10),child:Semantics(selected:selected==i,button:true,child:InkWell(onTap:()=>setState(()=>selected=i),borderRadius:BorderRadius.circular(20),child:Container(width:126,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:selected==i?effectPacks[i].color.withValues(alpha:.15):Colors.white.withValues(alpha:.03),border:Border.all(color:selected==i?effectPacks[i].color:Colors.white12,width:2),borderRadius:BorderRadius.circular(20)),child:Column(children:[Image.asset(effectPacks[i].asset,height:98,width:98),const SizedBox(height:8),Text(effectPacks[i].name,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold))])))))])),
   const SizedBox(height:20),Wrap(spacing:8,runSpacing:8,children:[for(int i=0;i<3;i++)ChoiceChip(label:Text(['Frame','Entry','Speaking glow'][i]),selected:kind==i,onSelected:(_){pulse.reset();setState(()=>kind=i);})]),
   const SizedBox(height:20),Glass(tint:pack.color,child:Column(children:[
    AnimatedBuilder(animation:pulse,builder:(context,_)=>EffectPortrait(pack:pack,size:math.min(MediaQuery.sizeOf(context).width-80,270.0),phase:pulse.value,speaking:kind==2,child:const BrandLogo(size:100))),
    const SizedBox(height:14),Text(pack.name,textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
    const SizedBox(height:10),Text(['A decorative frame around your portrait.','An animated room-arrival overlay with wings, light and particles.','A visual pulse around the avatar. This preview does not listen to your microphone.'][kind],textAlign:TextAlign.center,style:const TextStyle(color:Colors.white60,height:1.5)),
    const SizedBox(height:18),
    if(kind!=0)FilledButton.icon(onPressed:play,icon:const Icon(Icons.play_arrow_rounded),label:Text(kind==1?'Preview entry':'Preview speaking glow')),
    if(kind==0)FilledButton.icon(onPressed:(){previewAvatarFrame.value=pack;ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Frame applied for this preview session.')));},icon:const Icon(Icons.check_circle_outline_rounded),label:const Text('Use frame in preview')),
   ])),
   const SizedBox(height:16),TextButton.icon(onPressed:()=>previewAvatarFrame.value=null,icon:const Icon(Icons.restart_alt_rounded),label:const Text('Reset preview frame')),
   const SizedBox(height:8),const Text('Preview selections reset when the app restarts. Entry and speaking animations are demonstrations; live voice and account inventory are not connected.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Colors.white54,height:1.5)),
  ]));
 }
}
