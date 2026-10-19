import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_voice.dart';
import 'country_picker.dart' show soveraCountries;

String _flag(String code) => RegExp(r'^[A-Z]{2}$').hasMatch(code)
    ? String.fromCharCodes(code.codeUnits.map((c)=>c+127397)) : '';
String _requestId() {
  final rng=Random.secure();final h=List.generate(16,(_)=>rng.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
  return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}
String _error(Object e)=>e is ProfileApiError?e.message:'Could not connect. Please retry.';

class FirebaseRoomsPage extends StatefulWidget {
  final FirebaseProfileApi api;
  const FirebaseRoomsPage({super.key,required this.api});
  @override State<FirebaseRoomsPage> createState()=>_FirebaseRoomsPageState();
}
class _FirebaseRoomsPageState extends State<FirebaseRoomsPage> {
  List<Map<String,dynamic>> rows=[];bool busy=false;String? error;
  Timer? timer;
  @override void initState(){super.initState();load();timer=Timer.periodic(const Duration(seconds:30),(_)=>load());}
  @override void dispose(){timer?.cancel();super.dispose();}
  Future<void> load()async{
    if(busy)return;setState((){busy=true;error=null;});
    try{final data=await widget.api.call('GET',suffix:'/rooms');if(mounted)setState(()=>rows=(data['rooms'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList());}
    catch(e){if(mounted)setState(()=>error=_error(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> create()async{
    var draft='';
    final name=await showDialog<String>(context:context,builder:(context)=>AlertDialog(title:const Text('My room'),content:TextField(onChanged:(value)=>draft=value,maxLength:40,decoration:const InputDecoration(labelText:'Room name')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,draft.trim()),child:const Text('Open my room'))]));
    if(!mounted||name==null||name.isEmpty)return;
    setState(()=>busy=true);
    try{final data=await widget.api.call('POST',suffix:'/rooms',fields:{'name':name,'seats':9});if(!mounted)return;await open(Map<String,dynamic>.from(data['room'] as Map));}
    catch(e){if(mounted)setState(()=>error=_error(e));}
    finally{if(mounted){setState(()=>busy=false);load();}}
  }
  Future<void> open(Map<String,dynamic> room)=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>FirebaseRoomChat(api:widget.api,room:room))).then((_){if(mounted)load();});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Sovera rooms'),actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(16),children:[
    FilledButton.icon(onPressed:busy?null:create,icon:const Icon(Icons.add_home),label:const Text('Create / open my room')),
    const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('Public rooms, saved text chat and live audio.')),
    if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!),
    if(!busy&&rows.isEmpty&&error==null)const Text('No rooms yet. Create the first room.'),
    for(final room in rows)Card(child:ListTile(
      leading:CircleAvatar(backgroundImage:room['avatar_url'] is String?NetworkImage(room['avatar_url'] as String):null,child:room['avatar_url']==null?const Icon(Icons.meeting_room):null),
      title:Text('${room['name']} ${_flag((room['country']??'').toString())}'),
      subtitle:Text('${room['owner_name']} · ${soveraCountries[room['country']]??room['country']}\n${room['occupants']} members with a recent room heartbeat'),
      isThreeLine:true,trailing:const Icon(Icons.chevron_right),onTap:()=>open(room))),
  ]));
}

/// Owner-only editor. The server verifies ownership again on PUT.
class FirebaseRoomSettingsDialog extends StatefulWidget {
  final String name;
  final int seats;
  const FirebaseRoomSettingsDialog({super.key,required this.name,required this.seats});
  @override State<FirebaseRoomSettingsDialog> createState()=>_FirebaseRoomSettingsDialogState();
}
class _FirebaseRoomSettingsDialogState extends State<FirebaseRoomSettingsDialog>{
  late final TextEditingController name;
  late int seats;
  @override void initState(){super.initState();name=TextEditingController(text:widget.name);seats=widget.seats;}
  @override void dispose(){name.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Room settings'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      TextField(controller:name,maxLength:40,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Room name')),
      const SizedBox(height:8),
      const Text('Seats',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:6,children:[
        for(final count in const [5,6,9,12])
          ChoiceChip(label:Text('$count seats'),selected:seats==count,onSelected:(_)=>setState(()=>seats=count)),
      ]),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:name.text.trim().isEmpty?null:()=>Navigator.pop(context,{'name':name.text.trim(),'seats':seats}),child:const Text('Save changes')),
    ],
  );
}

