import 'admin_control.dart';
import 'member_profile.dart';
import 'room_media.dart';
import 'referral.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'cloud_rooms.dart';
import 'room_card.dart';
import 'account_cards.dart';
import 'social_center.dart';
import 'effects_studio.dart';
import 'support_tickets.dart';
import 'wallet.dart';
import 'seat_link.dart';
import 'room_visuals.dart';
import 'member_directory.dart';
import 'supabase_config.dart';

Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 try {
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey, authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce));
  runApp(const Sovera());
 } catch (_) {
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Could not initialize sign-in. Please restart Sovera.')))));
 }
}
const violet = Color(0xFF9268F4);
const gold = Color(0xFFECC58A);
const pink = Color(0xFFFF69B4);
const ink = Color(0xFF12172D);
const cyan = Color(0xFF71E5E6);

class Sovera extends StatelessWidget {
  final bool preview;
  const Sovera({super.key, this.preview=false});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sovera', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: ink, colorScheme: const ColorScheme.dark(primary: violet, secondary: cyan),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    ), home: preview ? const Home() : const AuthGate(),
  );
}

class Glass extends StatelessWidget {
  final Widget child;
  final Color tint;
  final EdgeInsets padding;
  const Glass({super.key, required this.child, this.tint = violet, this.padding = const EdgeInsets.all(18)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .22), const Color(0xFF17223A), const Color(0xFF10172C)]),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
      boxShadow: [BoxShadow(color: tint.withValues(alpha: .12), blurRadius: 24, offset: const Offset(0, 12))],
    ), child: child,
  );
}

class Jewel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const Jewel(this.icon, {super.key, this.color = violet, this.size = 54});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * .32),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, .45)!, color, Color.lerp(color, Colors.black, .4)!]),
      border: Border.all(color: Colors.white.withValues(alpha: .32)),
      boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 16, offset: const Offset(0, 7))]),
    child: Icon(icon, color: Colors.white, size: size * .49),
  );
}

