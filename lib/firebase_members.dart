import 'firebase_programs.dart';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_original_profile_card.dart';
import 'firebase_messaging.dart';
import 'sovera_visuals.dart' show Glass,Jewel,cyan,gold,violet;

class FirebaseMemberProfile extends StatefulWidget {
 final FirebaseProfileApi api;final String uid;
 const FirebaseMemberProfile({super.key,required this.api,required this.uid});
 @override State<FirebaseMemberProfile> createState()=>_FirebaseMemberProfileState();
}
class _FirebaseMemberProfileState extends State<FirebaseMemberProfile>{
 Map<String,dynamic>? profile;String? error;bool busy=false;
 @override void initState(){super.initState();load();}
 Future<void> load()async{try{final p=await widget.api.call('GET',suffix:'/members/${Uri.encodeComponent(widget.uid)}');if(mounted)setState((){profile=p;error=null;});}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load profile.');}}
 Future<void> follow()async{if(busy||profile==null)return;setState(()=>busy=true);try{await widget.api.call('PUT',suffix:'/members/${Uri.encodeComponent(widget.uid)}/follow',fields:{'enabled':profile!['is_following']!=true});await load();}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not update following.');}finally{if(mounted)setState(()=>busy=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Member profile'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(18),children:[
  if(error!=null)Text(error!),
  if(profile==null&&error==null)const Center(child:CircularProgressIndicator()),
  if(profile!=null)...[
   FirebaseOriginalProfileCard(profile:profile,name:'${profile!['display_name']}',onEdit:(){},editable:false),
   const SizedBox(height:16),MemberSocialCounts(profile:profile!),
   const SizedBox(height:16),Glass(tint:gold,child:Text('Gift Coins sent: ${profile!['gift_coins_sent']}\nGift Diamonds received: ${profile!['gift_diamonds_received']}',style:const TextStyle(height:1.8))),
   if(widget.uid!=widget.api.uid)...[
    const SizedBox(height:16),FilledButton.icon(onPressed:busy?null:follow,icon:Icon(profile!['is_following']==true?Icons.person_remove:Icons.person_add),label:Text(profile!['is_following']==true?'Unfollow':'Follow')),
    OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseDirectChat(api:widget.api,target:widget.uid,name:'${profile!['display_name']}'))),icon:const Icon(Icons.chat_rounded),label:const Text('Message')),
   ],
  ],
 ]));
}
class MemberSocialCounts extends StatelessWidget{
 final Map<String,dynamic> profile;final void Function(String)? onOpen;
 const MemberSocialCounts({super.key,required this.profile,this.onOpen});
 @override Widget build(BuildContext context)=>Glass(tint:cyan,child:Row(children:[for(final item in const [('friends','Friends'),('followers','Followers'),('following','Following'),('visitors','Visitors')])Expanded(child:InkWell(onTap:onOpen==null?null:()=>onOpen!(item.$1),child:Column(children:[Text('${profile[item.$1]??'—'}',style:const TextStyle(fontWeight:FontWeight.w800,fontSize:23)),const SizedBox(height:5),FittedBox(child:Text(item.$2,style:const TextStyle(fontSize:11,color:Colors.white70)))])))]));
}
class FirebaseMembersPage extends StatefulWidget{
 final FirebaseProfileApi api;final String? section;
 const FirebaseMembersPage({super.key,required this.api,this.section});
 @override State<FirebaseMembersPage> createState()=>_FirebaseMembersPageState();
}
class _FirebaseMembersPageState extends State<FirebaseMembersPage>{
 List<Map<String,dynamic>> rows=[];bool loading=true,hasMore=false;String? error;String query='';
 @override void initState(){super.initState();load();}
 Future<void> load({bool more=false})async{setState(()=>loading=true);try{final data=await widget.api.call('GET',suffix:'/members?${Uri(queryParameters:{'q':query,'offset':more?'${rows.length}':'0',if(widget.section!=null)'section':widget.section!}).query}');if(mounted)setState((){final fetched=(data['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();if(!more)rows.clear();rows.addAll(fetched);hasMore=fetched.length==100;error=null;});}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load members.');}finally{if(mounted)setState(()=>loading=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.section??'Find members')),body:ListView(padding:const EdgeInsets.all(18),children:[
  TextField(onChanged:(v)=>query=v.trim(),onSubmitted:(_)=>load(),decoration:InputDecoration(hintText:'Name or public ID',suffixIcon:IconButton(onPressed:load,icon:const Icon(Icons.search)))),
  if(loading)const Center(child:CircularProgressIndicator()),if(error!=null)Text(error!),
  if(!loading&&error==null&&rows.isEmpty)const Text('No members found.'),
  for(final p in rows)Padding(padding:const EdgeInsets.only(top:12),child:Glass(tint:violet,child:ListTile(contentPadding:EdgeInsets.zero,leading:const Jewel(Icons.person_rounded,color:cyan,size:42),title:Text('${p['name']}'),subtitle:Text('ID ${p['public_id']??'—'} · ${p['country']}'),trailing:const Icon(Icons.chevron_right),onTap:()async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseMemberProfile(api:widget.api,uid:'${p['uid']}')));if(mounted)load();}))),
  if(hasMore)TextButton(onPressed:loading?null:()=>load(more:true),child:const Text('Load more members')),
 ]));
}
class FirebaseAgenciesPage extends StatefulWidget{
 final FirebaseProfileApi api;
 const FirebaseAgenciesPage({super.key,required this.api});
 @override State<FirebaseAgenciesPage> createState()=>_FirebaseAgenciesPageState();
}
class _FirebaseAgenciesPageState extends State<FirebaseAgenciesPage>{
 List<Map<String,dynamic>> rows=[];String? error;bool busy=false;
 @override void initState(){super.initState();load();}
 Future<void> load()async{try{final result=await widget.api.call('GET',suffix:'/agencies');if(mounted)setState((){rows=(result['items'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();error=null;});}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load agencies.');}}
 Future<void> join(Map<String,dynamic> agency)async{if(busy)return;setState(()=>busy=true);try{await widget.api.call('POST',suffix:'/agencies/${agency['id']}/join',fields:{'enabled':agency['membership']==null});await load();}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not save membership.');}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> roster(Map<String,dynamic> agency)async{
  try{final result=await widget.api.call('GET',suffix:'/agencies/${agency['id']}/members');if(!mounted)return;
   await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:SizedBox(height:440,child:ListView(children:[ListTile(title:Text('${agency['name']} · Members')),for(final p in (result['items'] as List).whereType<Map>())ListTile(title:Text('${p['name']}'),subtitle:Text('${p['status']}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[if(p['status']=='pending')IconButton(tooltip:'Approve member',icon:const Icon(Icons.check),onPressed:()async{await widget.api.call('PUT',suffix:'/agencies/${agency['id']}/members/${p['uid']}',fields:{'enabled':true});if(ctx.mounted)Navigator.pop(ctx);load();}),IconButton(tooltip:'Remove member',icon:const Icon(Icons.close),onPressed:()async{await widget.api.call('PUT',suffix:'/agencies/${agency['id']}/members/${p['uid']}',fields:{'enabled':false});if(ctx.mounted)Navigator.pop(ctx);load();})]))]))));
  }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load roster.');}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Sovera Agencies'),actions:[IconButton(tooltip:'Agency income',onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseProgramsPage(api:widget.api,initialSection:'agency'))),icon:const Icon(Icons.insights_rounded)),IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(18),children:[
  if(error!=null)Text(error!),if(rows.isEmpty)const Text('Owner-approved agencies will appear here.'),
  for(final agency in rows)Padding(padding:const EdgeInsets.only(bottom:15),child:Glass(tint:violet,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const Jewel(Icons.groups_rounded,color:violet,size:46),const SizedBox(width:12),Expanded(child:Text('${agency['name']}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)))]),Text('Manager: ${agency['manager_name']} · ${agency['members']} members'),const SizedBox(height:12),if(agency['manager']==widget.api.uid)FilledButton(onPressed:()=>roster(agency),child:const Text('Manage join requests / members'))else FilledButton(onPressed:busy?null:()=>join(agency),child:Text(agency['membership']==null?'Request to join':agency['membership']=='pending'?'Cancel request':'Leave agency'))]))),
 ]));
}