class FirebaseRoomChat extends StatefulWidget {
  final FirebaseProfileApi api;final Map<String,dynamic> room;
  const FirebaseRoomChat({super.key,required this.api,required this.room});
  @override State<FirebaseRoomChat> createState()=>_FirebaseRoomChatState();
}
class _FirebaseRoomChatState extends State<FirebaseRoomChat> with WidgetsBindingObserver {
  final input=TextEditingController();final messages=<Map<String,dynamic>>[];
  Timer? timer;bool syncing=false,sending=false,savingRoom=false;String? error,pendingId,pendingText;
  late String roomName;late int seatCount;
  bool get isOwner=>widget.room['owner_uid']==widget.api.uid;
  DateTime? heartbeat;
  String get path=>'/rooms/${Uri.encodeComponent(widget.room['id'] as String)}';
  @override void initState(){super.initState();roomName=widget.room['name'] as String;seatCount=widget.room['seats'] as int? ?? 9;WidgetsBinding.instance.addObserver(this);start();}
  void start(){timer?.cancel();sync();timer=Timer.periodic(const Duration(seconds:5),(_)=>sync());}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed){heartbeat=null;start();}else{timer?.cancel();}}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);timer?.cancel();input.dispose();unawaited(widget.api.call('DELETE',suffix:'$path/presence').then<void>((_){}).catchError((Object _){}));super.dispose();}
  Future<void> sync()async{
    if(syncing)return;syncing=true;
    try{
      if(heartbeat==null||DateTime.now().difference(heartbeat!)>=const Duration(seconds:30)){
        await widget.api.call('PUT',suffix:'$path/presence');heartbeat=DateTime.now();
      }
      final data=await widget.api.call('GET',suffix:'$path/messages');
      if(mounted)setState((){messages..clear()..addAll((data['messages'] as List).map((r)=>Map<String,dynamic>.from(r as Map)));error=null;});
    }catch(e){if(mounted)setState(()=>error=_error(e));}finally{syncing=false;}
  }
  Future<void> editRoom()async{
    if(!isOwner||savingRoom)return;
    final selected=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>
      FirebaseRoomSettingsDialog(name:roomName,seats:seatCount));
    if(!mounted||selected==null)return;
    setState(()=>savingRoom=true);
    try{
      final response=await widget.api.call('PUT',suffix:path,fields:selected);
      final saved=response['room'];
      if(saved is! Map||saved['name'] is! String||saved['seats'] is! int)throw const ProfileApiError('Invalid room response.');
      if(mounted)setState((){roomName=saved['name'] as String;seatCount=saved['seats'] as int;error=null;});
    }catch(e){if(mounted)setState(()=>error=_error(e));}
    finally{if(mounted)setState(()=>savingRoom=false);}
  }
  Future<void> send()async{
    final text=input.text.trim();if(sending||text.isEmpty)return;
    if(pendingText!=null&&pendingText!=text){setState(()=>error='Retry the pending message before changing its text.');return;}
    pendingText=text;pendingId??=_requestId();setState(()=>sending=true);
    try{
      await widget.api.call('POST',suffix:'$path/messages',fields:{'text':text,'request_id':pendingId});
      if(!mounted)return;
      input.clear();pendingId=null;pendingText=null;await sync();
    }catch(e){if(mounted)setState(()=>error=_error(e));}finally{if(mounted)setState(()=>sending=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(roomName),actions:[if(isOwner)IconButton(tooltip:'Room settings',onPressed:savingRoom?null:editRoom,icon:const Icon(Icons.tune_rounded))]),body:SafeArea(child:Column(children:[
    if(isOwner)Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('$seatCount seats · Owner settings',style:const TextStyle(fontSize:12,color:Colors.white70))),
    FirebaseVoicePanel(api:widget.api,roomId:widget.room['id'] as String),
    if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!)),
    Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[for(final message in messages)Card(child:ListTile(title:Text('${message['name']} ${_flag(message['country'].toString())}'),subtitle:Text(message['text'] as String)))])),
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:input,enabled:!sending,readOnly:pendingId!=null,maxLength:500,decoration:const InputDecoration(labelText:'Message'))),IconButton(onPressed:sending?null:send,icon:const Icon(Icons.send))])),
  ])));
}