class Home extends StatefulWidget {
 final Map<String,dynamic>? profile;
 const Home({super.key, this.profile});
 @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> {
 int tab=0, banner=0; String filter='All',query='',displayName='Preview guest',bio='';
 final search=TextEditingController();
 final pageScroll=ScrollController(keepScrollOffset:false);
 final cloudRooms=GlobalKey<CloudRoomsState>();
 final rooms=<String,String>{'Moonlight Lounge':'Music','Ocean Avenue':'Adda','Golden Hour':'Friends','Sovera Studio':'Music'};
 final followed=<String>{};
 final posts=<String>[];
 final banners=< (String,String,IconData,Color)>[
 ('Your voice. Your world.','Create a room and make it yours.',Icons.mic_rounded,violet),
 ('The Sovera Hall of Fame','Explore ranking designs and room honors.',Icons.emoji_events_rounded,gold),
 ('Something worth celebrating','Explore upcoming community features.',Icons.celebration_rounded,pink),
 ];
 @override void initState(){super.initState();if(widget.profile!=null)filter='All';displayName=widget.profile?['display_name'] as String? ?? 'Preview guest';bio=widget.profile?['bio'] as String? ?? '';}
 @override void dispose(){search.dispose();pageScroll.dispose();super.dispose();}
 void selectTab(int value){setState((){tab=value;if(value==0)banner=0;});WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&pageScroll.hasClients)pageScroll.jumpTo(0);});}
 void go(Widget screen)=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>screen));
 void notice(String message)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
 Widget title(String text)=>Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(text,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)));
 Future<String?> ask(String name,{String initial='',int maxLength=100,bool allowEmpty=false})=>showDialog<String>(context:context,builder:(_)=>TextEntryDialog(title:name,initial:initial,maxLength:maxLength,allowEmpty:allowEmpty));
 Future<void> createRoom()async{if(widget.profile!=null){if(tab!=0){selectTab(0);await WidgetsBinding.instance.endOfFrame;}await cloudRooms.currentState?.myRoom();return;}final name=await ask('Name your preview room',maxLength:40);if(!mounted||name==null)return;setState(()=>rooms[name]='Your room');go(VoiceRoom(name:name));}
 Widget quick(IconData icon,String label,VoidCallback onTap,Color color)=>Expanded(child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(20),child:Padding(padding:const EdgeInsets.all(6),child:Column(children:[Jewel(icon,color:color,size:46),const SizedBox(height:9),Text(label,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600))]))));
 Future<void> editProfile() async {
 final name=await ask('Display name',initial:displayName,maxLength:40);
 if(!mounted||name==null)return;
 final about=await ask('Bio',initial:bio,maxLength:150,allowEmpty:true);
 if(!mounted||about==null)return;
 if(widget.profile!=null){
  try {
   final row=await soveraClient.from('sovera_profiles').update({'display_name':name,'bio':about}).eq('id',widget.profile!['id'] as String).select('display_name,bio').single();
   if(!mounted)return;
   setState((){displayName=row['display_name'] as String;bio=row['bio'] as String;});
   notice('Profile saved.');
  }catch(_){if(mounted)notice('Profile was not saved. Check your connection and retry.');}
 }else{setState((){displayName=name;bio=about;});}
 }
 Widget roomGrid(){
 if(widget.profile!=null)return CloudRooms(key:cloudRooms,query:query,filter:filter);
 final entries=rooms.entries.where((e)=>e.key.toLowerCase().contains(query.trim().toLowerCase())&&(filter!='Following'||followed.contains(e.key))).toList();
 if(filter=='New')entries.replaceRange(0,entries.length,entries.reversed.toList());
 if(entries.isEmpty)return const Padding(padding:EdgeInsets.all(32),child:Text('No rooms here yet.',textAlign:TextAlign.center));
 return LayoutBuilder(builder:(context,c){
 final columns=c.maxWidth<300?1:2;
 return GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:entries.length,gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:columns,mainAxisExtent:260+30*(MediaQuery.textScalerOf(context).scale(1)-1),crossAxisSpacing:12,mainAxisSpacing:14),itemBuilder:(context,index){
 final e=entries[index];
 return RoomCard(name:e.key,category:e.value,subtitle:'Design preview · Audio unavailable',color:[violet,cyan,gold,pink][index%4],followed:followed.contains(e.key),onOpen:()=>go(VoiceRoom(name:e.key)),onFollow:()=>setState(()=>followed.contains(e.key)?followed.remove(e.key):followed.add(e.key)));
 });
 });
 }
 @override Widget build(BuildContext context)=>Scaffold(
 body:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF442A79),Color(0xFF25356C),Color(0xFF101B3A)])),child:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:640),child:ListView(key:ValueKey(tab),controller:pageScroll,padding:const EdgeInsets.all(18),children:[
 Row(children:[const BrandLogo(size:48),const SizedBox(width:10),const Expanded(child:Text('Sovera',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:27,fontWeight:FontWeight.w800))),IconButton(tooltip:'Notifications',onPressed:()=>go(const Notices()),icon:const Icon(Icons.notifications_none_rounded)),IconButton(tooltip:'Settings',onPressed:()=>go(const AppSettings()),icon:const Icon(Icons.settings_outlined))]),
 Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(widget.profile==null?'DESIGN PREVIEW · NOT SIGNED IN':'SIGNED IN · ROOMS SAVED · VOICE COMING SOON',style:const TextStyle(fontSize:9,letterSpacing:1.8,color:Colors.white54))),
 if(widget.profile==null)Padding(padding:const EdgeInsets.only(bottom:12),child:OutlinedButton.icon(onPressed:()=>go(const SoveraLoginPage()),icon:const Icon(Icons.login_rounded),label:const Text('Sign in / Create account'))),
 ValueListenableBuilder<RoomDraft?>(valueListenable:minimizedRoom,builder:(context,draft,_)=>draft==null?const SizedBox.shrink():Padding(padding:const EdgeInsets.only(bottom:12),child:ListTile(tileColor:cyan.withValues(alpha:.12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),leading:const Icon(Icons.open_in_full_rounded,color:cyan),title:const Text('Return to room'),subtitle:Text(draft.name),trailing:const Icon(Icons.chevron_right_rounded),onTap:(){minimizedRoom.value=null;go(VoiceRoom(name:draft.name,roomId:draft.roomId,ownerId:draft.ownerId,initialSeats:draft.seats,draft:draft));}))),
 if(tab==0)...[
 const PublishedCommunityContent(kind:'banner'),
 TextField(controller:search,onChanged:(value)=>setState(()=>query=value),decoration:InputDecoration(hintText:'Search rooms',prefixIcon:const Icon(Icons.search_rounded),suffixIcon:query.isEmpty?null:IconButton(tooltip:'Clear room search',onPressed:(){search.clear();setState(()=>query='');},icon:const Icon(Icons.close_rounded)),filled:true,fillColor:Colors.white10,border:OutlineInputBorder(borderRadius:BorderRadius.circular(20),borderSide:BorderSide.none))),const SizedBox(height:18),
 SizedBox(height:280+80*(MediaQuery.textScalerOf(context).scale(1)-1),child:PageView.builder(itemCount:banners.length,onPageChanged:(value)=>setState(()=>banner=value),itemBuilder:(context,index){final b=banners[index];return Padding(padding:const EdgeInsets.only(right:4),child:InkWell(onTap:()=>index==0?createRoom():go(index==1?const Rankings():const Events()),child:Glass(tint:b.$4,child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[const Text('SOVERA COMMUNITY',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,letterSpacing:2,color:Colors.white60)),const SizedBox(height:10),Text(b.$1,maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800,height:1.1)),const SizedBox(height:10),Text(b.$2,maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:Colors.white60))])),const SizedBox(width:10),Column(mainAxisAlignment:MainAxisAlignment.center,children:[const BrandLogo(size:62),const SizedBox(height:12),Jewel(b.$3,color:b.$4,size:42)])]))));})),
 const SizedBox(height:10),Row(mainAxisAlignment:MainAxisAlignment.center,children:[for(int i=0;i<banners.length;i++)Container(width:banner==i?20:6,height:6,margin:const EdgeInsets.symmetric(horizontal:3),decoration:BoxDecoration(color:banner==i?pink:Colors.white30,borderRadius:BorderRadius.circular(4)))]),const SizedBox(height:14),
 Row(children:[quick(Icons.emoji_events_rounded,'Rankings',()=>go(const Rankings()),gold),quick(Icons.celebration_rounded,'Events',()=>go(const Events()),pink),quick(Icons.add_home_rounded,'My room',createRoom,cyan),quick(Icons.sports_esports_rounded,'Games',()=>go(const GamesHub()),violet)]),
 const SizedBox(height:14),Wrap(spacing:8,children:['All','Following','New'].map((name)=>ChoiceChip(label:Text(name),selected:filter==name,onSelected:(_)=>setState(()=>filter=name))).toList()),const SizedBox(height:14),roomGrid(),
 ],
 if(tab==1)...[title('Moments'),FilledButton.icon(onPressed:()async{final text=await ask('Write a local preview post',maxLength:500);if(mounted&&text!=null)setState(()=>posts.insert(0,text));},icon:const Icon(Icons.edit_rounded),label:const Text('Write a moment')),const SizedBox(height:18),if(posts.isEmpty)const Glass(child:Text('Your community stories will appear here. Preview posts stay in this session.')),for(final post in posts)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(displayName,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:10),Text(post)])))],
 if(tab==2)...[title('Messages'),for(final item in [(Icons.support_agent_rounded,'Official support',cyan),(Icons.campaign_rounded,'Official notices',gold),(Icons.account_balance_wallet_rounded,'Recharge support',pink)])Padding(padding:const EdgeInsets.only(bottom:12),child:InkWell(onTap:()=>go(item.$2=='Official notices'?const Notices():widget.profile!=null?SavedSupportPage(title:item.$2):SupportPage(title:item.$2)),child:Glass(tint:item.$3,child:Row(children:[Jewel(item.$1,color:item.$3,size:46),const SizedBox(width:14),Expanded(child:Text(item.$2,style:const TextStyle(fontWeight:FontWeight.bold))),const Icon(Icons.chevron_right_rounded)])))),const SizedBox(height:20),const Text('Chats',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),widget.profile==null?const Text('Sign in to read private conversations.',style:TextStyle(color:Colors.white54)):FilledButton.icon(onPressed:()=>go(DirectInboxPage(viewerId:widget.profile!['id'] as String)),icon:const Icon(Icons.forum_rounded),label:const Text('Open private chats'))],
 if(tab==3)...[title('My profile'),if(widget.profile!=null)AdminControlEntry(userId:widget.profile!['id'] as String),ProfileIdentityCard(profile:widget.profile,name:displayName,bio:bio,onEdit:editProfile),const SizedBox(height:22),const SocialProfileCards(),const SizedBox(height:22),
 InkWell(onTap:()=>go(ResellerCenter(profile:widget.profile)),borderRadius:BorderRadius.circular(26),child:Glass(tint:gold,child:Row(children:[const Jewel(Icons.storefront_rounded,color:gold,size:48),const SizedBox(width:14),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Reseller center',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),SizedBox(height:5),Text('Access, coin quota and applications',style:TextStyle(fontSize:11,color:Colors.white60))])),const Icon(Icons.chevron_right_rounded,color:gold)]))),
 const SizedBox(height:16),for(final item in [(Icons.account_balance_wallet_rounded,'Wallet'),(Icons.storefront_rounded,'Coin seller list'),(Icons.card_giftcard_rounded,'Invite & referrals'),(Icons.people_outline_rounded,'People & following'),(Icons.workspace_premium_rounded,'Frames & effects'),(Icons.add_home_rounded,'My room'),(Icons.settings_outlined,'Settings')])ListTile(leading:Icon(item.$1,color:gold),title:Text(item.$2),trailing:const Icon(Icons.chevron_right_rounded),onTap:(){switch(item.$2){case 'Invite & referrals':go(ReferralPage(profile:widget.profile));break;case 'Wallet':go(WalletPage(profile:widget.profile));break;case 'Coin seller list':go(CoinSellerList(profile:widget.profile));break;case 'People & following':go(MemberDirectory(profile:widget.profile==null?null:{...widget.profile!,'display_name':displayName,'bio':bio}));break;case 'Frames & effects':go(const EffectsStudio());break;case 'Settings':go(const AppSettings());break;case 'My room':createRoom();break;default:break;}}),Text(widget.profile==null?'Profile edits are local and reset when the app restarts.':'Profile edits are saved to your Supabase account.',style:const TextStyle(fontSize:11,color:Colors.white54)),if(widget.profile!=null) TextButton.icon(onPressed:() async { try { await soveraClient.auth.signOut(scope:SignOutScope.local); } catch(_) {notice('Could not sign out. Please retry.');} },icon:const Icon(Icons.logout_rounded),label:const Text('Sign out'))],
 ]))))),
 bottomNavigationBar:NavigationBar(backgroundColor:const Color(0xFF1B2448),selectedIndex:tab,onDestinationSelected:selectTab,destinations:const[NavigationDestination(icon:Icon(Icons.home_rounded),label:'Home'),NavigationDestination(icon:Icon(Icons.auto_awesome_rounded),label:'Moments'),NavigationDestination(icon:Icon(Icons.chat_bubble_outline_rounded),label:'Messages'),NavigationDestination(icon:Icon(Icons.person_outline_rounded),label:'Me')]),
 );
}
class TextEntryDialog extends StatefulWidget {
 final String title,initial,saveLabel;final int maxLength;final bool allowEmpty;
 const TextEntryDialog({super.key,required this.title,this.initial='',this.maxLength=100,this.allowEmpty=false,this.saveLabel='Save'});
 @override State<TextEntryDialog> createState()=>_TextEntryDialogState();
}
class _TextEntryDialogState extends State<TextEntryDialog>{
 late final TextEditingController input=TextEditingController(text:widget.initial);
 @override void dispose(){input.dispose();super.dispose();}
 void save(){final value=input.text.trim();if(widget.allowEmpty||value.isNotEmpty)Navigator.pop(context,value);}
 @override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.title),content:TextField(controller:input,maxLength:widget.maxLength,autofocus:true,textInputAction:TextInputAction.done,onSubmitted:(_)=>save()),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:save,child:Text(widget.saveLabel))]);
}
class FeaturePage extends StatelessWidget{
 final String title,description;final IconData icon;
 const FeaturePage({super.key,required this.title,required this.description,required this.icon});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(title)),body:ListView(padding:const EdgeInsets.all(24),children:[const Center(child:BrandLogo(size:76)),const SizedBox(height:30),Glass(child:Column(children:[Jewel(icon,color:gold,size:66),const SizedBox(height:22),Text(title,style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:14),Text(description,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white60,height:1.6))]))]));
}
class GamesHub extends StatelessWidget{
 const GamesHub({super.key});
 @override Widget build(BuildContext context)=>const FeaturePage(title:'Games',icon:Icons.sports_esports_rounded,description:'Your game collection will appear here.\n\nGames will be added later. No games, bets or coin deductions are enabled in this version.');
}
class Events extends StatelessWidget{
 const Events({super.key});
 @override Widget build(BuildContext context)=>DefaultTabController(length:3,child:Scaffold(appBar:AppBar(title:const Text('Events'),bottom:const TabBar(isScrollable:true,tabs:[Tab(text:'Active'),Tab(text:'Upcoming'),Tab(text:'Winners')])),body:TabBarView(children:[for(final text in ['No active events. Event banners, rules, rewards and live scores will appear here.','Scheduled events will appear here when published by an admin.','Verified winners will appear here after an event is settled.'])SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(children:[const BrandLogo(size:86),const SizedBox(height:26),Glass(tint:gold,child:Text(text)),const SizedBox(height:16),const Text('Event previews · Publishing coming soon',style:TextStyle(color:Colors.white54))]))])));
}
class Notices extends StatelessWidget{
 const Notices({super.key});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Official notices')),body:const SingleChildScrollView(padding:EdgeInsets.all(20),child:PublishedCommunityContent(kind:'notice')));
}

