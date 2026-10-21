import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_profile.dart';
import 'firebase_safety.dart';
import 'sovera_visuals.dart' show Glass, cyan, gold, violet;

String communityRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}

class FirebaseCommunity extends StatefulWidget {
  final FirebaseProfileApi api;
  final String section, title;
  final bool embedded;
  const FirebaseCommunity({super.key, required this.api, required this.section,
    required this.title, this.embedded=false});
  @override State<FirebaseCommunity> createState() => _FirebaseCommunityState();
}

class _FirebaseCommunityState extends State<FirebaseCommunity> {
  List<Map<String,dynamic>> items=[];
  bool loading=true, sending=false;
  String? error, pendingText, pendingId;
  final input=TextEditingController();
  bool get writable => widget.section=='moments'||widget.section=='support';
  @override void initState(){super.initState();load();}
  @override void dispose(){input.dispose();super.dispose();}
  Future<void> load()async{
    setState((){loading=true;error=null;});
    try{
      final result=await widget.api.call('GET',suffix:'/community/${widget.section}');
      final rows=result['items'];
      if(rows is! List)throw const ProfileApiError('Invalid community response.');
      if(mounted)setState(()=>items=rows.map((r)=>Map<String,dynamic>.from(r as Map)).toList());
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load this page. Please retry.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> send()async{
    final text=input.text.trim();
    if(text.isEmpty||sending)return;
    pendingText??=text;pendingId??=communityRequestId();
    if(pendingText!=text)return;
    setState((){sending=true;error=null;});
    try{
      await widget.api.call('POST',suffix:'/community/${widget.section}',fields:{'text':text,'request_id':pendingId});
      if(!mounted)return;
      input.clear();pendingText=null;pendingId=null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.section=='support'?'Message sent to support.':'Moment published.')));
      await load();
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not send. Tap Retry send.');}
    finally{if(mounted)setState(()=>sending=false);}
  }
  Widget content()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Expanded(child:Text(widget.title,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800))),IconButton(tooltip:'Refresh',onPressed:loading?null:load,icon:const Icon(Icons.refresh_rounded))]),
    if(writable)...[
      Glass(tint:violet,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(controller:input,readOnly:pendingId!=null,enabled:!sending,maxLength:1000,minLines:2,maxLines:5,
          decoration:InputDecoration(labelText:widget.section=='support'?'How can we help?':'Write a moment',border:InputBorder.none)),
        FilledButton.icon(onPressed:sending?null:send,icon:const Icon(Icons.send_rounded),label:Text(sending?'Sending…':pendingId!=null?'Retry send':widget.section=='support'?'Send to support':'Publish moment')),
      ])),const SizedBox(height:18),
    ],
    if(loading)const LinearProgressIndicator(),
    if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Colors.orange.shade200))),
    if(!loading&&error==null&&items.isEmpty)const Glass(child:Text('Nothing here yet. Pull new updates with Refresh.')),
    for(final row in items)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(row['name']!=null||row['title']!=null)Text((row['name']??row['title']).toString(),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
      if((widget.section=='members'||widget.section=='moments')&&row['uid']!=null)
        SoveraSafetyMenu(api:widget.api,uid:row['uid'].toString(),name:(row['name']??'User').toString(),changed:load),
      if(widget.section=='blocks')TextButton(onPressed:()async{
        try{
          await widget.api.call('DELETE',suffix:'/community/blocks/${Uri.encodeComponent(row['uid'].toString())}');
          if(mounted)await load();
        }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not unblock. Retry.');}
      },child:const Text('Unblock')),
      if(row['text']!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),child:SelectableText(row['text'].toString())),
      if(widget.section=='members')...[
        Text('Country · ${row['country']??''}',style:const TextStyle(color:Colors.white60)),
        const SizedBox(height:8),SelectableText('Account · ${row['uid']}',style:const TextStyle(fontSize:11,color:cyan)),
      ],
      if(widget.section=='support')Text((row['reply']??'').toString().isEmpty?'Waiting for a support reply':'Support: ${row['reply']}',style:const TextStyle(color:gold)),
      if(row['created_at'] is num)Text(DateTime.fromMillisecondsSinceEpoch((row['created_at'] as num).toInt()*1000).toLocal().toString().split('.').first,style:const TextStyle(color:Colors.white54,fontSize:11)),
    ]))),
  ]);
  @override Widget build(BuildContext context)=>widget.embedded?content():Scaffold(
    appBar:AppBar(title:Text(widget.title)),body:RefreshIndicator(onRefresh:load,
      child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(18),children:[content()])));
}

