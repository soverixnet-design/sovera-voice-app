import 'community_services.dart';
import 'package:flutter/material.dart';
import 'main.dart';

enum SocialSection { friendship, cp, love }

class SocialProfileCards extends StatelessWidget{
 const SocialProfileCards({super.key});
 void open(BuildContext context,SocialSection section)=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>ConnectionsPage(kind:section==SocialSection.friendship?'friend':section==SocialSection.cp?'cp':'love')));
 @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  const Text('My connections',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
  const SizedBox(height:12),
  LayoutBuilder(builder:(context,c)=>Wrap(spacing:10,runSpacing:10,children:[
   for(final item in [(SocialSection.friendship,'Friendship','Friends & requests',Icons.handshake_rounded,cyan),(SocialSection.cp,'CP','Couple space',Icons.people_alt_rounded,violet),(SocialSection.love,'Love','Hearts & gifts',Icons.favorite_rounded,pink)])
   SizedBox(width:c.maxWidth<280||MediaQuery.textScalerOf(context).scale(1)>1.3?c.maxWidth:(c.maxWidth-20)/3,child:Material(color:Colors.transparent,borderRadius:BorderRadius.circular(22),clipBehavior:Clip.antiAlias,child:InkWell(onTap:()=>open(context,item.$1),child:Glass(tint:item.$5,padding:const EdgeInsets.symmetric(horizontal:8,vertical:18),child:Column(children:[
    Jewel(item.$4,color:item.$5,size:42),const SizedBox(height:13),Text(item.$2,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),
    const SizedBox(height:6),Text(item.$3,textAlign:TextAlign.center,style:const TextStyle(fontSize:10,color:Colors.white60,height:1.4)),
   ]))))),
  ])),
 ]);
}