class SupportPage extends StatefulWidget{
 final String title;const SupportPage({super.key,required this.title});
 @override State<SupportPage> createState()=>_SupportPageState();
}
class _SupportPageState extends State<SupportPage>{
 final text=TextEditingController();String? draft;
 @override void dispose(){text.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.title)),body:ListView(padding:const EdgeInsets.all(22),children:[const BrandLogo(size:70),const SizedBox(height:20),const Text('Describe your issue. Support delivery is not connected yet.',style:TextStyle(color:Colors.white60)),const SizedBox(height:18),TextField(controller:text,maxLines:5,maxLength:1000,decoration:const InputDecoration(labelText:'Support message',border:OutlineInputBorder())),FilledButton(onPressed:(){if(text.text.trim().isEmpty)return;setState(()=>draft=text.text.trim());},child:const Text('Save local draft')),if(draft!=null)Padding(padding:const EdgeInsets.only(top:20),child:Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('LOCAL DRAFT · NOT SENT',style:TextStyle(color:gold,fontSize:11)),const SizedBox(height:10),Text(draft!)])))]));
}
class AppSettings extends StatelessWidget{
 const AppSettings({super.key});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Settings')),body:ListView(padding:const EdgeInsets.all(16),children:[const Center(child:BrandLogo(size:76)),const SizedBox(height:20),for(final item in [(Icons.language_rounded,'Language','This preview currently supports English. Full Bangla translation and saved language selection are pending.'),(Icons.mic_rounded,'Audio settings','Microphone permission, voice quality and audio routing will be available when the RTC engine is connected.'),(Icons.block_rounded,'Blocked users','User blocking is not connected yet.'),(Icons.shield_outlined,'Privacy','Facebook and Google sign-in use Supabase. Profile edits, room settings, room follows and submitted support tickets are saved to your account. Voice and payments are not connected. Local room chat and moment drafts reset after restart. A production privacy policy is still required.'),(Icons.description_outlined,'Terms','This is an early-access build with account storage and visual previews. Purchases, cash rewards and live voice are not enabled. Production terms have not been published.'),(Icons.delete_outline_rounded,'Delete account','Account deletion is not available in this build. An authenticated deletion flow is still required.')])ListTile(leading:Icon(item.$1,color:gold),title:Text(item.$2),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FeaturePage(title:item.$2,description:item.$3,icon:item.$1)))),const ListTile(leading:Icon(Icons.info_outline_rounded),title:Text('Sovera 0.15.0 · Early access'),subtitle:Text('Account and room storage connected · voice pending'))]));
}

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 56});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sovera logo',
    image: true,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: cyan.withValues(alpha: .12), blurRadius: size*.38),
          BoxShadow(color: violet.withValues(alpha: .10), blurRadius: size*.55),
        ],
      ),
      child: Image.asset('assets/sovera-logo-transparent.png',
        width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.high),
    ),
  );
}
class RoyalAvatar extends StatelessWidget {
 final double size; final String label; final bool active;
 const RoyalAvatar({super.key, this.size = 66, this.label = '', this.active = false});
 @override
 Widget build(BuildContext context) => FramePreviewAdapter(size:size+28,enabled:active,child:SizedBox(width: size+24, height: size+28, child: Stack(alignment: Alignment.center, children: [
 Positioned(left: 0, child: Transform.rotate(angle: -.4, child: Icon(Icons.eco_rounded, color: gold, size: size*.55))),
 Positioned(right: 0, child: Transform.flip(flipX: true, child: Transform.rotate(angle: -.4, child: Icon(Icons.eco_rounded, color: gold, size: size*.55)))),
 Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [gold, Color(0xFF8F542A), Color(0xFFFFE7BA)]), boxShadow: [BoxShadow(color: gold.withValues(alpha: .25), blurRadius: 14)]), padding: const EdgeInsets.all(3), child: CircleAvatar(backgroundColor: const Color(0xFF15131B), child: active ? const BrandLogo(size: 42) : Icon(Icons.chair_alt_rounded, color: gold, size: size*.4))),
 Positioned(top: 0, child: Icon(Icons.workspace_premium_rounded, color: gold, size: size*.38)),
 Positioned(bottom: 0, child: Icon(Icons.diamond_rounded, color: gold, size: size*.24)),
 ])));
}
class Rankings extends StatefulWidget {
 const Rankings({super.key});
 @override
 State<Rankings> createState() => _RankingsState();
}
class _RankingsState extends State<Rankings> {
 String period='Weekly';
 @override
 Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Rankings'), backgroundColor: Colors.transparent), backgroundColor: const Color(0xFF101027), body: ListView(padding: const EdgeInsets.all(22), children: [
 const Center(child: BrandLogo(size: 74)), const SizedBox(height: 22),
 Wrap(alignment: WrapAlignment.center, spacing: 8, children: ['Daily','Weekly','Monthly'].map((p) => ChoiceChip(label: Text(p), selected: period==p, onSelected: (_) => setState(() => period=p))).toList()),
 const SizedBox(height: 28), const Text('The Sovera Hall of Fame', textAlign: TextAlign.center, style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: gold)),
 const SizedBox(height: 24), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: [for (final rank in [2,1,3]) Expanded(child: Column(children: [FittedBox(fit:BoxFit.scaleDown,child:RoyalAvatar(size: rank==1?82:62)), const SizedBox(height: 8), Text('TOP $rank', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('Unclaimed', style: TextStyle(color: Colors.white54, fontSize: 12)), SizedBox(height: rank==1?32:8)]))]),
 const Divider(color: gold), const SizedBox(height: 20),
 for(final name in ['Recharge honors','Gifts sent','Charm','Room gifts','Room tier']) Padding(padding: const EdgeInsets.only(bottom: 12), child: Glass(tint: gold, child: Row(children: [const Jewel(Icons.emoji_events_rounded, color: gold), const SizedBox(width: 16), Expanded(child: Text(name)), const Text('—', style: TextStyle(color: gold))]))),
 Text('$period preview · Real rankings need server event totals.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
 ]));
}
class RoomDraft{
 final String name;final String? roomId,ownerId;final int seats;final int? mySeat,partnerSeat;final SeatBond bond;final bool muted;final List<String> messages;
 const RoomDraft({required this.name,this.roomId,this.ownerId,required this.seats,this.mySeat,this.partnerSeat,required this.bond,required this.muted,required this.messages});
}
final minimizedRoom=ValueNotifier<RoomDraft?>(null);
class VoiceRoom extends StatefulWidget {
 final String name;
 final String? roomId,ownerId;
 final int initialSeats;final RoomDraft? draft;
 const VoiceRoom({super.key, required this.name,this.roomId,this.ownerId,this.initialSeats=9,this.draft});
 @override
 State<VoiceRoom> createState() => _VoiceRoomState();
}
class _VoiceRoomState extends State<VoiceRoom> {
 int seats=9;bool micMuted=true; int? partnerSeat; SeatBond bond=SeatBond.friendship; bool savingSeats=false; int? mySeat; String? selectedGift;
 final messages=<String>[]; final input=TextEditingController();
 @override void initState(){super.initState();seats=widget.draft?.seats??widget.initialSeats;mySeat=widget.draft?.mySeat;partnerSeat=widget.draft?.partnerSeat;bond=widget.draft?.bond??SeatBond.friendship;micMuted=widget.draft?.muted??true;messages.addAll(widget.draft?.messages??[]);
  WidgetsBinding.instance.addPostFrameCallback((_){
   final entry=previewEntryEffect.value;
   if(mounted&&entry!=null&&ModalRoute.of(context)?.isCurrent==true)showEntryPreview(context,entry);
  });
 }
 bool get canEdit=>widget.roomId==null||soveraClient.auth.currentUser?.id==widget.ownerId;
 void notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
 @override
 void dispose(){input.dispose();super.dispose();}
 @override
 Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFF0C0D0F),
 appBar:AppBar(backgroundColor:const Color(0xFF10182A),automaticallyImplyLeading:false,leadingWidth:44,leading:RoomTool(label:'Back',icon:Icons.arrow_back_ios_new_rounded,color:violet,onTap:()=>Navigator.maybePop(context)),titleSpacing:0,title:Row(children:[RoomPhoto(roomId:widget.roomId,canEdit:canEdit,size:32),const SizedBox(width:6),Expanded(child:Text(widget.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:14,fontWeight:FontWeight.bold)))]),actions:[
 RoomTool(label:'Minimize room',icon:Icons.unfold_less_rounded,color:cyan,onTap:minimize),
 RoomTool(label:'Frames & effects',icon:Icons.auto_awesome_rounded,color:violet,onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const EffectsStudio()))),
 RoomTool(label:'Seat settings',icon:Icons.tune_rounded,color:gold,onTap:canEdit&&!savingSeats?settings:null),
 RoomTool(label:'Leave room',icon:Icons.logout_rounded,color:pink,onTap:(){minimizedRoom.value=null;if(Navigator.canPop(context)){Navigator.pop(context);}else{Navigator.pushReplacement(context,MaterialPageRoute<void>(builder:(_)=>const Home()));}}),
 ]),
 body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth:640),child: Column(children:[
 Expanded(child: ListView(padding:const EdgeInsets.symmetric(horizontal:18,vertical:12),children:[
 Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[ActionChip(avatar:const Icon(Icons.emoji_events_rounded,color:gold,size:18),label:const Text('Room honors'),onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const Rankings()))),Text(widget.roomId==null?'OFFLINE PREVIEW':'ROOM SAVED · NO AUDIO',maxLines:2,style:const TextStyle(color:Colors.white38,fontSize:10))]),
 const SizedBox(height:6),
 Align(alignment:Alignment.center,child:TextButton.icon(onPressed:connections,icon:const Icon(Icons.handshake_rounded,color:cyan),label:const Text('Friendship & CP preview'))),
 LayoutBuilder(builder:(context,constraints){
 final seatSize=(constraints.maxWidth/roomSeatColumns-24).clamp(36.0,64.0);
 final height=seatSize+62+25*(MediaQuery.textScalerOf(context).scale(1)-1);
 final linked=mySeat!=null&&partnerSeat!=null&&adjacentSeats(mySeat!,partnerSeat!,seats);
 return Stack(children:[
 GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:seats,gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:roomSeatColumns,mainAxisExtent:height),itemBuilder:(context,index)=>Semantics(label:'Seat ${index+1}',button:true,child:InkWell(onTap:(){if(mySeat==index&&widget.roomId!=null){profile(index);return;}setState((){mySeat=mySeat==index?null:index;if(mySeat==null||mySeat==partnerSeat)partnerSeat=null;});},onLongPress:()=>profile(index),borderRadius:BorderRadius.circular(24),child:Column(children:[RoomSeatAvatar(size:seatSize,occupied:mySeat==index||partnerSeat==index,muted:mySeat==index&&micMuted),Text(mySeat==index?'You':partnerSeat==index?'Partner preview':'${index+1}',maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white60,fontSize:11))])))),
 if(linked)Positioned(left:constraints.maxWidth*((mySeat!%roomSeatColumns+partnerSeat!%roomSeatColumns+1)/(roomSeatColumns*2))-18,top:(mySeat!~/roomSeatColumns)*height+seatSize/2,child:SeatLinkMarker(bond:bond)),
 ]);
 }),
 if(partnerSeat!=null)const Text('Local relationship preview · No real request or gift sent',textAlign:TextAlign.center,style:TextStyle(color:Colors.white54,fontSize:10)),
 if(mySeat!=null)Text(micMuted?'Mic indicator: muted · Live audio unavailable':'Mic indicator: unmuted preview · Live audio unavailable',textAlign:TextAlign.center,style:TextStyle(color:micMuted?pink:cyan,fontSize:10)),
 const SizedBox(height:16),const Text('Local chat preview',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
 const SizedBox(height:12),const Text('Welcome to Sovera. Take a seat and explore the room design.',style:TextStyle(color:Colors.white54,fontSize:12)),const SizedBox(height:12),
 for(final m in messages)Padding(padding:const EdgeInsets.only(bottom:8),child:Glass(tint:gold,padding:const EdgeInsets.all(12),child:Text('You: $m'))),
 ])),
 Padding(padding:const EdgeInsets.fromLTRB(10,6,10,14),child:Row(children:[IconButton(tooltip:micMuted?'Unmute preview':'Mute preview',onPressed:toggleMic,icon:Icon(micMuted?Icons.mic_off_rounded:Icons.mic_rounded,color:micMuted?pink:cyan)),Expanded(child:TextField(controller:input,maxLength:300,decoration:const InputDecoration(hintText:'Local message…',counterText:'',border:InputBorder.none),onSubmitted:(_)=>send())),IconButton(tooltip:'Send local message',onPressed:send,icon:const Icon(Icons.send_rounded,color:gold)),IconButton.filled(tooltip:'Preview gifts',onPressed:gifts,style:IconButton.styleFrom(backgroundColor:const Color(0xFFB6642B)),icon:const Icon(Icons.card_giftcard_rounded)),IconButton(tooltip:'Games',onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const GamesHub())),icon:const Icon(Icons.grid_view_rounded,color:gold))])),
 ])))),
 );
 void toggleMic(){if(mySeat==null){notice('Take a seat first to preview your microphone indicator.');return;}setState(()=>micMuted=!micMuted);}
 void minimize(){
 if(!Navigator.canPop(context)){notice('Open a room from Home to minimize it.');return;}
 minimizedRoom.value=RoomDraft(name:widget.name,roomId:widget.roomId,ownerId:widget.ownerId,seats:seats,mySeat:mySeat,partnerSeat:partnerSeat,bond:bond,muted:micMuted,messages:List.unmodifiable(messages));Navigator.pop(context);
 }
 Future<void> connections()async{
 int own=mySeat??0;SeatBond draft=bond;
 if(!List.generate(seats,(i)=>i).any((i)=>adjacentSeats(own,i,seats)))own=0;
 int peer=partnerSeat??(own%roomSeatColumns==roomSeatColumns-1?own-1:own+1);
 if(!adjacentSeats(own,peer,seats))peer=List.generate(seats,(i)=>i).firstWhere((i)=>adjacentSeats(own,i,seats));
 final applied=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,showDragHandle:true,builder:(sheet)=>StatefulBuilder(builder:(sheet,update)=>SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
 const Text('Friendship & CP',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:12),const Text('Try two neighbouring seats. This is a local visual preview; real links require both users to accept a relationship.',style:TextStyle(color:Colors.white60,height:1.5)),const SizedBox(height:18),
 DropdownButtonFormField<int>(initialValue:own,decoration:const InputDecoration(labelText:'Your preview seat'),items:[for(int i=0;i<seats;i++)DropdownMenuItem(value:i,enabled:List.generate(seats,(j)=>j).any((j)=>adjacentSeats(i,j,seats)),child:Text('Seat ${i+1}'))],onChanged:(value){if(value==null)return;update((){own=value;peer=own%roomSeatColumns==roomSeatColumns-1?own-1:own+1;if(peer>=seats)peer=own-1;});}),
 const SizedBox(height:12),DropdownButtonFormField<int>(key:ValueKey(own),initialValue:peer,decoration:const InputDecoration(labelText:'Partner preview seat'),items:[for(int i=0;i<seats;i++)if(adjacentSeats(own,i,seats))DropdownMenuItem(value:i,child:Text('Seat ${i+1}'))],onChanged:(value){if(value!=null)update(()=>peer=value);}),
 const SizedBox(height:18),Wrap(spacing:8,children:[ChoiceChip(label:const Text('Friendship'),avatar:const Icon(Icons.handshake_rounded,size:18),selected:draft==SeatBond.friendship,onSelected:(_)=>update(()=>draft=SeatBond.friendship)),ChoiceChip(label:const Text('CP Love'),avatar:const Icon(Icons.favorite_rounded,size:18),selected:draft==SeatBond.cp,onSelected:(_)=>update(()=>draft=SeatBond.cp))]),
 const SizedBox(height:18),FilledButton(onPressed:()=>Navigator.pop(sheet,true),child:const Text('Apply seat preview')),
 TextButton(onPressed:()=>Navigator.pop(sheet,false),child:const Text('Clear seat link')),
 ])))));
 if(!mounted||applied==null)return;
 setState((){if(applied){mySeat=own;partnerSeat=peer;bond=draft;}else{partnerSeat=null;}});
 }
 void send(){if(input.text.trim().isEmpty)return;setState((){messages.add(input.text.trim());input.clear();});}
 Future<void> settings()async{
 if(!canEdit||savingSeats)return;
 int draft=seats;
 final value=await showModalBottomSheet<int>(context:context,isScrollControlled:true,showDragHandle:true,builder:(context)=>StatefulBuilder(builder:(context,update)=>SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Room seats',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:20),Wrap(spacing:8,children:[5,6,9,12].map((n)=>ChoiceChip(label:Text('$n seats'),selected:draft==n,onSelected:(_)=>update(()=>draft=n))).toList()),const SizedBox(height:20),FilledButton(onPressed:()=>Navigator.pop(context,draft),child:const Text('Save seat layout'))])))));
 if(!mounted||value==null)return;
 if(widget.roomId!=null){
  setState(()=>savingSeats=true);
  try{
   final saved=await soveraClient.from('sovera_rooms').update({'seat_count':value}).eq('id',widget.roomId!).select('seat_count').single();
   if(!mounted)return;
   setState((){seats=saved['seat_count'] as int;if(mySeat!=null&&mySeat!>=seats)mySeat=null;if(partnerSeat!=null&&partnerSeat!>=seats)partnerSeat=null;});
   notice('Seat layout saved to your room.');
  }catch(_){if(mounted)notice('Seat layout was not saved. Please retry.');}
  finally{if(mounted)setState(()=>savingSeats=false);}
 }else{setState((){seats=value;if(mySeat!=null&&mySeat!>=seats)mySeat=null;if(partnerSeat!=null&&partnerSeat!>=seats)partnerSeat=null;});notice('Seat layout saved for this preview session.');}
 }
 Future<void> profile(int index)async{
 if(mySeat==index&&widget.roomId!=null){final user=soveraClient.auth.currentUser;if(user!=null){await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>MemberProfilePage(targetId:user.id,viewerId:user.id)));return;}}
 await showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,backgroundColor:const Color(0xFF1B191C),builder:(context)=>SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[RoyalAvatar(size:96,active:mySeat==index),Text(mySeat==index?'You':'Empty seat ${index+1}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:12),Text(mySeat==index?'Your seat preview · audio is not connected':'This seat is empty. Tap it to preview sitting here.',style:const TextStyle(color:Colors.white54)),const SizedBox(height:22),const SizedBox.shrink(),const SizedBox(height:20),if(mySeat==index)FilledButton(onPressed:(){Navigator.pop(context);gifts();},child:const Text('Open gift collection'))]))));
 }
 void previewGift(BuildContext sheet){
 if(selectedGift==null)return;
 showDialog<void>(context:sheet,builder:(_)=>GiftAnimationCard(name:selectedGift!));
 }
 void gifts()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,backgroundColor:const Color(0xFF111113),builder:(context)=>StatefulBuilder(builder:(context,update)=>SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.72,child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFFA323),Color(0xFFED541F)]),borderRadius:BorderRadius.circular(18)),child:const Row(children:[Icon(Icons.card_giftcard_rounded),SizedBox(width:10),Expanded(child:Text('Sovera Gift Collection',maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:FontWeight.bold))),SizedBox(width:8),BrandLogo(size:32)])),
 const SizedBox(height:14),const Text('Preview only · no coins will be spent',style:TextStyle(color:Colors.white54,fontSize:12)),const SizedBox(height:14),
 const SizedBox(height:16),Expanded(child:GridView.count(crossAxisCount:MediaQuery.sizeOf(context).width<360||MediaQuery.textScalerOf(context).scale(1)>1.3?2:3,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:MediaQuery.textScalerOf(context).scale(1)>1.3 ? 0.65 : 0.85,children:[for(final item in [(Icons.favorite_rounded,'Heart',pink),(Icons.diamond_rounded,'Diamond',cyan),(Icons.castle_rounded,'Castle',gold),(Icons.local_florist_rounded,'Rose',pink),(Icons.directions_car_rounded,'Royal car',gold),(Icons.auto_awesome_rounded,'Starlight',violet),(Icons.handshake_rounded,'Holding hands',cyan),(Icons.favorite_rounded,'CP Heart',pink)])InkWell(onTap:()=>update(()=>selectedGift=item.$2),child:Container(decoration:BoxDecoration(color:selectedGift==item.$2?gold.withValues(alpha:.18):Colors.white.withValues(alpha:.03),border:Border.all(color:selectedGift==item.$2?gold:Colors.white12),borderRadius:BorderRadius.circular(16)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Jewel(item.$1,color:item.$3,size:48),const SizedBox(height:10),Text(item.$2,style:const TextStyle(fontSize:11)),const Text('Preview',style:TextStyle(fontSize:10,color:gold))])))])),
 const SizedBox(height:12),Wrap(spacing:12,runSpacing:8,alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,children:[const Text('Coins · —',style:TextStyle(color:gold)),FilledButton(onPressed:selectedGift==null?null:()=>previewGift(context),style:FilledButton.styleFrom(backgroundColor:const Color(0xFFF07D2A)),child:const Text('View selection'))]),
 ]))))));
}
