import 'community_services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show Home, BrandLogo, cyan, minimizedRoom;
import 'supabase_config.dart';
import 'room_presence.dart';

SupabaseClient get soveraClient => Supabase.instance.client;

Future<Map<String,dynamic>> ensureSoveraProfile(User user) async {
  final db=soveraClient.from('sovera_profiles');
  final existing=await db.select().eq('id',user.id).maybeSingle();
  if(existing!=null)return existing;
  final metadata=user.userMetadata??{};
  var name=(metadata['full_name']??metadata['name']??'Sovera user').toString().trim();
  if(name.isEmpty)name='Sovera user';
  if(name.length>40)name=name.substring(0,40);
  final avatar=metadata['avatar_url']??metadata['picture'];
  final safeAvatar=avatar is String&&avatar.startsWith('https://')&&avatar.length<=2000?avatar:null;
  try {
    return await db.insert({'id':user.id,'display_name':name,'avatar_url':safeAvatar}).select().single();
  } on PostgrestException catch(error) {
    if(error.code!='23505')rethrow;
    // A second device may have provisioned the same profile concurrently.
    return await db.select().eq('id',user.id).single();
  }
}

Future<void> startSocialSignIn(OAuthProvider provider) async {
  final opened=await soveraClient.auth.signInWithOAuth(provider,
    redirectTo:soveraRedirectUri,authScreenLaunchMode:LaunchMode.externalApplication,
    scopes:provider==OAuthProvider.facebook?'email':null,
    queryParams:provider==OAuthProvider.google?{'prompt':'select_account'}:null);
  if(!opened)throw const AuthException('Could not open your browser. Please retry.');
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState()=>_AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? subscription;
  Map<String,dynamic>? profile;
  String? error;
  bool loading=true;
  int revision=0;
  @override void initState(){
    super.initState();
    subscription=soveraClient.auth.onAuthStateChange.listen((state){
      if(state.event==AuthChangeEvent.signedOut)unawaited(RoomPresence.instance.stop());
      if(state.event==AuthChangeEvent.signedOut||(state.event==AuthChangeEvent.signedIn&&profile?['id']!=state.session?.user.id))minimizedRoom.value=null;
      if((state.event==AuthChangeEvent.signedOut||(state.event==AuthChangeEvent.signedIn&&profile?['id']!=state.session?.user.id))&&mounted){
        Navigator.of(context).popUntil((route)=>route.isFirst);
      }
      // Token refresh must not unmount Home and discard unsaved edits.
      if(state.event==AuthChangeEvent.tokenRefreshed&&profile!=null&&state.session?.user.id==profile!['id'])return;
      // Keep database work outside the synchronous auth callback.
      unawaited(Future<void>.delayed(Duration.zero,refresh));
    },onError:(Object e){if(mounted)setState((){error='Your session could not be restored. Please retry.';loading=false;});});
    unawaited(refresh());
  }
  Future<void> refresh()async{
    final ticket=++revision;
    if(!mounted)return;
    if(soveraClient.auth.currentSession==null){setState((){profile=null;error=null;loading=false;});return;}
    setState((){loading=true;error=null;profile=null;});
    try{
      final result=await soveraClient.auth.getUser();
      if(result.user==null)throw const AuthException('Please sign in again.');
      try{final blocked=await soveraClient.rpc('sovera_account_status');if(blocked==true)throw const AuthException('Your account is suspended. Contact support.');}on PostgrestException catch(_){/* Older servers do not expose the status RPC. */}
      final row=await ensureSoveraProfile(result.user!);
      if(mounted&&ticket==revision)setState((){profile=row;loading=false;});
    }catch(e){if(mounted&&ticket==revision)setState((){error=e is AuthException&&e.message=='Your account is suspended. Contact support.'?e.message:'Could not load your verified profile. Check your connection and retry.';loading=false;});}
  }
  @override void dispose(){revision++;subscription?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(error!=null)return Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const BrandLogo(size:100),const SizedBox(height:24),Text(error!,textAlign:TextAlign.center),const SizedBox(height:18),FilledButton(onPressed:refresh,child:const Text('Retry')),TextButton(onPressed:()async{try{await soveraClient.auth.signOut(scope:SignOutScope.local);}catch(_){if(mounted)setState(()=>error='Could not sign out. Please retry.');}},child:const Text('Back to sign-in'))])))));
    if(profile!=null&&(profile!['country']??'').toString().trim().isEmpty)return ProfileSetupPage(profile:profile!,onSaved:refresh);
    if(profile!=null)return Home(key:ValueKey(profile!['id']),profile:profile);
    return const SoveraLoginPage();
  }
}
class SoveraLoginPage extends StatefulWidget{
 final Future<void> Function(OAuthProvider)? onSignIn;
 const SoveraLoginPage({super.key,this.onSignIn});
 @override State<SoveraLoginPage> createState()=>_SoveraLoginPageState();
}
class _SoveraLoginPageState extends State<SoveraLoginPage>{
 OAuthProvider? busyProvider;String? error;
 Future<void> signIn(OAuthProvider provider)async{
  if(busyProvider!=null)return;
  setState((){busyProvider=provider;error=null;});
  try{await (widget.onSignIn??startSocialSignIn)(provider);}
  on AuthException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Unable to start sign-in. Check your connection and try again.');}
  finally{if(mounted)setState(()=>busyProvider=null);}
 }
 Widget providerButton(OAuthProvider provider,String label,IconData icon,Color background,Color foreground)=>SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busyProvider!=null?null:()=>signIn(provider),style:FilledButton.styleFrom(backgroundColor:background,foregroundColor:foreground,padding:const EdgeInsets.symmetric(horizontal:16,vertical:16)),icon:busyProvider==provider?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):Icon(icon),label:Text(busyProvider==provider?'Opening $label…':'Continue with $label',textAlign:TextAlign.center)));
 @override Widget build(BuildContext context)=>Scaffold(body:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF882580),Color(0xFF43249A),Color(0xFF25116B)])),child:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Column(children:[const BrandLogo(size:150),const SizedBox(height:24),const Text('Welcome to Sovera',textAlign:TextAlign.center,style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),const SizedBox(height:12),const Text('Your voice. Your world.',style:TextStyle(color:Colors.white70,fontSize:17)),const SizedBox(height:30),providerButton(OAuthProvider.google,'Google',Icons.login_rounded,Colors.white,Colors.black),if(error!=null)Padding(padding:const EdgeInsets.only(top:20),child:Text(error!,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFFFFD0D0)))),const SizedBox(height:18),TextButton.icon(onPressed:busyProvider!=null?null:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const Home())),icon:const Icon(Icons.visibility_outlined),label:const Text('Explore design preview')),const SizedBox(height:24),const Text('Sign in with Google to save your profile and join voice rooms.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,fontSize:12,height:1.5)),const SizedBox(height:20),const Text('Choose your profile photo and country after sign-in.',textAlign:TextAlign.center,style:TextStyle(color:cyan,fontSize:11))])))))));
}

