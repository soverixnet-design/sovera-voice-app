import 'member_profile.dart';
import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'main.dart' show Glass,Jewel,cyan,gold;

abstract class MemberStore{
 const MemberStore();
 Future<Map<String,dynamic>?> ownCard(String id);
 Future<Set<String>> following(String id);
 Future<List<Map<String,dynamic>>> members(String own,String query,int offset);
 Future<void> publish(Map<String,dynamic> profile,bool listed);
 Future<void> follow(String own,String target,bool value);
}
class SupabaseMemberStore extends MemberStore{
 const SupabaseMemberStore();
 @override Future<Map<String,dynamic>?> ownCard(String id)=>soveraClient.from('sovera_member_cards').select().eq('user_id',id).maybeSingle();
 @override Future<Set<String>> following(String id)async{
  final result=<String>{};int offset=0;
  while(true){final rows=await soveraClient.from('sovera_user_follows').select('following_id').eq('follower_id',id).order('following_id').range(offset,offset+199);result.addAll(rows.map((r)=>r['following_id'] as String));if(rows.length<200)break;offset+=200;}
  return result;
 }
 @override Future<List<Map<String,dynamic>>> members(String own,String query,int offset)async{
  var request=soveraClient.from('sovera_member_cards').select().eq('listed',true).neq('user_id',own);
  if(query.trim().isNotEmpty){final id=int.tryParse(query.trim());if(id!=null){request=request.eq('uid',id);}else{final escaped=query.trim().replaceAll('\\',r'\\').replaceAll('%',r'\%').replaceAll('_',r'\_');request=request.ilike('display_name','%$escaped%');}}
  return await request.order('uid').range(offset,offset+19);
 }
 @override Future<void> publish(Map<String,dynamic> profile,bool listed)async{await soveraClient.from('sovera_member_cards').upsert({'user_id':profile['id'],'uid':profile['uid'],'display_name':profile['display_name']??'Sovera member','avatar_url':profile['avatar_url'],'bio':profile['bio']??'','listed':listed});}
 @override Future<void> follow(String own,String target,bool value)async{
  if(value){await soveraClient.from('sovera_user_follows').insert({'follower_id':own,'following_id':target});}else{await soveraClient.from('sovera_user_follows').delete().eq('follower_id',own).eq('following_id',target);}
 }
}
class MemberDirectory extends StatefulWidget{
 final Map<String,dynamic>? profile;final MemberStore store;
 const MemberDirectory({super.key,this.profile,this.store=const SupabaseMemberStore()});
 @override State<MemberDirectory> createState()=>_MemberDirectoryState();
}
class _MemberDirectoryState extends State<MemberDirectory>{
 final search=TextEditingController();List<Map<String,dynamic>> rows=[];Set<String> followed={},busyIds={};bool listed=false,loading=false,publishing=false,more=false;String? error;int revision=0;
 @override void initState(){super.initState();if(widget.profile!=null)load();}
 @override void dispose(){revision++;search.dispose();super.dispose();}
 Future<void> load({bool next=false})async{
  final ticket=++revision;final offset=next?rows.length:0;
  setState((){loading=true;error=null;});
  try{
   final id=widget.profile!['id'] as String;
   final card=await widget.store.ownCard(id);final saved=await widget.store.following(id);final members=await widget.store.members(id,search.text,offset);
   if(mounted&&ticket==revision)setState((){listed=card?['listed']==true;followed=saved;rows=[if(next)...rows,...members];more=members.length==20;});
  }catch(_){if(mounted&&ticket==revision)setState(()=>error='Could not load members. Please retry.');}
  finally{if(mounted&&ticket==revision)setState(()=>loading=false);}
 }
 Future<void> publish(bool value)async{
  setState(()=>publishing=true);
  try{await widget.store.publish(widget.profile!,value);if(mounted)setState(()=>listed=value);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Visibility was not saved. Please retry.')));}
  finally{if(mounted)setState(()=>publishing=false);}
 }
 Future<void> toggle(String id)async{
  if(busyIds.contains(id))return;final value=!followed.contains(id);setState(()=>busyIds.add(id));
  try{await widget.store.follow(widget.profile!['id'] as String,id,value);if(mounted)setState((){value?followed.add(id):followed.remove(id);});}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Follow change was not saved. Refresh and retry.')));}
  finally{if(mounted)setState(()=>busyIds.remove(id));}
 }
 Future<void> openProfile(String id)async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>MemberProfilePage(targetId:id,viewerId:widget.profile!['id'] as String)));if(mounted)await load();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('People & following'),actions:[if(widget.profile!=null)IconButton(tooltip:'Refresh people',onPressed:loading||publishing||busyIds.isNotEmpty?null:()=>load(),icon:const Icon(Icons.refresh_rounded))]),body:ListView(padding:const EdgeInsets.all(20),children:[
 const Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Jewel(Icons.people_alt_rounded,color:cyan),SizedBox(height:16),Text('Find your people',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800)),SizedBox(height:10),Text('Only members who choose to appear are listed. Following is separate from Friendship or CP.',style:TextStyle(color:Colors.white60,height:1.5))])),const SizedBox(height:18),
 if(widget.profile==null)const Glass(child:Text('Sign in to publish your member card and follow people. No follows are created in guest mode.'))
 else ...[
 SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Appear in People'),subtitle:const Text('Share your display name and numeric ID with signed-in members.'),value:listed,onChanged:loading||publishing?null:publish),
 TextField(controller:search,maxLength:80,textInputAction:TextInputAction.search,onSubmitted:(_)=>load(),decoration:InputDecoration(labelText:'Find member by name or ID',counterText:'',prefixIcon:const Icon(Icons.search_rounded),suffixIcon:IconButton(tooltip:'Search people',onPressed:()=>load(),icon:const Icon(Icons.arrow_forward_rounded)),border:const OutlineInputBorder())),
 const SizedBox(height:20),if(loading)const LinearProgressIndicator(),if(error!=null)TextButton(onPressed:()=>load(),child:Text(error!)),
 if(!loading&&error==null&&rows.isEmpty)const Glass(child:Text('No discoverable members found. Try another name or ID.')),
 for(final row in rows)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:followed.contains(row['user_id'])?gold:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[TextButton.icon(onPressed:()=>openProfile(row['user_id'] as String),icon:const Icon(Icons.account_circle_rounded),label:Text(row['display_name'].toString(),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold))),const SizedBox(height:8),SelectableText('ID · ${row['uid']}',style:const TextStyle(color:Colors.white60)),const SizedBox(height:12),FilledButton.icon(onPressed:busyIds.contains(row['user_id'])||loading?null:()=>toggle(row['user_id'] as String),icon:Icon(followed.contains(row['user_id'])?Icons.person_remove_alt_1_rounded:Icons.person_add_alt_1_rounded),label:Text(busyIds.contains(row['user_id'])?'Saving…':followed.contains(row['user_id'])?'Unfollow':'Follow'))]))),
 if(more&&!loading)TextButton(onPressed:()=>load(next:true),child:const Text('Load more people')),
 ],
 ]));
}
