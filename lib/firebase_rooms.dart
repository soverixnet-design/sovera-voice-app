import 'sovera_icons.dart';
import 'room_entry_scene.dart';
import 'firebase_members.dart';
import 'firebase_room_session.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_safety.dart';
import 'app_preferences.dart';
import 'firebase_catalog.dart';
import 'firebase_voice.dart';
import 'sovera_room_card.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_greedy_wheel.dart';

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
  Future<void> open(Map<String,dynamic> room)=>PersistentRoomLayer.open(context,widget.api,room).then((_){if(mounted)load();});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Sovera rooms'),actions:[
    IconButton(tooltip:'Greedy Wheel',onPressed:()=>Navigator.push(context,
      MaterialPageRoute<void>(builder:(_)=>FirebaseGreedyWheelPage(api:widget.api))),
      icon:const Icon(Icons.casino_rounded)),
    IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(16),children:[
    FilledButton.icon(onPressed:()=>Navigator.push(context,
      MaterialPageRoute<void>(builder:(_)=>FirebaseGreedyWheelPage(api:widget.api))),
      icon:const Icon(Icons.casino_rounded),label:const Text('Greedy Wheel · One server round')),
    const SizedBox(height:8),
    FilledButton.icon(onPressed:busy?null:create,icon:const Icon(Icons.add_home),label:const Text('Create / open my room')),
    const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('Public rooms, saved text chat and live audio.')),
    if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!),
    if(!busy&&rows.isEmpty&&error==null)const Text('No rooms yet. Create the first room.'),
    GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:rows.length,
      gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,mainAxisExtent:235,crossAxisSpacing:12,mainAxisSpacing:16),
      itemBuilder:(context,index)=>SoveraRoomCard(room:rows[index],onTap:()=>open(rows[index]))),
  ]));
}

/// Owner-only editor. The server verifies ownership again on PUT.
class FirebaseRoomSettingsDialog extends StatefulWidget {
  final String name;
  final int seats;
  final String frame;
  final FirebaseProfileApi? api;
  final String? roomId,imageUrl;
  const FirebaseRoomSettingsDialog({super.key,required this.name,required this.seats,this.frame='none',this.api,this.roomId,this.imageUrl});
  @override State<FirebaseRoomSettingsDialog> createState()=>_FirebaseRoomSettingsDialogState();
}
class _FirebaseRoomSettingsDialogState extends State<FirebaseRoomSettingsDialog>{
  late final TextEditingController name;
  late int seats;
  late String frame;
  String? imageUrl,photoError;
  bool uploading=false;
  @override void initState(){super.initState();name=TextEditingController(text:widget.name);seats=widget.seats;frame=widget.frame;imageUrl=widget.imageUrl;}
  @override void dispose(){name.dispose();super.dispose();}
  Future<void> choosePhoto()async{
    if(uploading||widget.api==null||widget.roomId==null)return;
    try{
      final photo=await ImagePicker().pickImage(source:ImageSource.gallery,maxWidth:1024,maxHeight:1024,imageQuality:85);
      if(photo==null||!mounted)return;
      setState((){uploading=true;photoError=null;});
      final url=await widget.api!.uploadPhoto(photo,suffix:'/rooms/${widget.roomId}/photo');
      if(mounted)setState(()=>imageUrl=url);
    }catch(_){if(mounted)setState(()=>photoError='Photo upload failed. Please retry.');}
    finally{if(mounted)setState(()=>uploading=false);}
  }
  @override Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Room settings'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(widget.api!=null)...[
        SizedBox(height:120,width:double.infinity,child:ClipRRect(borderRadius:BorderRadius.circular(18),child:SoveraRoomPhoto(room:{'image_url':imageUrl}))),
        TextButton.icon(onPressed:uploading?null:choosePhoto,icon:const Icon(Icons.photo_library_outlined),label:Text(uploading?'Uploading…':'Change room picture')),
        if(photoError!=null)Text(photoError!,style:const TextStyle(color:Colors.orange)),
      ],
      TextField(controller:name,maxLength:40,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Room name')),
      const SizedBox(height:8),
      const Text('Room card frame'),
      Wrap(spacing:8,children:[for(final option in const ['none','coins_seller','official'])
        ChoiceChip(label:Text(option=='none'?'None':option=='official'?'Official artwork':'Coin seller artwork'),selected:frame==option,onSelected:(_)=>setState(()=>frame=option))]),
      const SizedBox(height:8),
      const Text('Seats',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:6,children:[
        for(final count in const [5,6,9,12,15])
          ChoiceChip(label:Text('$count seats'),selected:seats==count,onSelected:(_)=>setState(()=>seats=count)),
      ]),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:uploading||name.text.trim().isEmpty?null:()=>Navigator.pop(context,{'name':name.text.trim(),'seats':seats,if(imageUrl!=widget.imageUrl)'image_url':imageUrl,if(frame!=widget.frame)'room_frame':frame}),child:const Text('Save changes')),
    ],
  );
}

