import 'package:flutter/material.dart';
import 'main.dart';
import 'auth_gate.dart';

class SavedSupportPage extends StatefulWidget{
 final String title;
 const SavedSupportPage({super.key,required this.title});
 @override State<SavedSupportPage> createState()=>_SavedSupportPageState();
}
class _SavedSupportPageState extends State<SavedSupportPage>{
 final input=TextEditingController();
 List<Map<String,dynamic>> tickets=[];
 bool busy=false,loading=true;String? error;
 @override void initState(){super.initState();load();}
 @override void dispose(){input.dispose();super.dispose();}
 Future<void> load()async{
  try{
   final rows=await soveraClient.from('sovera_support_tickets').select().eq('topic',widget.title).order('created_at',ascending:false).limit(30);
   if(mounted)setState((){tickets=rows;loading=false;error=null;});
  }catch(_){if(mounted)setState((){loading=false;error='Could not load support history.';});}
 }
 Future<void> submit()async{
  final message=input.text.trim();
  if(message.isEmpty||message.length>1000||busy)return;
  final user=soveraClient.auth.currentUser;if(user==null)return;
  setState(()=>busy=true);
  try{
   await soveraClient.from('sovera_support_tickets').insert({'user_id':user.id,'topic':widget.title,'message':message});
   if(!mounted)return;
   input.clear();
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Support request saved.')));
   await load();
  }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Request was not saved. Your message is still here; please retry.')));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.title)),body:ListView(padding:const EdgeInsets.all(22),children:[
  const Center(child:BrandLogo(size:76)),const SizedBox(height:24),
  const Text('Send a private support request. Requests are stored for review; replies and response times are not available in this version.',style:TextStyle(color:Colors.white70)),
  const SizedBox(height:20),TextField(controller:input,enabled:!busy,maxLines:5,maxLength:1000,decoration:const InputDecoration(labelText:'Support message',border:OutlineInputBorder())),
  FilledButton(onPressed:busy?null:submit,child:Text(busy?'Saving…':'Submit support request')),
  const SizedBox(height:24),const Text('Your requests',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:12),
  if(loading)const Center(child:CircularProgressIndicator()),
  if(error!=null)TextButton(onPressed:load,child:Text('$error Tap to retry.')),
  if(!loading&&error==null&&tickets.isEmpty)const Text('No requests yet.',style:TextStyle(color:Colors.white54)),
  for(final ticket in tickets)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Text('${ticket['status']} · ${(ticket['created_at'] as String).substring(0,10)}',style:const TextStyle(color:cyan,fontSize:11)),const SizedBox(height:10),Text(ticket['message'] as String),
  ]))),
 ]));
}
