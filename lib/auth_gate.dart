import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'main.dart' show Home, BrandLogo, cyan, minimizedRoom;
import 'supabase_config.dart';

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

Future<void> startGoogleSignIn() async {
  final response=await http.get(Uri.parse('$supabaseUrl/auth/v1/settings'),headers:{'apikey':supabasePublishableKey}).timeout(const Duration(seconds:15));
  if(response.statusCode!=200)throw const AuthException('Cannot reach the sign-in service. Please retry.');
  final settings=jsonDecode(response.body) as Map<String,dynamic>;
  if((settings['external'] as Map?)?['google']!=true){
    throw const AuthException('Google sign-in is not enabled in Supabase yet. The project owner must finish Google provider setup.');
  }
  final opened=await soveraClient.auth.signInWithOAuth(OAuthProvider.google,
    redirectTo:soveraRedirectUri,authScreenLaunchMode:LaunchMode.externalApplication,
    queryParams:{'prompt':'select_account'});
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
      if(state.event==AuthChangeEvent.signedOut||(state.event==AuthChangeEvent.signedIn&&profile?['id']!=state.session?.user.id))minimizedRoom.value=null;
      if(state.event==AuthChangeEvent.signedOut&&mounted){
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
      final row=await ensureSoveraProfile(result.user!);
      if(mounted&&ticket==revision)setState((){profile=row;loading=false;});
    }catch(e){if(mounted&&ticket==revision)setState((){error='Could not load your verified profile. Check your connection and retry.';loading=false;});}
  }
  @override void dispose(){revision++;subscription?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(error!=null)return Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const BrandLogo(size:100),const SizedBox(height:24),Text(error!,textAlign:TextAlign.center),const SizedBox(height:18),FilledButton(onPressed:refresh,child:const Text('Retry')),TextButton(onPressed:()async{try{await soveraClient.auth.signOut(scope:SignOutScope.local);}catch(_){if(mounted)setState(()=>error='Could not sign out. Please retry.');}},child:const Text('Back to sign-in'))])))));
    if(profile!=null)return Home(key:ValueKey(profile!['id']),profile:profile);
    return const GoogleLoginPage();
  }
}
class GoogleLoginPage extends StatefulWidget{
 const GoogleLoginPage({super.key});
 @override State<GoogleLoginPage> createState()=>_GoogleLoginPageState();
}
class _GoogleLoginPageState extends State<GoogleLoginPage>{
 bool busy=false;String? error;
 Future<void> signIn()async{
  setState((){busy=true;error=null;});
  try{await startGoogleSignIn();}
  on AuthException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(e){if(mounted)setState(()=>error='Unable to start sign-in. Check your connection and try again.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(body:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF882580),Color(0xFF43249A),Color(0xFF25116B)])),child:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Column(children:[const BrandLogo(size:180),const SizedBox(height:30),const Text('Welcome to Sovera',textAlign:TextAlign.center,style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),const SizedBox(height:12),const Text('Your voice. Your world.',style:TextStyle(color:Colors.white70,fontSize:17)),const SizedBox(height:36),SizedBox(width:double.infinity,height:54,child:FilledButton.icon(onPressed:busy?null:signIn,style:FilledButton.styleFrom(backgroundColor:Colors.white,foregroundColor:Colors.black),icon:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.login_rounded),label:Text(busy?'Opening sign-in…':'Continue with Google'))),if(error!=null)Padding(padding:const EdgeInsets.only(top:20),child:Text(error!,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFFFFD0D0)))),const SizedBox(height:18),TextButton.icon(onPressed:busy?null:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>const Home())),icon:const Icon(Icons.visibility_outlined),label:const Text('Explore design preview')),const SizedBox(height:24),const Text('Your Google account is used for sign-in. Your profile stays private to your account in this first version.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,fontSize:12,height:1.5)),const SizedBox(height:20),const Text('Voice rooms and wallet services are still in development.',textAlign:TextAlign.center,style:TextStyle(color:cyan,fontSize:11))])))))));
}

