import 'admin_control.dart';
import 'member_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'auth_gate.dart';
import 'effects_studio.dart';

class ProfileIdentityCard extends StatefulWidget {
 final Map<String,dynamic>? profile;
 final String name,bio;
 final VoidCallback onEdit;
 const ProfileIdentityCard({super.key,this.profile,required this.name,required this.bio,required this.onEdit});
 @override State<ProfileIdentityCard> createState()=>_ProfileIdentityCardState();
}
class _ProfileIdentityCardState extends State<ProfileIdentityCard>{
 Future<Map<String,dynamic>?>? levels;
 @override void initState(){super.initState();reload();}
 void reload(){if(widget.profile!=null)levels=soveraClient.from('sovera_profile_levels').select().eq('user_id',widget.profile!['id'] as String).maybeSingle();}
 Future<void> copyId()async{
  final uid=widget.profile?['uid'];if(uid==null)return;
  await Clipboard.setData(ClipboardData(text:uid.toString()));
  if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('User ID copied.')));
 }
 @override Widget build(BuildContext context)=>Glass(tint:cyan,child:Column(children:[
  FramePreviewAdapter(size:170,child:Stack(alignment:Alignment.bottomRight,children:[
   Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:gold,width:2),boxShadow:[BoxShadow(color:cyan.withValues(alpha:.18),blurRadius:24)]),child:ClipOval(child:widget.profile?['avatar_url'] is String?Image.network(widget.profile!['avatar_url'] as String,width:90,height:90,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const BrandLogo(size:90)):const BrandLogo(size:90))),
   const CircleAvatar(radius:14,backgroundColor:Color(0xFF292044),child:Icon(Icons.person_rounded,color:gold,size:18)),
  ])),
  if(widget.profile!=null)TextButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>MemberProfilePage(targetId:widget.profile!['id'] as String,viewerId:widget.profile!['id'] as String))),icon:const Icon(Icons.account_circle_rounded),label:const Text('Open member profile')),
  const SizedBox(height:18),Text(widget.name,textAlign:TextAlign.center,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
  const SizedBox(height:10),
  Wrap(alignment:WrapAlignment.center,crossAxisAlignment:WrapCrossAlignment.center,spacing:4,children:[
   SelectableText(widget.profile==null?'ID · Sign in to receive your ID':'ID · ${widget.profile!['uid']}',style:const TextStyle(color:cyan,fontWeight:FontWeight.w600,fontSize:13)),
   if(widget.profile!=null)IconButton(tooltip:'Copy user ID',onPressed:copyId,icon:const Icon(Icons.copy_rounded,color:cyan,size:18)),
  ]),
  VipIdentityBadge(value:widget.profile?['vip_id']),
  const SizedBox(height:20),
  FutureBuilder<Map<String,dynamic>?>(future:levels,builder:(context,snapshot){
   final row=snapshot.data;
   return Column(children:[
    Wrap(spacing:8,runSpacing:8,alignment:WrapAlignment.center,children:[
     LevelBadge(label:'Wealth',value:row?['wealth_level'],icon:Icons.diamond_rounded,color:cyan),
     LevelBadge(label:'Charm',value:row?['charm_level'],icon:Icons.favorite_rounded,color:const Color(0xFFF18AA6)),
     LevelBadge(label:'VIP',value:row?['vip_level'],icon:Icons.workspace_premium_rounded,color:gold),
    ]),
    const SizedBox(height:10),
    if(snapshot.connectionState==ConnectionState.waiting)const Text('Loading verified levels…',style:TextStyle(fontSize:11,color:Colors.white54))
    else if(snapshot.hasError)TextButton(onPressed:()=>setState(reload),child:const Text('Could not load levels · Retry'))
    else if(row==null)const Text('Levels appear when verified activity is available.',textAlign:TextAlign.center,style:TextStyle(fontSize:11,color:Colors.white54)),
   ]);
  }),
  const SizedBox(height:16),const ProfileStylePreview(),
  Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),decoration:BoxDecoration(color:violet.withValues(alpha:.18),borderRadius:BorderRadius.circular(20)),child:Text(widget.profile==null?'Guest preview':'Sovera member',style:const TextStyle(fontSize:11,color:Colors.white70))),
  if(widget.bio.isNotEmpty)Padding(padding:const EdgeInsets.only(top:14),child:Text(widget.bio,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70,height:1.5))),
  const SizedBox(height:10),TextButton.icon(onPressed:widget.onEdit,icon:const Icon(Icons.edit_outlined),label:const Text('Edit profile')),
 ]));
}
class LevelBadge extends StatelessWidget{
 final String label;final Object? value;final IconData icon;final Color color;
 const LevelBadge({super.key,required this.label,this.value,required this.icon,required this.color});
 @override Widget build(BuildContext context)=>Container(width:72,padding:const EdgeInsets.symmetric(horizontal:4,vertical:7),decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[color.withValues(alpha:.25),Colors.black26]),border:Border.all(color:color.withValues(alpha:.4)),borderRadius:BorderRadius.circular(18)),child:Column(children:[Icon(icon,color:color,size:18),const SizedBox(height:4),Text(value==null?'Lv. —':'Lv. $value',style:TextStyle(color:color,fontWeight:FontWeight.bold,fontSize:12)),const SizedBox(height:3),Text(label,style:const TextStyle(fontSize:10,color:Colors.white70))]));
}

