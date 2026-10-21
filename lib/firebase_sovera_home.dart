import 'firebase_programs.dart';
import 'sovera_icons.dart';
import 'firebase_rewards.dart';
import 'firebase_members.dart';
import 'firebase_room_session.dart';
import 'firebase_messaging.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'firebase_profile.dart';
import 'app_preferences.dart';
import 'firebase_catalog.dart';
import 'firebase_original_profile_card.dart';
import 'firebase_original_coin_sellers.dart';
import 'firebase_server_wallet.dart';
import 'firebase_community.dart';
import 'sovera_room_card.dart';
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
  List<Map<String,dynamic>> publishedBanners=[];
  bool catalogLoaded=false;
  Map<String,dynamic>? profile;
  String? error;
  int tab=0,banner=0;
  bool loading=false,creating=false;
  String query='',filter='All';
  String? staffRole;
  bool followBusy=false;
  final followed=<String>{};
  final slides=const <(String,String,IconData,Color)>[
    ('Your voice. Your world.','Create a room and make it yours.',Icons.mic_rounded,violet),
    ('Sovera Hall of Fame','Greedy Wheel · One server round for everyone.',Icons.emoji_events_rounded,gold),
    ('Something worth celebrating','Voice rooms, gifts and community.',Icons.celebration_rounded,pink),
  ];
  @override void initState(){
    super.initState();
    refresh();
    resetRefreshTimer();
    SoveraPreferences.lowData.addListener(resetRefreshTimer);
  }
  void resetRefreshTimer(){refreshTimer?.cancel();refreshTimer=Timer.periodic(Duration(seconds:SoveraPreferences.lowData.value?60:30),(_)=>refresh(silent:true));}
  @override void dispose(){SoveraPreferences.lowData.removeListener(resetRefreshTimer);refreshTimer?.cancel();search.dispose();client.close();super.dispose();}
  void say(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  void go(Widget page)=>Navigator.of(context).push<void>(
    MaterialPageRoute(builder:(_)=>page));
  Future<void> refresh({bool silent=false})async{
    if(loading)return;
    if(!silent&&mounted)setState((){loading=true;error=null;});
    try{
      final data=await api.call('GET',suffix:'/rooms');
      final p=await api.load();
      // Older deployed servers may not yet have community endpoints.
      Set<String>? savedFollows;String? role;
      try{
        final following=await api.call('GET',suffix:'/community/follows');
        savedFollows=(following['items'] as List).map((r)=>(r as Map)['room'].toString()).toSet();
        role=(await api.call('GET',suffix:'/staff'))['role'] as String?;
      }catch(_){/* Room access remains available during server rollout. */}
      List<Map<String,dynamic>>? banners;
      try{final catalog=await api.call('GET',suffix:'/catalog');banners=(catalog['items'] as List).whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).where((r)=>r['kind']=='banner').toList();}catch(_){/* Keep existing artwork when rollout is unavailable. */}
      if(mounted)setState((){
        if(banners!=null){publishedBanners=banners;catalogLoaded=true;}
        rooms=(data['rooms'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
        profile=p;error=null;staffRole=role;
        if(savedFollows!=null){followed..clear()..addAll(savedFollows);}
      });
    }catch(e){if(mounted&&!silent)setState(()=>error=e is ProfileApiError?e.message:'Could not load rooms. Check connection.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  String get displayName => profile?['display_name'] as String? ??
      widget.user.displayName??'Sovera user';
  bool get hasProfile=>profile!=null;
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
    PersistentRoomLayer.open(context,api,room);
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
  void community(String section,String title)=>go(FirebaseCommunity(api:api,section:section,title:title));
  void notices()=>go(FirebaseMessageInbox(api:api,official:true));
  Future<void> toggleFollow(String id)async{
    if(followBusy)return;
    setState(()=>followBusy=true);
    final enable=!followed.contains(id);
    try{
      await api.call(enable?'PUT':'DELETE',suffix:'/community/follows/${Uri.encodeComponent(id)}');
      if(mounted)setState(()=>enable?followed.add(id):followed.remove(id));
    }catch(e){say(e is ProfileApiError?e.message:'Could not save room follow.');}
    finally{if(mounted)setState(()=>followBusy=false);}
  }
  void wallet()=>go(FirebaseServerWalletPage(api:api));
  void rankings()=>go(FirebaseRewardsPage(api:api));
  void events()=>go(FirebaseRewardsPage(api:api,initialTab:'event'));
  Widget roomCard(Map<String,dynamic> room,int index)=>SoveraRoomCard(room:room,onTap:()=>openRoom(room),followed:followed.contains(room['id']),onFollow:followBusy?null:()=>toggleFollow(room['id'].toString()));
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
    if(!catalogLoaded||publishedBanners.isNotEmpty)SizedBox(height:195,child:PageView.builder(itemCount:catalogLoaded?publishedBanners.length:slides.length,
      onPageChanged:(i)=>setState(()=>banner=i),
      itemBuilder:(context,index){
        final published=publishedBanners.isEmpty?null:publishedBanners[index];
        final builtIn=published?['builtin_slide'];
        if(published!=null&&builtIn is! int)return Padding(padding:const EdgeInsets.only(right:4),child:ClipRRect(borderRadius:BorderRadius.circular(22),child:CatalogImage(asset:publishedBanners[index],fit:BoxFit.cover)));
        final slide=slides[builtIn is int?builtIn.clamp(0,slides.length-1).toInt():index];
        return Padding(padding:const EdgeInsets.only(right:4),
          child:InkWell(onTap:(builtIn??index)==0?createRoom:(builtIn??index)==1?rankings:events,
            child:Glass(tint:slide.$4,child:Row(children:[
              Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Text('SOVERA COMMUNITY',
                    style:TextStyle(fontSize:10,letterSpacing:1.7,color:Colors.white60)),
                  const SizedBox(height:10),
                  Text((published?['title']??slide.$1).toString(),style:const TextStyle(fontSize:22,
                    fontWeight:FontWeight.w800,height:1.15)),
                  const SizedBox(height:10),
                  Text((published?['subtitle']??slide.$2).toString(),style:const TextStyle(fontSize:11,color:Colors.white70)),
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
      for(var i=0;i<(catalogLoaded?publishedBanners.length:slides.length);i++)Container(
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
  Widget moments()=>FirebaseCommunity(api:api,section:'moments',title:'Moments',embedded:true);
  Widget messages()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    title('Messages'),
    for(final item in <(IconData,String,Color,VoidCallback)>[
      (Icons.support_agent_rounded,'Official support',cyan,
        ()=>community('support','Official support')),
      (Icons.campaign_rounded,'Official notices',gold,notices),
      (Icons.account_balance_wallet_rounded,'Recharge support',pink,()=>community('support','Recharge support')),
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
    FilledButton.icon(onPressed:()=>go(FirebaseMessageInbox(api:api)),icon:const SoveraIcon(Icons.chat_rounded,size:28),label:const Text('Private messages')),
  ]);
  Widget profileTab()=>Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    title('My profile'),
    FirebaseOriginalProfileCard(profile:profile,name:displayName,onEdit:editProfile),
    if(!hasProfile)Padding(padding:const EdgeInsets.only(top:10),
      child:Text('Complete your name and country before creating a live room.',
        style:TextStyle(color:Colors.orange.shade200))),
    const SizedBox(height:18),
    MemberSocialCounts(profile:profile??{},onOpen:(section)=>go(FirebaseMembersPage(api:api,section:section))),
    const SizedBox(height:16),
    Row(children:[
      for(final item in <(IconData,String,Color,VoidCallback)>[
        (Icons.storefront_rounded,'Mall',cyan,()=>go(FirebaseCatalogPage(api:api))),
        (Icons.military_tech_rounded,'Medals',gold,()=>go(FirebaseCatalogPage(api:api,initialKind:'medal'))),
        (Icons.groups_rounded,'Agency',violet,()=>go(FirebaseAgenciesPage(api:api))),
        (Icons.event_available_rounded,'Task Center',pink,()=>go(FirebaseRewardsPage(api:api,initialTab:'event'))),
      ])Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:InkWell(onTap:item.$4,borderRadius:BorderRadius.circular(20),child:Container(padding:const EdgeInsets.symmetric(horizontal:4,vertical:12),decoration:BoxDecoration(gradient:LinearGradient(colors:[item.$3.withValues(alpha:.32),const Color(0xff20233e)]),borderRadius:BorderRadius.circular(20),border:Border.all(color:item.$3.withValues(alpha:.4)),boxShadow:const [BoxShadow(color:Colors.black38,offset:Offset(0,6),blurRadius:10)]),child:Column(children:[Jewel(item.$1,color:item.$3,size:39),const SizedBox(height:9),FittedBox(child:Text(item.$2,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:11)))]))))),
    ]),
    const SizedBox(height:18),
    for(final item in <(IconData,String,VoidCallback)>[
      (Icons.account_balance_wallet_rounded,'Wallet',wallet),
      (Icons.redeem_rounded,'Ranking & Event Rewards',rankings),
      (Icons.workspace_premium_rounded,'VIP & SVIP',()=>go(FirebaseProgramsPage(api:api))),
      (Icons.savings_rounded,'Recharge Rewards',()=>go(FirebaseRewardsPage(api:api,initialTab:'recharge'))),
      (Icons.storefront_rounded,'Coin seller list',
        ()=>go(FirebaseOriginalCoinSellers(api:api))),
      (Icons.card_giftcard_rounded,'Invite & referrals',
        ()=>go(FirebaseProgramsPage(api:api,initialSection:'referral'))),
      (Icons.people_outline_rounded,'People & following',
        ()=>go(FirebaseMembersPage(api:api))),
      (Icons.auto_awesome_rounded,'My frames & entries',
        ()=>go(FirebaseCatalogPage(api:api))),
      (Icons.workspace_premium_rounded,'Frames & effects',
        ()=>go(FirebaseCatalogPage(api:api))),
      (Icons.add_home_rounded,'My room',createRoom),
      if(staffRole!=null)(Icons.admin_panel_settings_outlined,'Community admin',
        ()=>go(FirebaseStaffPage(api:api,role:staffRole!))),
      (Icons.settings_outlined,'Settings',
        ()=>go(SoveraSettingsPage(support:()=>go(FirebaseCommunity(api:api,section:'support',title:'Official support')),blocked:()=>go(FirebaseCommunity(api:api,section:'blocks',title:'Blocked users'))))),
    ])ListTile(leading:SoveraIcon(item.$1,color:gold,size:30),title:Text(item.$2),
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
        NavigationDestination(icon:SoveraIcon(Icons.chat_bubble_outline_rounded,size:30),label:'Messages'),
        NavigationDestination(icon:Icon(Icons.person_outline_rounded),label:'Me'),
      ]),
  );
}

