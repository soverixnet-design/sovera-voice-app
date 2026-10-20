import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'firebase_profile.dart';
import 'country_picker.dart' show soveraCountries;
import 'firebase_rooms.dart';
import 'firebase_greedy_wheel.dart';
import 'sovera_visuals.dart' show BrandLogo, Glass, Jewel, violet, gold, pink, cyan;

/// Restores the ORIGINAL Sovera Home/Moments/Messages/Me visual hierarchy.
/// Data for rooms and users is from Firebase-authenticated account APIs,
/// never from the separate Supabase account or fake room fixtures.
class FirebaseSoveraHome extends StatefulWidget {
  final User user;
  // The test harness can supply a mocked server client. Production always
  // uses the signed-in Firebase user token from the normal constructor.
  final FirebaseProfileApi? apiOverride;
  const FirebaseSoveraHome({super.key,required this.user,this.apiOverride});
  @override State<FirebaseSoveraHome> createState()=>_FirebaseSoveraHomeState();
}

class _FirebaseSoveraHomeState extends State<FirebaseSoveraHome>{
  final http.Client client=http.Client();
  late final FirebaseProfileApi api=widget.apiOverride??FirebaseProfileApi(
    uid:widget.user.uid,client:client,
    token:()async=>FirebaseAuth.instance.currentUser?.uid==widget.user.uid
      ? widget.user.getIdToken():null,
  );
  final search=TextEditingController();
  Timer? refreshTimer;
  List<Map<String,dynamic>> rooms=[];
  Map<String,dynamic>? profile;
  String? error;
  int tab=0,banner=0;
  bool loading=false,creating=false;
  String query='',filter='All';
  final posts=<String>[];
  final followed=<String>{}; // Local preview only; no fake server follows.
  final slides=const <(String,String,IconData,Color)>[
    ('Your voice. Your world.','Create a room and make it yours.',Icons.mic_rounded,violet),
    ('Sovera Hall of Fame','Greedy Wheel · One server round for everyone.',Icons.emoji_events_rounded,gold),
    ('Something worth celebrating','Voice rooms, gifts and community.',Icons.celebration_rounded,pink),
  ];
  @override void initState(){
    super.initState();
    refresh();
    refreshTimer=Timer.periodic(const Duration(seconds:30),(_)=>refresh(silent:true));
  }
  @override void dispose(){refreshTimer?.cancel();search.dispose();client.close();super.dispose();}
  void say(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  void go(Widget page)=>Navigator.of(context).push<void>(
    MaterialPageRoute(builder:(_)=>page));
  Future<void> refresh({bool silent=false})async{
    if(loading)return;
    if(!silent&&mounted)setState((){loading=true;error=null;});
    try{
      final data=await api.call('GET',suffix:'/rooms');
      final p=await api.load();
      if(mounted)setState((){
        rooms=(data['rooms'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
        profile=p;error=null;
      });
    }catch(e){if(mounted&&!silent)setState(()=>error=e is ProfileApiError?e.message:'Could not load rooms. Check connection.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  String get displayName => profile?['display_name'] as String? ??
      widget.user.displayName??'Sovera user';
  bool get hasProfile=>profile!=null;
  static String flag(String country){
    if(!RegExp(r'^[A-Z]{2}$').hasMatch(country))return '';
    return String.fromCharCodes(country.codeUnits.map((c)=>c+127397));
  }
  Future<void> editProfile()async{
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder:(_)=>Scaffold(
        appBar:AppBar(title:const Text('Edit Profile')),
        body:SafeArea(child:SingleChildScrollView(
          padding:const EdgeInsets.all(18),
          child:FirebaseProfileEditor(
            api:api,initialName:displayName,
            onSaved:()=>Navigator.of(context).pop(),
          ),
        )),
      ),
    ));
    if(mounted)await refresh();
  }
  Future<void> createRoom()async{
    if(creating)return;
    if(!hasProfile){setState(()=>tab=3);say('Complete your profile before creating a room.');return;}
    final mine=rooms.where((r)=>r['owner_uid']==widget.user.uid).toList();
    if(mine.isNotEmpty){openRoom(mine.first);return;}
    String draft='';
    final name=await showDialog<String>(context:context,builder:(ctx)=>
      AlertDialog(title:const Text('Create your room'),
        content:TextField(maxLength:40,decoration:const InputDecoration(labelText:'Room name'),
          onChanged:(v)=>draft=v),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,draft.trim()),
            child:const Text('Create'))]));
    if(name==null||name.isEmpty||!mounted)return;
    setState(()=>creating=true);
    try{
      final result=await api.call('POST',suffix:'/rooms',fields:{'name':name,'seats':9});
      final room=Map<String,dynamic>.from(result['room'] as Map);
      await refresh(silent:true);
      if(mounted)openRoom(room);
    }catch(e){say(e is ProfileApiError?e.message:'Could not create room.');}
    finally{if(mounted)setState(()=>creating=false);}
  }
  void openRoom(Map<String,dynamic> room){
    go(FirebaseRoomChat(api:api,room:room));
  }
  Widget title(String name)=>Padding(padding:const EdgeInsets.symmetric(vertical:14),
    child:Text(name,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)));
  Widget quick(IconData icon,String label,VoidCallback callback,Color color)=>
    Expanded(child:InkWell(onTap:callback,borderRadius:BorderRadius.circular(20),
      child:Padding(padding:const EdgeInsets.all(5),child:Column(children:[
        Jewel(icon,color:color,size:46),const SizedBox(height:8),
        Text(label,textAlign:TextAlign.center,
          style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600)),
      ]))));
  void feature(String name,String explanation){
    showDialog<void>(context:context,builder:(_)=>AlertDialog(
      title:Text(name),content:Text(explanation),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))]));
  }
  void notices()=>feature('Official notices',
    'The Firebase notice feed has not yet been connected. Old Supabase notices were not deleted.');
  void wallet()=>feature('Coins & Diamonds',
    'Wallet and recharge are not connected to this Firebase account yet. No fake balance is shown and no coins will be deducted.');
  void rankings()=>feature('Rankings',
    'Greedy game rankings will show only server-verified results after the live game wallet is enabled.');
  void events()=>feature('Events',
    'Admin-created community events need their verified Firebase API before going live.');
  Widget roomCard(Map<String,dynamic> room,int index){
    const tones=[violet,cyan,gold,pink];
    final color=tones[index%tones.length];
    // Country belongs to the ROOM OWNER's saved profile, not the viewer's
    // phone location. No GPS, device locale, or fabricated flag is used.
    final country=(room['country']??'').toString().toUpperCase();
    final countryFlag=soveraCountries.containsKey(country)?flag(country):'';
    final id=(room['id']??'').toString();
    final roomName=(room['name']??'Voice room').toString();
    final avatar=(room['avatar_url']??'').toString();
    final count=room['occupants'] as int? ?? 0;
    final isFollowed=followed.contains(id);
    return Material(color:Colors.transparent,borderRadius:BorderRadius.circular(24),
      clipBehavior:Clip.antiAlias,child:InkWell(onTap:()=>openRoom(room),
        child:Ink(decoration:BoxDecoration(
          gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
            colors:[color.withValues(alpha:.42),const Color(0xFF1A1534),const Color(0xFF121327)]),
          border:Border.all(color:color.withValues(alpha:.4)),
          borderRadius:BorderRadius.circular(24)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(child:Stack(fit:StackFit.expand,children:[
              if(avatar.startsWith('https://'))
                Image.network(avatar,fit:BoxFit.cover,errorBuilder:(_,__,___)=>
                  const Center(child:BrandLogo(size:80)))
              else const Center(child:BrandLogo(size:80)),
              Positioned(left:10,top:10,child:Container(
                padding:const EdgeInsets.symmetric(horizontal:9,vertical:6),
                decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(15)),
                child:const Text('VOICE ROOM',style:TextStyle(fontSize:10,color:Colors.white)))),
              Positioned(right:0,top:0,child:IconButton(
                tooltip:isFollowed?'Unmark room':'Mark favorite (this device)',
                onPressed:()=>setState(()=>
                  isFollowed?followed.remove(id):followed.add(id)),
                icon:Icon(isFollowed?Icons.favorite:Icons.favorite_border,
                  color:isFollowed?pink:Colors.white))),
              Positioned(right:9,bottom:8,child:Container(
                padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),
                decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(12)),
                child:Row(mainAxisSize:MainAxisSize.min,children:[
                  const Icon(Icons.people_alt_rounded,size:14),
                  const SizedBox(width:4),Text('$count'),
                ]))),
            ])),
            Container(width:double.infinity,padding:const EdgeInsets.all(12),
              color:Colors.black12,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('${countryFlag.isEmpty?'': '$countryFlag '}$roomName',
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:14,fontWeight:FontWeight.w700)),
                const SizedBox(height:6),
                Text('${room['owner_name']??'Room owner'} · ${room['seats']??9} seats',
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:11,color:Colors.white60)),
                const SizedBox(height:9),
                Row(children:[Text('Explore room',style:TextStyle(fontSize:11,color:color)),
                  const Spacer(),Icon(Icons.arrow_forward_rounded,size:16,color:color)]),
              ])),
          ]))));
  }
  Widget directory(){
    final visible=rooms.where((r){
      final name=(r['name']??'').toString().toLowerCase();
      return name.contains(query.toLowerCase()) &&
        (filter!='Following'||followed.contains((r['id']??'').toString()));
    }).toList();
    if(filter=='New')visible.sort((a,b)=>(b['created_at'] as num? ?? 0)
      .compareTo(a['created_at'] as num? ?? 0));
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Text('Community rooms',
        style:TextStyle(fontWeight:FontWeight.w800,fontSize:18))),
        IconButton(onPressed:loading?null:refresh,
          icon:const Icon(Icons.refresh_rounded),tooltip:'Refresh rooms'),
        FilledButton.icon(onPressed:creating?null:createRoom,
          icon:const Icon(Icons.add_home_rounded),label:const Text('My room'))]),
      if(loading)const LinearProgressIndicator(),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.orangeAccent)),
      const SizedBox(height:12),
      if(visible.isEmpty&&!loading)Glass(child:Text(rooms.isEmpty
        ?'No community rooms yet. Create your room.'
        :'No rooms matched your search.')),
      if(visible.isNotEmpty)LayoutBuilder(builder:(context,b)=>GridView.builder(
        shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
        itemCount:visible.length,
        gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:b.maxWidth<300?1:2,mainAxisExtent:235,
          crossAxisSpacing:12,mainAxisSpacing:12),
        itemBuilder:(context,index)=>roomCard(visible[index],index))),
    ]);
  }
  Widget home()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    TextField(controller:search,onChanged:(s)=>setState(()=>query=s),
      decoration:InputDecoration(hintText:'Search rooms',
        prefixIcon:const Icon(Icons.search_rounded),
        filled:true,fillColor:Colors.white10,
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(20),
          borderSide:BorderSide.none))),
    const SizedBox(height:16),
    SizedBox(height:195,child:PageView.builder(itemCount:slides.length,
      onPageChanged:(i)=>setState(()=>banner=i),
      itemBuilder:(context,index){
        final slide=slides[index];
        return Padding(padding:const EdgeInsets.only(right:4),
          child:InkWell(onTap:index==0?createRoom:index==1?rankings:events,
            child:Glass(tint:slide.$4,child:Row(children:[
              Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Text('SOVERA COMMUNITY',
                    style:TextStyle(fontSize:10,letterSpacing:1.7,color:Colors.white60)),
                  const SizedBox(height:10),
                  Text(slide.$1,style:const TextStyle(fontSize:22,
                    fontWeight:FontWeight.w800,height:1.15)),
                  const SizedBox(height:10),
                  Text(slide.$2,style:const TextStyle(fontSize:11,color:Colors.white70)),
                ])),
              const SizedBox(width:9),
              Column(mainAxisAlignment:MainAxisAlignment.center,children:[
                const BrandLogo(size:62),const SizedBox(height:12),
                Jewel(slide.$3,color:slide.$4,size:42),
              ]),
            ]))),
        );
      })),
    const SizedBox(height:10),
    Row(mainAxisAlignment:MainAxisAlignment.center,children:[
      for(var i=0;i<slides.length;i++)Container(
        margin:const EdgeInsets.symmetric(horizontal:3),height:6,width:i==banner?20:6,
        decoration:BoxDecoration(color:i==banner?pink:Colors.white38,
          borderRadius:BorderRadius.circular(4))),
    ]),
    const SizedBox(height:18),
    Row(children:[
      quick(Icons.emoji_events_rounded,'Rankings',rankings,gold),
      quick(Icons.celebration_rounded,'Events',events,pink),
      quick(Icons.add_home_rounded,'My room',createRoom,cyan),
      quick(Icons.sports_esports_rounded,'Games',
        ()=>go(FirebaseGreedyWheelPage(api:api)),violet),
    ]),
    const SizedBox(height:18),
    Row(children:[
      for(final name in ['All','Following','New'])
        Padding(padding:const EdgeInsets.only(right:8),
          child:ChoiceChip(label:Text(name),selected:filter==name,
            onSelected:(_)=>setState(()=>filter=name))),
    ]),
    const SizedBox(height:16),directory(),
  ]);
  Widget moments()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    title('Moments'),
    FilledButton.icon(onPressed:()async{
      final edit=TextEditingController();
      final note=await showDialog<String>(context:context,builder:(ctx)=>
        AlertDialog(title:const Text('Write a moment (local draft)'),
          content:TextField(controller:edit,maxLength:500,maxLines:5),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,edit.text.trim()),
              child:const Text('Save draft'))]));
      edit.dispose();
      if(note!=null&&note.isNotEmpty&&mounted)setState(()=>posts.insert(0,note));
    },icon:const Icon(Icons.edit_rounded),label:const Text('Write a moment')),
    const SizedBox(height:16),
    if(posts.isEmpty)const Glass(child:Text(
      'Moments design restored. Publishing to the Firebase feed is not yet connected; drafts stay on this device during this session.')),
    for(final p in posts)Padding(padding:const EdgeInsets.only(bottom:12),
      child:Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(displayName,style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:12),Text(p),
      ]))),
  ]);
  Widget messages()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    title('Messages'),
    for(final item in <(IconData,String,Color,VoidCallback)>[
      (Icons.support_agent_rounded,'Official support',cyan,
        ()=>feature('Customer service','A live Firebase support inbox is not connected yet.')),
      (Icons.campaign_rounded,'Official notices',gold,notices),
      (Icons.account_balance_wallet_rounded,'Recharge support',pink,wallet),
    ])Padding(padding:const EdgeInsets.only(bottom:12),child:InkWell(onTap:item.$4,
      child:Glass(tint:item.$3,child:Row(children:[
        Jewel(item.$1,color:item.$3,size:45),const SizedBox(width:14),
        Expanded(child:Text(item.$2,style:const TextStyle(fontWeight:FontWeight.w700))),
        const Icon(Icons.chevron_right_rounded),
      ])))),
    const SizedBox(height:14),
    title('Room chat'),
    OutlinedButton.icon(onPressed:()=>setState(()=>tab=0),
      icon:const Icon(Icons.meeting_room_outlined),
      label:const Text('Open a room to chat with members')),
    const Text('Private direct messages are not connected to Firebase yet.',
      style:TextStyle(color:Colors.white60,fontSize:12)),
  ]);
  Widget profileTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    title('My profile'),
    Glass(tint:gold,child:Row(children:[
      const Jewel(Icons.person_rounded,color:gold,size:52),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(displayName,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        Text(widget.user.email??'Account',
          style:const TextStyle(fontSize:12,color:Colors.white60)),
      ])),
    ])),
    const SizedBox(height:12),
    FilledButton.icon(
      onPressed:editProfile,
      icon:const Icon(Icons.edit_rounded),
      label:Text(hasProfile?'Edit Profile':'Complete Profile'),
    ),
    if(!hasProfile)Padding(padding:const EdgeInsets.only(top:10),
      child:Text('Complete your name and country before creating a live room.',
        style:TextStyle(color:Colors.orange.shade200))),
    const SizedBox(height:14),
    const SizedBox(height:16),
    for(final item in <(IconData,String,VoidCallback)>[
      (Icons.account_balance_wallet_rounded,'Wallet',wallet),
      (Icons.storefront_rounded,'Coin seller list',wallet),
      (Icons.card_giftcard_rounded,'Invite & referrals',
        ()=>feature('Referrals','Firebase referral awards are not connected yet.')),
      (Icons.people_outline_rounded,'People & following',
        ()=>feature('Members','Firebase member directory is not connected yet.')),
      (Icons.workspace_premium_rounded,'Frames & effects',
        ()=>go(const _SoveraFrameGallery())),
      (Icons.add_home_rounded,'My room',createRoom),
      (Icons.settings_outlined,'Settings',
        ()=>feature('Settings','Original design saved. Additional settings are being connected to Firebase.')),
    ])ListTile(leading:Icon(item.$1,color:gold),title:Text(item.$2),
      trailing:const Icon(Icons.chevron_right_rounded),onTap:item.$3),
    const SizedBox(height:12),
    TextButton.icon(onPressed:()async{
      await FirebaseAuth.instance.signOut();
      try{await GoogleSignIn.instance.signOut();}catch(_){}
    },icon:const Icon(Icons.logout),label:const Text('Sign out')),
  ]);
  @override Widget build(BuildContext context)=>Scaffold(
    body:Container(decoration:const BoxDecoration(gradient:LinearGradient(
      begin:Alignment.topLeft,end:Alignment.bottomRight,
      colors:[Color(0xFF442A79),Color(0xFF25356C),Color(0xFF101B3A)])),
      child:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:640),
        child:ListView(key:ValueKey(tab),
          padding:const EdgeInsets.all(18),children:[
          Row(children:[const BrandLogo(size:48),const SizedBox(width:10),
            const Expanded(child:Text('Sovera',
              style:TextStyle(fontSize:27,fontWeight:FontWeight.w800))),
            IconButton(onPressed:notices,icon:const Icon(Icons.notifications_none_rounded)),
            IconButton(onPressed:()=>setState(()=>tab=3),
              icon:const Icon(Icons.settings_outlined))]),
          const Padding(padding:EdgeInsets.symmetric(vertical:8),
            child:Text('SIGNED IN · LIVE COMMUNITY ROOMS',
              style:TextStyle(fontSize:10,color:Colors.white60,letterSpacing:1.7))),
          if(tab==0)home(),
          if(tab==1)moments(),
          if(tab==2)messages(),
          if(tab==3)profileTab(),
        ]))))),
    bottomNavigationBar:NavigationBar(
      backgroundColor:const Color(0xFF1B2448),
      selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
      destinations:const[
        NavigationDestination(icon:Icon(Icons.home_rounded),label:'Home'),
        NavigationDestination(icon:Icon(Icons.auto_awesome_rounded),label:'Moments'),
        NavigationDestination(icon:Icon(Icons.chat_bubble_outline_rounded),label:'Messages'),
        NavigationDestination(icon:Icon(Icons.person_outline_rounded),label:'Me'),
      ]),
  );
}

class _SoveraFrameGallery extends StatelessWidget{
  const _SoveraFrameGallery();
  static const samples=[
    'assets/effects/royal-horses.webp',
    'assets/effects/phoenix-queen-entry.webp',
    'assets/effects/ice-king-entry.webp',
    'assets/effects/violet-phoenix-still.webp',
    'assets/effects/vip7.webp',
    'assets/effects/top-host-medal.webp',
  ];
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Original frames & entry animations')),
    body:GridView.builder(padding:const EdgeInsets.all(16),
      itemCount:samples.length,
      gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12),
      itemBuilder:(_,i)=>Glass(child:Column(children:[
        Expanded(child:Image.asset(samples[i],fit:BoxFit.contain,
          errorBuilder:(_,__,___)=>const Icon(Icons.workspace_premium_rounded,size:46))),
        const Text('Preview · no purchase',style:TextStyle(fontSize:10)),
      ]))));
}