class SocialCenter extends StatefulWidget{
 final SocialSection initial;
 const SocialCenter({super.key,this.initial=SocialSection.friendship});
 @override State<SocialCenter> createState()=>_SocialCenterState();
}
class _SocialCenterState extends State<SocialCenter>{
 late SocialSection section;
 bool requests=false;
 Color frame=pink;
 String gift='Heart';
 @override void initState(){super.initState();section=widget.initial;}
 void unavailable()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Social connections are not connected to the server yet. No request was sent.')));
 Widget label(String text)=>Padding(padding:const EdgeInsets.only(top:24,bottom:12),child:Text(text,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)));
 Widget pairAvatar(bool self)=>Container(width:86,height:86,padding:const EdgeInsets.all(4),decoration:BoxDecoration(shape:BoxShape.circle,gradient:LinearGradient(colors:[frame,cyan,gold]),boxShadow:[BoxShadow(color:frame.withValues(alpha:.25),blurRadius:20)]),child:CircleAvatar(backgroundColor:const Color(0xFF18132B),child:self?const BrandLogo(size:64):const Icon(Icons.person_add_alt_1_rounded,color:Colors.white54,size:32)));
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(['Friendship','CP space','Love'][section.index])),
  body:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF45247F),Color(0xFF19132F)])),child:ListView(padding:const EdgeInsets.all(20),children:[
   Wrap(spacing:8,runSpacing:8,children:[for(final item in [(SocialSection.friendship,'Friendship',Icons.handshake_rounded),(SocialSection.cp,'CP',Icons.people_alt_rounded),(SocialSection.love,'Love',Icons.favorite_rounded)])ChoiceChip(avatar:Icon(item.$3,size:18),label:Text(item.$2),selected:section==item.$1,onSelected:(_)=>setState(()=>section=item.$1))]),
   const SizedBox(height:16),const Text('DESIGN PREVIEW · SOCIAL SERVER PENDING',style:TextStyle(fontSize:10,letterSpacing:1,color:Colors.white54)),
   const SizedBox(height:18),
   if(section==SocialSection.friendship)...[
    Glass(tint:cyan,child:Column(children:[
     const Jewel(Icons.handshake_rounded,color:cyan,size:76),const SizedBox(height:20),
     const Text('Good friends. Great moments.',textAlign:TextAlign.center,style:TextStyle(fontSize:25,fontWeight:FontWeight.w800)),
     const SizedBox(height:12),const Text('A place for your friends, new connections and shared memories.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.5)),
     const SizedBox(height:20),OutlinedButton.icon(onPressed:unavailable,icon:const Icon(Icons.person_add_alt_1_rounded),label:const Text('Add friend by ID')),
    ])),
    label('Your circle'),
    Wrap(spacing:8,children:[ChoiceChip(label:const Text('Friends'),selected:!requests,onSelected:(_)=>setState(()=>requests=false)),ChoiceChip(label:const Text('Requests'),selected:requests,onSelected:(_)=>setState(()=>requests=true))]),
    const SizedBox(height:14),Glass(tint:cyan,child:Column(children:[Icon(requests?Icons.mail_outline_rounded:Icons.handshake_outlined,size:40,color:cyan),const SizedBox(height:14),Text(requests?'Friend requests will appear here.':'Your accepted friends will appear here.',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w600)),const SizedBox(height:10),const Text('Friend lists and request delivery are not available in this build.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Colors.white54,height:1.5))])),
   ],
   if(section==SocialSection.cp)...[
    Glass(tint:frame,child:Column(children:[
     const Text('A special connection',textAlign:TextAlign.center,style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
     const SizedBox(height:24),
     FittedBox(fit:BoxFit.scaleDown,child:Row(mainAxisSize:MainAxisSize.min,children:[pairAvatar(true),Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Column(children:[Icon(Icons.favorite_rounded,color:frame,size:27),const SizedBox(height:6),Icon(Icons.handshake_rounded,color:gold,size:25)])),pairAvatar(false)])),
     const SizedBox(height:20),const Text('You + your future CP partner',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold)),
     const SizedBox(height:10),const Text('A CP connection will become active only after both people agree.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.5)),
     const SizedBox(height:18),FilledButton.icon(onPressed:unavailable,icon:const Icon(Icons.favorite_border_rounded),label:const Text('Invite a CP partner')),
    ])),
    label('Preview your couple frame'),
    Wrap(spacing:8,runSpacing:8,children:[for(final item in [('Rose',pink),('Royal',violet),('Ocean',cyan),('Gold',gold)])ChoiceChip(label:Text(item.$1),selected:frame==item.$2,onSelected:(_)=>setState(()=>frame=item.$2))]),
    const SizedBox(height:16),const Glass(tint:pink,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('CP level · —',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),SizedBox(height:10),Text('Couple level, anniversary and shared milestones will appear after a verified CP connection is available.',style:TextStyle(color:Colors.white60,height:1.5))])),
   ],
   if(section==SocialSection.love)...[
    Glass(tint:pink,child:Column(children:[
     const Text('Little gifts. Lasting memories.',textAlign:TextAlign.center,style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
     const SizedBox(height:22),AnimatedSwitcher(duration:const Duration(milliseconds:250),child:Jewel(gift=='Rose'?Icons.local_florist_rounded:gift=='Starlight'?Icons.auto_awesome_rounded:Icons.favorite_rounded,key:ValueKey(gift),color:gift=='Starlight'?gold:pink,size:86)),
     const SizedBox(height:18),Text('$gift preview',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
     const SizedBox(height:10),const Text('Love points · —',style:TextStyle(color:pink,fontSize:20,fontWeight:FontWeight.w800)),
     const SizedBox(height:12),const Text('Love points belong to your CP connection. Verified gift activity will be shown here when the gift service is ready.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.5)),
    ])),
    label('Explore love gifts'),
    Wrap(spacing:10,runSpacing:10,children:[for(final item in [('Heart',Icons.favorite_rounded,pink),('Rose',Icons.local_florist_rounded,pink),('Starlight',Icons.auto_awesome_rounded,gold)])ChoiceChip(avatar:Icon(item.$2,color:item.$3,size:18),label:Text(item.$1),selected:gift==item.$1,onSelected:(_)=>setState(()=>gift=item.$1))]),
    const SizedBox(height:18),const Glass(tint:pink,child:Text('Previewing a gift does not send it, spend coins or add points. Love history and rankings are not connected yet.',style:TextStyle(color:Colors.white60,height:1.5))),
   ],
   const SizedBox(height:16),
  ])),
 );
}