/// Cosmetic room effects are deliberately separate from paid gift settlement.
class FirebaseRoomEffectPicker extends StatefulWidget {
  final List<Map<String,dynamic>> people;
  const FirebaseRoomEffectPicker({super.key,required this.people});
  @override State<FirebaseRoomEffectPicker> createState()=>_FirebaseRoomEffectPickerState();
}
class _FirebaseRoomEffectPickerState extends State<FirebaseRoomEffectPicker>{
  String? recipient;
  String effect='rose';
  @override void initState(){super.initState();if(widget.people.isNotEmpty)recipient=widget.people.first['uid'] as String?;}
  @override Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Send room effect'),
    content:SizedBox(width:340,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Select an online member',style:TextStyle(fontWeight:FontWeight.bold)),
      for(final person in widget.people) ListTile(
        dense:true,contentPadding:EdgeInsets.zero,
        leading:Icon(recipient==person['uid']?Icons.radio_button_checked:Icons.radio_button_unchecked),
        title:Text(person['name'].toString(),maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text('ID: ${person['uid']}',
          maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
        onTap:()=>setState(()=>recipient=person['uid'] as String),
      ),
      const SizedBox(height:8),
      const Text('Choose effect',style:TextStyle(fontWeight:FontWeight.bold)),
      Wrap(spacing:6,runSpacing:4,children:[
        for(final option in const ['rose','heart','sparkle','crown'])
          ChoiceChip(label:Text(option),selected:effect==option,onSelected:(_)=>setState(()=>effect=option)),
      ]),
      const Padding(padding:EdgeInsets.only(top:12),child:Text(
        'Free visual effect only. No Coins are spent and no Diamonds are awarded.',
        style:TextStyle(color:Colors.white70,fontSize:12))),
    ]))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:recipient==null?null:()=>Navigator.pop(context,{'recipient_uid':recipient!,'kind':effect}),
        child:const Text('Send effect')),
    ],
  );
}

class FirebaseRoomChat extends StatefulWidget {
  final FirebaseProfileApi api;final Map<String,dynamic> room;
  final VoidCallback? onMinimize,onLeave;
  const FirebaseRoomChat({super.key,required this.api,required this.room,this.onMinimize,this.onLeave});
  @override State<FirebaseRoomChat> createState()=>_FirebaseRoomChatState();
}
class _FirebaseRoomChatState extends State<FirebaseRoomChat> with WidgetsBindingObserver {
  final input=TextEditingController();final messages=<Map<String,dynamic>>[];
  Timer? timer;bool syncing=false,sending=false,savingRoom=false,sendingEffect=false;String? error,pendingId,pendingText;
  String? pendingEffectId,pendingEffectKey;
  List<Map<String,dynamic>> roomEffects=[],catalogEvents=[],roomPeople=[];
  int catalogServerNow=0;
  Map<String,dynamic>? pendingGift;
  Set<String> blocked={};
  Set<int> lockedSeats={};
  String roomRole='member';
  List<Map<String,dynamic>> roomAdmins=[];

