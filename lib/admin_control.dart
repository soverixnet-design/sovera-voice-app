import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_gate.dart';
import 'main.dart' show gold, cyan, Glass;

class VipIdentityBadge extends StatelessWidget {
 final Object? value;
 const VipIdentityBadge({super.key,this.value});
 @override Widget build(BuildContext context)=>value==null?const SizedBox.shrink():Container(margin:const EdgeInsets.symmetric(vertical:10),padding:const EdgeInsets.symmetric(horizontal:18,vertical:8),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF655022),Color(0xFF30263C)]),borderRadius:BorderRadius.circular(12),border:Border.all(color:gold),boxShadow:[BoxShadow(color:gold.withValues(alpha:.16),blurRadius:18)]),child:Text('♛ VIP ID · $value',style:const TextStyle(color:gold,fontSize:20,fontWeight:FontWeight.bold)));
}
class AdminControlEntry extends StatefulWidget {
 final String userId;
 const AdminControlEntry({super.key,required this.userId});
 @override State<AdminControlEntry> createState()=>_AdminControlEntryState();
}
class _AdminControlEntryState extends State<AdminControlEntry>{
 late final Future<Map<String,dynamic>?> access;
 @override void initState(){super.initState();access=load();}
 Future<Map<String,dynamic>?> load()async{try{return await soveraClient.from('sovera_admin_staff').select('role,active').eq('user_id',widget.userId).maybeSingle();}catch(_){return null;}}
 @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>?>(future:access,builder:(context,snapshot)=>snapshot.data?['active']!=true?const SizedBox.shrink():ListTile(leading:const Icon(Icons.admin_panel_settings_rounded,color:gold),title:const Text('Admin Control'),subtitle:Text('Assigned role · ${snapshot.data!['role']}'),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const AdminControlPage()))));
}
class AdminControlPage extends StatefulWidget {
 const AdminControlPage({super.key});
 @override State<AdminControlPage> createState()=>_AdminControlPageState();
}
class _AdminControlPageState extends State<AdminControlPage>{
 String? code,error;bool busy=false;
 Future<void> generate()async{
  if(busy)return;setState((){busy=true;error=null;code=null;});
  try{final result=await soveraClient.rpc('sovera_create_admin_code');if(result is! String||result.length!=64)throw StateError('Invalid code');if(mounted)setState(()=>code=result);}
  catch(_){if(mounted)setState(()=>error='Admin access is not assigned, or the server is not activated. Contact the owner.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Admin Control')),body:ListView(padding:const EdgeInsets.all(22),children:[
 const Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.admin_panel_settings_rounded,size:50,color:gold),SizedBox(height:16),Text('Your staff workspace',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold)),SizedBox(height:10),Text('Generate a one-time sign-in code, then paste it into the Sovera control panel. Your role and permissions are checked by the server.')])),
 const SizedBox(height:20),FilledButton.icon(onPressed:busy?null:generate,icon:const Icon(Icons.key_rounded),label:Text(busy?'Creating code…':'Generate one-time code')),
 if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.orange))),
 if(code!=null)Padding(padding:const EdgeInsets.only(top:18),child:Glass(tint:cyan,child:Column(children:[SelectableText(code!,style:const TextStyle(fontFamily:'monospace',fontSize:13)),const SizedBox(height:12),const Text('Valid for five minutes · One use only. Do not share this code with anyone.'),TextButton.icon(onPressed:()async{await Clipboard.setData(ClipboardData(text:code!));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Admin sign-in code copied.')));},icon:const Icon(Icons.copy_rounded),label:const Text('Copy sign-in code'))]))),
 const SizedBox(height:18),OutlinedButton.icon(onPressed:()async{final opened=await launchUrl(Uri.parse('https://sovera-control.soverixnet.chatgpt.site'),mode:LaunchMode.externalApplication);if(!opened&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open the control panel.')));},icon:const Icon(Icons.open_in_browser_rounded),label:const Text('Open web control panel')),
 ]));
}
class PublishedCommunityContent extends StatefulWidget {
 final String kind;
 const PublishedCommunityContent({super.key,required this.kind});
 @override State<PublishedCommunityContent> createState()=>_PublishedCommunityContentState();
}
class _PublishedCommunityContentState extends State<PublishedCommunityContent>{
 late Future<List<Map<String,dynamic>>> items;
 @override void initState(){super.initState();items=load();}
 Future<List<Map<String,dynamic>>> load()async{try{return await soveraClient.from('sovera_admin_content').select('title,payload').eq('kind',widget.kind).eq('published',true).order('updated_at',ascending:false).limit(30);}catch(_){return [];}}
 @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(future:items,builder:(context,snapshot){final rows=snapshot.data??[];if(rows.isEmpty)return widget.kind=='banner'?const SizedBox.shrink():const Padding(padding:EdgeInsets.all(24),child:Text('No published announcements yet.'));return Column(children:[for(final row in rows)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 if((row['payload'] as Map?)?['asset_url'] is String && ((row['payload'] as Map)['asset_url'] as String).startsWith('https://'))ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.network((row['payload'] as Map)['asset_url'] as String,height:150,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox.shrink())),
 const SizedBox(height:8),Text(row['title'].toString(),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),if((row['payload'] as Map?)?['text']!=null)Text((row['payload'] as Map)['text'].toString()),
 if(widget.kind=='event')const Padding(padding:EdgeInsets.only(top:10),child:Text('Published event configuration · Live scoring and automatic rewards are not connected.',style:TextStyle(fontSize:11,color:Colors.white54))),
 ]))) ]);});
}