class FirebaseStaffPage extends StatefulWidget{
  final FirebaseProfileApi api;
  final String role;
  const FirebaseStaffPage({super.key,required this.api,required this.role});
  @override State<FirebaseStaffPage> createState()=>_FirebaseStaffPageState();
}
class _FirebaseStaffPageState extends State<FirebaseStaffPage>{
  final title=TextEditingController(),text=TextEditingController();
  List<Map<String,dynamic>> tickets=[];
  String section='notices';String? error,requestId;
  bool busy=false;
  @override void initState(){super.initState();if(widget.role!='agent')load();}
  @override void dispose(){title.dispose();text.dispose();super.dispose();}
  Future<void> load()async{
    try{final data=await widget.api.call('GET',suffix:'/staff/support');if(mounted)setState(()=>tickets=(data['items'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList());}
    catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load support inbox.');}
  }
  Future<void> publish()async{
    if(busy||title.text.trim().isEmpty||text.text.trim().isEmpty)return;
    requestId??=communityRequestId();setState((){busy=true;error=null;});
    try{
      await widget.api.call('POST',suffix:'/staff/publications',fields:{'section':section,'title':title.text.trim(),'text':text.text.trim(),'request_id':requestId});
      if(!mounted)return;
      title.clear();text.clear();requestId=null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Published to the community.')));
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not publish.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> reply(Map<String,dynamic> ticket)async{
    var draft=(ticket['reply']??'').toString();
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Reply to support request'),content:TextFormField(initialValue:draft,maxLength:1000,maxLines:4,onChanged:(value)=>draft=value),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,draft.trim()),child:const Text('Send reply'))]));
    if(result==null||result.isEmpty||!mounted)return;
    try{await widget.api.call('PUT',suffix:'/staff/support/${ticket['id']}',fields:{'text':result,'request_id':communityRequestId()});if(mounted)await load();}
    catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Reply was not sent.');}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Community admin')),body:ListView(padding:const EdgeInsets.all(18),children:[
    FirebaseControlAccess(api:widget.api),
    const SizedBox(height:18),
    if(error!=null)Text(error!,style:TextStyle(color:Colors.orange.shade200)),
    if(widget.role=='owner'||widget.role=='admin')Glass(tint:violet,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Publish an update',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
      Wrap(spacing:8,children:[for(final s in ['notices','events'])ChoiceChip(label:Text(s=='notices'?'Official notice':'Community event'),selected:section==s,onSelected:busy||requestId!=null?null:(_)=>setState(()=>section=s))]),
      TextField(controller:title,readOnly:requestId!=null,maxLength:100,decoration:const InputDecoration(labelText:'Title')),
      TextField(controller:text,readOnly:requestId!=null,maxLength:1000,maxLines:4,decoration:const InputDecoration(labelText:'Details')),
      FilledButton(onPressed:busy?null:publish,child:Text(busy?'Publishing…':requestId!=null?'Retry publication':'Publish')),
    ])),
    if(widget.role!='agent')...[
    const SizedBox(height:22),Row(children:[const Expanded(child:Text('Support inbox',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold))),IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    for(final ticket in tickets)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(ticket['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:10),Text(ticket['text'].toString()),if((ticket['reply']??'').toString().isNotEmpty)Text('Reply: ${ticket['reply']}',style:const TextStyle(color:gold)),TextButton.icon(onPressed:()=>reply(ticket),icon:const Icon(Icons.reply),label:const Text('Reply'))]))),
    ],
  ]));
}

class FirebaseControlAccess extends StatefulWidget{
  final FirebaseProfileApi api;
  const FirebaseControlAccess({super.key,required this.api});
  @override State<FirebaseControlAccess> createState()=>_FirebaseControlAccessState();
}
class _FirebaseControlAccessState extends State<FirebaseControlAccess>{
  bool busy=false;String? code,error;
  Future<void> generate()async{
    setState((){busy=true;error=null;code=null;});
    try{
      final result=await widget.api.call('POST',suffix:'/staff/access-code');
      final value=result['code'];
      if(value is! String||!RegExp(r'^[a-f0-9]{64}$').hasMatch(value))throw const ProfileApiError('Invalid admin code response.');
      if(mounted)setState(()=>code=value);
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not generate admin access.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Text('Sovera Control',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const SizedBox(height:10),const Text('Generate a code, open admin.soverixnet.com and paste it to sign in. Each code expires after five minutes and works once.'),
    const SizedBox(height:12),FilledButton.icon(onPressed:busy?null:generate,icon:const Icon(Icons.key_rounded),label:Text(busy?'Generating…':'Generate admin sign-in code')),
    if(error!=null)Text(error!,style:TextStyle(color:Colors.orange.shade200)),
    if(code!=null)...[
      const SizedBox(height:12),SelectableText(code!,style:const TextStyle(fontFamily:'monospace',fontSize:12)),
      TextButton.icon(onPressed:()async{await Clipboard.setData(ClipboardData(text:code!));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Code copied. Keep it private.')));},icon:const Icon(Icons.copy),label:const Text('Copy code')),
    ],
    OutlinedButton.icon(onPressed:()async{
      final opened=await launchUrl(Uri.parse('https://admin.soverixnet.com'),mode:LaunchMode.externalApplication);
      if(!opened&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open admin panel.')));
    },icon:const Icon(Icons.open_in_browser),label:const Text('Open admin panel')),
  ]));
}
