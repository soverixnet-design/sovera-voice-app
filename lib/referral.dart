import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_gate.dart';
import 'main.dart' show Glass, Jewel, cyan, gold;

const referralDownloadUrl = 'https://github.com/soverixnet-design/sovera-voice-app/releases/latest/download/Sovera.apk';
String? parseReferralCode(String input) => RegExp(r'\bSV[A-F0-9]{12}\b').firstMatch(input.toUpperCase())?.group(0);
String referralInvitation(String code) => 'Join me on Sovera! My invitation code: $code\nDownload: $referralDownloadUrl?ref=$code\nAfter installing, sign in and enter my code in Me → Invite & referrals.';
class ReferralSnapshot {
 final String code; final int count; final List<String> dates; final String? claimedCode;
 const ReferralSnapshot({required this.code,required this.count,this.dates=const [],this.claimedCode});
}
abstract class ReferralStore {
 const ReferralStore();
 Future<ReferralSnapshot> load(String id);
 Future<void> claim(String code);
}
class SupabaseReferralStore extends ReferralStore {
 const SupabaseReferralStore();
 @override Future<ReferralSnapshot> load(String id) async {
  var own = await soveraClient.from('sovera_referral_codes').select('code').eq('user_id',id).maybeSingle();
  if(own==null){
   try { own=await soveraClient.from('sovera_referral_codes').insert({'user_id':id}).select('code').single(); }
   on PostgrestException catch(e){if(e.code!='23505') rethrow; own=await soveraClient.from('sovera_referral_codes').select('code').eq('user_id',id).single();}
  }
  final code=own['code'] as String;
  final result=await soveraClient.from('sovera_referrals').select('created_at').eq('referral_code',code).order('created_at',ascending:false).limit(20).count(CountOption.exact);
  final claimed=await soveraClient.from('sovera_referrals').select('referral_code').eq('referred_id',id).maybeSingle();
  return ReferralSnapshot(code:code,count:result.count,dates:result.data.map((r)=>r['created_at'] as String).toList(),claimedCode:claimed?['referral_code'] as String?);
 }
 @override Future<void> claim(String code) async {await soveraClient.from('sovera_referrals').insert({'referral_code':code});}
}
class ReferralPage extends StatefulWidget {
 final Map<String,dynamic>? profile; final ReferralStore store;
 const ReferralPage({super.key,this.profile,this.store=const SupabaseReferralStore()});
 @override State<ReferralPage> createState()=>_ReferralPageState();
}
class _ReferralPageState extends State<ReferralPage> {
 final input=TextEditingController(); ReferralSnapshot? data; bool loading=false,busy=false; String? error;
 @override void initState(){super.initState();if(widget.profile!=null)load();}
 @override void dispose(){input.dispose();super.dispose();}
 void notice(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
 Future<void> load() async {
  setState((){loading=true;error=null;});
  try{final value=await widget.store.load(widget.profile!['id'] as String);if(mounted)setState(()=>data=value);}
  catch(_){if(mounted)setState(()=>error='Could not load invitations. Check your connection and retry.');}
  finally{if(mounted)setState(()=>loading=false);}
 }
 Future<void> claim() async {
  final code=parseReferralCode(input.text.trim());
  if(code==null){notice('Enter a valid Sovera code or paste an invitation.');return;}
  if(code==data?.code){notice('You cannot use your own code.');return;}
  setState(()=>busy=true);
  try{await widget.store.claim(code);if(!mounted)return;setState(()=>data=ReferralSnapshot(code:data!.code,count:data!.count,dates:data!.dates,claimedCode:code));notice('Invitation saved successfully.');}
  on PostgrestException catch(e){notice(e.code=='23505'?'Your account already has a referrer. Refresh to see it.':e.code=='23503'?'This invitation code was not found.':'Could not save this code. Please check and retry.');}
  catch(_){notice('Could not save your invitation. Please retry.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> copy(String text) async {await Clipboard.setData(ClipboardData(text:text));notice('Copied to clipboard');}
 Future<void> share() async {try{final opened=await launchUrl(Uri.https('wa.me','/',{'text':referralInvitation(data!.code)}),mode:LaunchMode.externalApplication);if(!opened)notice('Could not open WhatsApp. Use Copy invitation.');}catch(_){notice('Could not open WhatsApp. Use Copy invitation.');}}
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('Invite & referrals'),actions:[if(widget.profile!=null)IconButton(tooltip:'Refresh referrals',onPressed:loading||busy?null:load,icon:const Icon(Icons.refresh_rounded))]),
  body:ListView(padding:const EdgeInsets.all(20),children:[
   const Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Jewel(Icons.diversity_2_rounded,color:cyan),SizedBox(height:18),Text('Good rooms.\nBetter with friends.',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800,height:1.15)),SizedBox(height:12),Text('Invite your people to Sovera and grow your circle.',style:TextStyle(color:Colors.white70,height:1.5))])),const SizedBox(height:20),
   if(widget.profile==null)const Glass(child:Text('Sign in to get your personal invitation code and save referrals to your account.'))
   else if(loading)const Center(child:Padding(padding:EdgeInsets.all(30),child:CircularProgressIndicator()))
   else if(error!=null)Glass(child:Column(children:[Text(error!),TextButton.icon(onPressed:load,icon:const Icon(Icons.refresh_rounded),label:const Text('Retry'))]))
   else if(data!=null)...[
    Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('YOUR INVITATION CODE',style:TextStyle(color:gold,fontSize:12,letterSpacing:1.4)),const SizedBox(height:12),SelectableText(data!.code,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800,letterSpacing:1)),const SizedBox(height:16),Wrap(spacing:10,runSpacing:10,children:[FilledButton.icon(onPressed:()=>copy(data!.code),icon:const Icon(Icons.copy_rounded),label:const Text('Copy code')),OutlinedButton.icon(onPressed:()=>copy(referralInvitation(data!.code)),icon:const Icon(Icons.link_rounded),label:const Text('Copy invitation')),OutlinedButton.icon(onPressed:share,icon:const Icon(Icons.send_rounded),label:const Text('Invite via WhatsApp'))])])),const SizedBox(height:16),
    Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${data!.count}',style:const TextStyle(color:cyan,fontSize:38,fontWeight:FontWeight.w800)),const Text('Friends joined with your code',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:8),const Text('Counts saved code claims, not link clicks or downloads. Coin rewards are not configured.',style:TextStyle(color:Colors.white60,height:1.4))])),const SizedBox(height:16),
    Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Invited by a friend?',style:TextStyle(fontSize:19,fontWeight:FontWeight.w700)),const SizedBox(height:12),if(data!.claimedCode!=null)...[const Icon(Icons.verified_rounded,color:cyan),const SizedBox(height:8),Text('Invitation saved: ${data!.claimedCode}'),const Text('Your referrer is saved to your account.',style:TextStyle(color:Colors.white60))]else ...[const Text('Install → Sign in → Enter their code here. You can use one friend’s code once; it cannot be changed.',style:TextStyle(color:Colors.white60,height:1.5)),const SizedBox(height:14),TextField(controller:input,enabled:!busy,maxLength:1000,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Friend’s code or invitation',counterText:'',border:OutlineInputBorder())),const SizedBox(height:12),FilledButton.icon(onPressed:busy?null:claim,icon:Icon(busy?Icons.hourglass_top_rounded:Icons.check_rounded),label:Text(busy?'Saving…':'Apply invitation'))]])),const SizedBox(height:16),
    Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Recent joins',style:TextStyle(fontSize:19,fontWeight:FontWeight.w700)),const SizedBox(height:12),if(data!.dates.isEmpty)const Text('Your circle starts here. Share your invitation with a friend.',style:TextStyle(color:Colors.white60)),for(final date in data!.dates)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.person_add_alt_1_rounded,color:cyan),title:const Text('Referral confirmed'),subtitle:Text(DateTime.tryParse(date)?.toLocal().toString().split('.').first??'Saved')),if(data!.count>20)const Text('Showing your 20 most recent joins.',style:TextStyle(color:Colors.white60))])),
   ],const SizedBox(height:24),
  ]));
}
