import 'sovera_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_community.dart' show communityRequestId;
import 'sovera_visuals.dart' show Glass, gold, cyan;

class FirebaseMessageInbox extends StatefulWidget {
  final FirebaseProfileApi api;
  final bool official;
  const FirebaseMessageInbox({super.key,required this.api,this.official=false});
  @override State<FirebaseMessageInbox> createState()=>_FirebaseMessageInboxState();
}
class _FirebaseMessageInboxState extends State<FirebaseMessageInbox> {
  List<Map<String,dynamic>> rows=[];
  bool loading=true;String? error;
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    setState(()=>loading=true);
    try{
      final result=await widget.api.call('GET',suffix:widget.official?'/official-inbox':'/messages');
      if(mounted){
        setState((){rows=(result['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();error=null;});
        if(widget.official&&ModalRoute.of(context)?.isCurrent==true&&rows.isNotEmpty){
          await widget.api.call('POST',suffix:'/message-read',fields:{'ids':rows.map((x)=>x['id'].toString()).toList()});
        }
      }
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load messages.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.official?'Official inbox':'Private messages'),actions:[IconButton(onPressed:loading?null:load,icon:const Icon(Icons.refresh))]),
    body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(18),children:[
      if(loading)const Center(child:CircularProgressIndicator()),
      if(error!=null)Text(error!),
      if(!loading&&error==null&&rows.isEmpty)const Text('No messages yet.'),
      for(final row in rows)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:widget.official?gold:cyan,child:ListTile(
        contentPadding:EdgeInsets.zero,
        trailing:!widget.official&&(row['unread'] as num? ?? 0)>0?Badge(label:Text('${row['unread']}')):null,
        leading:SoveraIcon(widget.official?Icons.campaign_rounded:Icons.chat_bubble_outline,size:42),
        title:Text('${row[widget.official?'title':'name']}',style:const TextStyle(fontWeight:FontWeight.bold)),
        subtitle:Text('${row['text']}',maxLines:widget.official?null:2,overflow:widget.official?null:TextOverflow.ellipsis),
        onTap:widget.official?null:()async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseDirectChat(api:widget.api,target:'${row['uid']}',name:'${row['name']}')));if(mounted)load();},
      ))),
    ])));
}

class FirebaseDirectChat extends StatefulWidget {
  final FirebaseProfileApi api;final String target,name;
  const FirebaseDirectChat({super.key,required this.api,required this.target,required this.name});
  @override State<FirebaseDirectChat> createState()=>_FirebaseDirectChatState();
}
class _FirebaseDirectChatState extends State<FirebaseDirectChat> {
  final input=TextEditingController(),scroll=ScrollController();
  Timer? timer;bool busy=false,loading=false,blocked=false;String? error;
  Map<String,dynamic>? pending;
  final List<Map<String,dynamic>> rows=[];
  @override void initState(){super.initState();load();timer=Timer.periodic(const Duration(seconds:5),(_)=>load());}
  @override void dispose(){timer?.cancel();input.dispose();scroll.dispose();super.dispose();}
  Future<void> load()async{
    if(loading)return;loading=true;
    try{
      var more=true;
      while(more&&mounted){
        final after=rows.isEmpty?0:rows.last['id'];
        final result=await widget.api.call('GET',suffix:'/messages/${Uri.encodeComponent(widget.target)}?after=$after');
        if(!mounted)return;
        setState((){blocked=result['blocked']==true;error=null;rows.addAll((result['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)));});
        more=result['has_more']==true;
        final incoming=(result['items'] as List).whereType<Map>().where((x)=>x['sender']!=widget.api.uid).map((x)=>'dm:${x['id']}').toList();
        if(incoming.isNotEmpty&&ModalRoute.of(context)?.isCurrent==true){
          await widget.api.call('POST',suffix:'/message-read',fields:{'ids':incoming});
        }
      }
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load chat.');}
    finally{loading=false;}
  }
  Future<void> send()async{
    if(busy||blocked||(pending==null&&input.text.trim().isEmpty))return;
    pending??={'text':input.text.trim(),'request_id':communityRequestId()};
    setState(()=>busy=true);
    try{
      await widget.api.call('POST',suffix:'/messages/${Uri.encodeComponent(widget.target)}',fields:pending);
      pending=null;input.clear();await load();
      if(mounted)WidgetsBinding.instance.addPostFrameCallback((_){if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);});
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Message not confirmed. Retry the same message.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.name)),body:SafeArea(child:Column(children:[
      if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!)),
      Expanded(child:ListView(controller:scroll,padding:const EdgeInsets.all(16),children:[
        if(rows.isEmpty)const Text('Start a private conversation.'),
        for(final row in rows)Align(alignment:row['sender']==widget.api.uid?Alignment.centerRight:Alignment.centerLeft,child:Container(
          margin:const EdgeInsets.symmetric(vertical:5),padding:const EdgeInsets.all(14),
          constraints:const BoxConstraints(maxWidth:310),decoration:BoxDecoration(color:row['sender']==widget.api.uid?const Color(0xff264e61):const Color(0xff29283f),borderRadius:BorderRadius.circular(18)),
          child:Text('${row['text']}'))),
      ])),
      if(blocked)const Padding(padding:EdgeInsets.all(16),child:Text('Messaging unavailable for this member.'))
      else Padding(padding:const EdgeInsets.all(12),child:Row(children:[
        Expanded(child:TextField(controller:input,readOnly:busy||pending!=null,maxLength:1000,minLines:1,maxLines:4,decoration:const InputDecoration(hintText:'Message',counterText:''))),
        IconButton(tooltip:pending==null?'Send message':'Retry message',onPressed:busy?null:send,icon:Icon(pending==null?Icons.send_rounded:Icons.refresh)),
      ])),
    ])));
}