class ResellerCenter extends StatefulWidget{
 final Map<String,dynamic>? profile;
 const ResellerCenter({super.key,this.profile});
 @override State<ResellerCenter> createState()=>_ResellerCenterState();
}
class _ResellerCenterState extends State<ResellerCenter>{
 final note=TextEditingController();
 Map<String,dynamic>? account,application;
 bool loading=false,busy=false;
 String? error,validation;
 @override void initState(){super.initState();if(widget.profile!=null)load();}
 @override void dispose(){note.dispose();super.dispose();}
 Future<void> load()async{
  setState((){loading=true;error=null;});
  try{
   final userId=widget.profile!['id'] as String;
   final results=await Future.wait([
    soveraClient.from('sovera_reseller_accounts').select().eq('user_id',userId).maybeSingle(),
    soveraClient.from('sovera_reseller_applications').select().eq('user_id',userId).maybeSingle(),
   ]);
   if(mounted)setState((){account=results[0];application=results[1];loading=false;});
  }catch(_){if(mounted)setState((){loading=false;error='Could not load reseller details. Please retry.';});}
 }
 Future<void> apply()async{
  final text=note.text.trim();
  if(text.length<10){setState(()=>validation='Please write at least 10 characters.');return;}
  if(text.length>500||busy||widget.profile==null)return;
  setState((){busy=true;validation=null;});
  try{
   await soveraClient.from('sovera_reseller_applications').insert({'user_id':widget.profile!['id'] as String,'note':text});
   if(!mounted)return;
   note.clear();await load();
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Reseller application saved for review.')));
  }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Application was not saved. Please refresh before retrying.')));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Reseller center')),body:ListView(padding:const EdgeInsets.all(20),children:[
  Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   const Row(children:[Jewel(Icons.storefront_rounded,color:gold,size:48),SizedBox(width:14),Expanded(child:Text('Grow with Sovera',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)))]),
   const SizedBox(height:16),const Text('Manage your reseller status and assigned coin quota from one place.',style:TextStyle(color:Colors.white70,height:1.5)),
   const SizedBox(height:14),Text(widget.profile==null?'Sign in to apply for reseller access.':'Your user ID · ${widget.profile!['uid']}',style:const TextStyle(color:gold,fontWeight:FontWeight.w600)),
  ])),
  const SizedBox(height:18),
  if(loading)const Center(child:CircularProgressIndicator())
  else if(error!=null)TextButton(onPressed:load,child:Text(error!))
  else ...[
   Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Account status',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:12),
    Text(account!=null?'Reseller · ${account!['status']}':application!=null?'Application · ${application!['status']}':'No reseller access assigned',style:const TextStyle(color:cyan)),
    if(account!=null)...[
     const SizedBox(height:12),Text('Tier · ${account!['tier']}'),
     const Divider(height:28),
     Text('Assigned quota · ${account!['coin_quota']} Coins'),
     const SizedBox(height:8),Text('Used quota · ${account!['used_quota']} Coins'),
     const SizedBox(height:8),Text('Available quota · ${(account!['coin_quota'] as num)-(account!['used_quota'] as num)} Coins',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
    ],
    const SizedBox(height:14),const Text('Access and quota are assigned by the owner. Recharge transfers are not enabled in this build.',style:TextStyle(color:Colors.white54,fontSize:12,height:1.5)),
   ])),
   if(widget.profile!=null&&account==null&&application==null)...[
    const SizedBox(height:18),Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const Text('Apply to become a reseller',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:12),
     TextField(controller:note,enabled:!busy,maxLength:500,maxLines:4,decoration:InputDecoration(labelText:'Tell us about your reseller business',errorText:validation,border:const OutlineInputBorder())),
     const SizedBox(height:10),FilledButton.icon(onPressed:busy?null:apply,icon:const Icon(Icons.send_rounded),label:Text(busy?'Submitting…':'Submit application')),
    ])),
   ],
  ],
  const SizedBox(height:22),const Text('Reseller tools',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:10),
  for(final item in [(Icons.person_search_rounded,'Find user by ID','Recipient verification · Coming soon'),(Icons.add_card_rounded,'Recharge coins','Server-verified transfers · Coming soon'),(Icons.receipt_long_rounded,'Recharge history','Receipts and transfer history · Coming soon')])Padding(padding:const EdgeInsets.only(bottom:10),child:Glass(padding:const EdgeInsets.all(8),child:ListTile(enabled:false,leading:Icon(item.$1,color:gold),title:Text(item.$2),subtitle:Text(item.$3)))),
 ]));
}