  late String roomName;late int seatCount;late String roomFrame;String? roomImage;
  bool get isOwner=>widget.room['owner_uid']==widget.api.uid;
  DateTime? heartbeat;
  String get path=>'/rooms/${Uri.encodeComponent(widget.room['id'] as String)}';
  @override void initState(){super.initState();roomName=widget.room['name'] as String;roomFrame=(widget.room['room_frame']??'none') as String;roomImage=widget.room['image_url'] as String?;seatCount=widget.room['seats'] as int? ?? 9;WidgetsBinding.instance.addObserver(this);SoveraPreferences.lowData.addListener(start);start();}
  void start(){timer?.cancel();sync();timer=Timer.periodic(Duration(seconds:SoveraPreferences.lowData.value?15:5),(_)=>sync());}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed){heartbeat=null;start();}else if(state==AppLifecycleState.detached){timer?.cancel();}}
  @override void dispose(){SoveraPreferences.lowData.removeListener(start);WidgetsBinding.instance.removeObserver(this);timer?.cancel();input.dispose();unawaited(widget.api.call('DELETE',suffix:'$path/presence').then<void>((_){}).catchError((Object _){}));super.dispose();}
  Future<void> sync()async{
    if(syncing)return;syncing=true;
    try{
      if(heartbeat==null||DateTime.now().difference(heartbeat!)>=const Duration(seconds:30)){
        await widget.api.call('PUT',suffix:'$path/presence');heartbeat=DateTime.now();
      }
      try{
        final list=await widget.api.call('GET',suffix:'/community/blocks');
        if(mounted)setState(()=>blocked=(list['items'] as List).whereType<Map>().map((r)=>r['uid'].toString()).toSet());
      }catch(_){}
      try {
        final controls=await widget.api.call('GET',suffix:'$path/controls');
        if(mounted)setState((){
          final metadata=controls['room'];
          if(metadata is Map&&metadata['name'] is String&&metadata['seats'] is int){roomName=metadata['name'] as String;seatCount=metadata['seats'] as int;roomImage=metadata['image_url'] as String?;}
          roomRole=controls['role'] as String;lockedSeats=(controls['locked_seats'] as List).cast<int>().toSet();roomAdmins=(controls['admins'] as List).whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).toList();});
      }catch(_){}
      final data=await widget.api.call('GET',suffix:'$path/messages');
      if(mounted)setState((){messages..clear()..addAll((data['messages'] as List).map((r)=>Map<String,dynamic>.from(r as Map)));error=null;});
      try{
        final events=await widget.api.call('GET',suffix:'$path/catalog-events');
        final people=await widget.api.call('GET',suffix:'$path/people');
        if(mounted)setState((){catalogEvents=(events['items'] as List).whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).toList();catalogServerNow=(events['server_now'] as num).toInt();roomPeople=(people['people'] as List).whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).toList();});
      }catch(_){/* Existing room chat stays available during server rollout. */}
      // Older server versions may not support cosmetic effects yet.
      try{
        final events=await widget.api.call('GET',suffix:'$path/effects');
        final entries=events['effects'];
        if(mounted&&entries is List)setState(()=>roomEffects=entries.whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).toList());
      }catch(_){if(mounted)setState(()=>roomEffects=[]);}

    }catch(e){if(mounted)setState(()=>error=_error(e));}finally{syncing=false;}
  }
  Future<void> editRoom()async{
    if(!isOwner||savingRoom)return;
    final selected=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>
      FirebaseRoomSettingsDialog(name:roomName,seats:seatCount,frame:roomFrame,api:widget.api,roomId:widget.room['id'] as String,imageUrl:roomImage));
    if(!mounted||selected==null)return;
    setState(()=>savingRoom=true);
    try{
      final response=await widget.api.call('PUT',suffix:path,fields:selected);
      final saved=response['room'];
      if(saved is! Map||saved['name'] is! String||saved['seats'] is! int)throw const ProfileApiError('Invalid room response.');
      if(mounted)setState((){roomImage=saved['image_url'] as String? ?? roomImage;roomName=saved['name'] as String;seatCount=saved['seats'] as int;roomFrame=(saved['room_frame']??roomFrame) as String;error=null;});
    }catch(e){if(mounted)setState(()=>error=_error(e));}
    finally{if(mounted)setState(()=>savingRoom=false);}
  }
  Future<void> chooseEffect({bool legacy=false})async{
    if(sendingEffect)return;
    setState(()=>sendingEffect=true);
    try{
      List<Map<String,dynamic>> gifts=[];
      if(!legacy){
        final catalog=await widget.api.call('GET',suffix:'/catalog');
        gifts=(catalog['items'] as List).whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).where((r)=>r['kind']=='gift').toList();
        if(gifts.isEmpty&&pendingGift==null)throw const ProfileApiError('No published gifts yet. The owner can add gifts in the admin catalog.');
      }
      final found=await widget.api.call('GET',suffix:'$path/people');
      if(!mounted)return;
      final raw=found['people'];
      if(raw is! List)throw const ProfileApiError('Invalid member list');
      final people=raw.whereType<Map>().map((p)=>Map<String,dynamic>.from(p)).toList();
      if(people.isEmpty){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No online members yet.')));
        return;
      }
      if(gifts.isNotEmpty||pendingGift!=null){
        if(pendingGift==null){
          setState(()=>sendingEffect=false);
          final chosen=await showModalBottomSheet<Map<String,dynamic>>(
            context:context,isScrollControlled:true,useSafeArea:true,
            backgroundColor:const Color(0xFF17162B),
            builder:(context)=>FirebaseCatalogGiftPicker(api:widget.api,people:people,gifts:gifts));
          if(!mounted||chosen==null)return;
          pendingGift={...chosen,'request_id':_requestId()};
        }
        setState(()=>sendingEffect=true);
        final receipt=await widget.api.call('POST',suffix:'$path/gifts',fields:pendingGift);
        pendingGift=null;
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Gift sent · ${receipt['coins_spent']} Coins charged.')));
        await sync();return;
      }
      setState(()=>sendingEffect=false);
      final selected=await showDialog<Map<String,String>>(context:context,builder:(_)=>FirebaseRoomEffectPicker(people:people));
      if(!mounted||selected==null)return;
      setState(()=>sendingEffect=true);
      final key='${selected['recipient_uid']}:${selected['kind']}';
      if(pendingEffectKey!=key){pendingEffectId=_requestId();pendingEffectKey=key;}
      final response=await widget.api.call('POST',suffix:'$path/effects',fields:{
        ...selected,'request_id':pendingEffectId,
      });
      if(response['visual_only']!=true)throw const ProfileApiError('Unexpected effect response');
      pendingEffectId=null;pendingEffectKey=null;
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Room effect shared · no Coins spent.')));
      await sync();
    }catch(e){
      if(e is ProfileApiError&&e.status==409)pendingGift=null;
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_error(e))));
    }finally{if(mounted)setState(()=>sendingEffect=false);}
  }

  void launchGreedy()=>showModalBottomSheet<void>(
    context:context,isScrollControlled:true,useSafeArea:true,
    backgroundColor:const Color(0xFF12172D),
    builder:(sheetContext)=>SizedBox(height:MediaQuery.sizeOf(sheetContext).height,
      child:FirebaseGreedyWheelPage(api:widget.api,inRoom:true)));
  void openGame()=>showModalBottomSheet<void>(context:context,useSafeArea:true,
    backgroundColor:const Color(0xF5101424),builder:(sheetContext)=>Padding(
      padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('Room games',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:20),
        Align(alignment:Alignment.centerLeft,child:SizedBox(width:145,child:InkWell(
          borderRadius:BorderRadius.circular(22),onTap:(){Navigator.pop(sheetContext);launchGreedy();},
          child:Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[Color(0xFFFFCB59),Color(0xFF7750D9)])),child:const Column(children:[
            Icon(Icons.restaurant_rounded,size:64,color:Colors.white),SizedBox(height:10),Text('Greedy Wheel',style:TextStyle(fontWeight:FontWeight.bold,color:Colors.white)),
          ]))))),
        const SizedBox(height:16),
      ])));

  Future<void> manageAdmins() async {
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(context)=>SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.55,child:ListView(children:[
      const ListTile(title:Text('Room admins'),subtitle:Text('Only the owner can give or remove room permissions.')),
      for(final person in {for(final p in [...roomPeople,...roomAdmins])p['uid']:p}.values)
        if(person['uid']!=widget.api.uid)ListTile(title:Text(person['name']?.toString()??'Room member'),
          trailing:TextButton(child:Text(roomAdmins.any((a)=>a['uid']==person['uid'])?'Remove admin':'Make admin'),onPressed:()async{
            final enabled=!roomAdmins.any((a)=>a['uid']==person['uid']);
            Navigator.pop(context);
            try{await widget.api.call('PUT',suffix:'$path/admins',fields:{'uid':person['uid'],'enabled':enabled});await sync();}
            catch(e){if(mounted)setState(()=>error=_error(e));}
          })),
    ]))));
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
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFF0C0D0F),
    appBar:AppBar(backgroundColor:const Color(0xFF101C32),automaticallyImplyLeading:false,titleSpacing:10,
      title:Row(children:[InkWell(onTap:isOwner?editRoom:null,child:ClipRRect(borderRadius:BorderRadius.circular(12),child:SizedBox(width:42,height:42,child:SoveraRoomPhoto(room:{...widget.room,'image_url':roomImage})))),const SizedBox(width:8),
        Expanded(child:Text('${_flag((widget.room['country']??'').toString())} $roomName'.trim(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800))),
      ]),actions:[
      RoomDepthButton(tooltip:'Minimize room',icon:Icons.remove_rounded,onPressed:widget.onMinimize??()=>Navigator.maybePop(context)),
      RoomDepthButton(tooltip:'Leave room',icon:Icons.logout_rounded,exit:true,onPressed:widget.onLeave??()=>Navigator.pop(context)),
      Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Center(child:Row(children:[const Icon(Icons.people_outline,size:16,color:Color(0xFF8EE3DC)),const SizedBox(width:3),Text('${roomPeople.length}',style:const TextStyle(fontSize:12))]))),
    PopupMenuButton<String>(tooltip:'Room options',onSelected:(value){
      if(value=='settings')editRoom();
      if(value=='admins')manageAdmins();
      if(value=='effects')chooseEffect(legacy:true);
      if(value=='report')reportSovera(context,widget.api,'room',widget.room['id'].toString());
      if(value=='members')showModalBottomSheet<void>(context:context,builder:(context)=>SafeArea(
        child:ListView(children:[for(final person in roomPeople)ListTile(
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseMemberProfile(api:widget.api,uid:person['uid'].toString()))),title:Text(person['name'].toString()),trailing:SoveraSafetyMenu(api:widget.api,
            uid:person['uid'].toString(),name:person['name'].toString(),
            changed:(){setState(()=>blocked.add(person['uid'].toString()));sync();}))])));
    },itemBuilder:(_)=>[
      const PopupMenuItem(value:'members',child:Text('Room members')),
      const PopupMenuItem(value:'effects',child:Text('Free room effects')),
      if(isOwner)const PopupMenuItem(value:'settings',child:Text('Room settings')),
      if(isOwner)const PopupMenuItem(value:'admins',child:Text('Room admins')),
      const PopupMenuItem(value:'report',child:Text('Report room')),
    ])]),
    body:Stack(children:[Container(
      decoration:const BoxDecoration(gradient:LinearGradient(
        begin:Alignment.topLeft,end:Alignment.bottomRight,
        colors:[Color(0xFF173C48),Color(0xFF1B2243),Color(0xFF090F1F)])),
      child:SafeArea(child:Column(children:[
    // Original full-size seat artwork stays scrollable on short displays;
    // input stays fixed and accessible without layout overflow.
    Expanded(child:SingleChildScrollView(child:Column(children:[
    FirebaseVoicePanel(onLeaveRoom:widget.onLeave,api:widget.api,roomId:widget.room['id'] as String,seatCount:seatCount,people:roomPeople,blockedUids:blocked,autoConnect:true,roomRole:isOwner?'owner':roomRole,lockedSeats:lockedSeats,onControlsChanged:sync),
    if(catalogEvents.isNotEmpty&&(catalogEvents.first['asset'] as Map?)?['kind']!='entry')CatalogRoomAnimation(key:ValueKey(catalogEvents.first['event_id']),event:catalogEvents.first,serverNow:catalogServerNow,recipients:catalogEvents.where((r)=>r['id']==catalogEvents.first['id']&&r['sender_uid']==catalogEvents.first['sender_uid']&&r['created_at']==catalogEvents.first['created_at']).toList()),
    if(roomEffects.isNotEmpty)AnimatedSwitcher(
      duration:const Duration(milliseconds:300),
      child:Card(
        key:ValueKey(roomEffects.last['id']),
        color:const Color(0xFF37265A),
        child:ListTile(
          leading:const Icon(Icons.auto_awesome_rounded,color:Colors.amber),
          title:Text('${roomEffects.last['sender_name']} → ${roomEffects.last['recipient_name']}',
            maxLines:1,overflow:TextOverflow.ellipsis),
          subtitle:Text('${roomEffects.last['kind']} · Visual only · 15s',
            maxLines:1,overflow:TextOverflow.ellipsis),
        ),
      ),
    ),
    if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!)),
    for(final message in messages)
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),
        child:Card(elevation:6,shadowColor:Colors.black54,color:const Color(0xFF1A2A40),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),side:const BorderSide(color:Color(0xFF365667))),child:ListTile(
          onTap:message['uid'] is String?()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseMemberProfile(api:widget.api,uid:message['uid'] as String))):null,
          title:Text('${message['name']} ${_flag(message['country'].toString())}'),
          subtitle:Text(message['text'] as String),
          trailing:message['uid'] is String?SoveraSafetyMenu(
            api:widget.api,uid:message['uid'] as String,name:message['name'].toString(),
            changed:(){setState(()=>blocked.add(message['uid'] as String));sync();}):null))),
    ]))),
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,10),child:Row(children:[
      Expanded(child:TextField(controller:input,enabled:!sending,readOnly:pendingId!=null,maxLength:500,
        decoration:InputDecoration(hintText:'Say something…',counterText:'',isDense:true,filled:true,
          fillColor:Colors.white.withValues(alpha:.08),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none)))),
      IconButton(tooltip:'Send message',onPressed:sending?null:send,icon:const Icon(Icons.send_rounded)),
      IconButton(tooltip:'Room games',onPressed:openGame,icon:const Icon(Icons.sports_esports_rounded,color:Color(0xFFA28BFF))),
      IconButton(tooltip:'Gift box',onPressed:sendingEffect?null:chooseEffect,icon:const SoveraIcon(Icons.card_giftcard_rounded,size:42)),
    ])),
  ]))),Positioned.fill(child:RoomEntryScene(events:catalogEvents,serverNow:catalogServerNow))]));
}
