import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_profile.dart';
import 'firebase_community.dart' show communityRequestId;
import 'sovera_visuals.dart' show Glass,Jewel,cyan,gold,violet;
import 'sovera_icons.dart';

class FirebaseProgramsPage extends StatefulWidget {
 final FirebaseProfileApi api;final String initialSection;
 const FirebaseProgramsPage({super.key,required this.api,this.initialSection='vip'});
 @override State<FirebaseProgramsPage> createState()=>_FirebaseProgramsPageState();
}
class _FirebaseProgramsPageState extends State<FirebaseProgramsPage>{
 late String section;Map<String,dynamic>? data,pending;List<Map<String,dynamic>> orders=[],income=[];
 String? error;bool loading=true,busy=false;
 String get pendingKey=>'sovera.programs.pending.${widget.api.uid}';
 @override void initState(){super.initState();section=widget.initialSection;load();}
 Future<void> load()async{
  setState(()=>loading=true);
  try{
   final prefs=await SharedPreferences.getInstance();final stored=prefs.getString(pendingKey);
   final results=await Future.wait([widget.api.call('GET',suffix:'/programs'),widget.api.call('GET',suffix:'/programs/payments'),widget.api.call('GET',suffix:'/programs/agency-income')]);
   if(mounted)setState((){data=results[0];orders=(results[1]['items'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();income=(results[2]['items'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();pending=stored==null?null:Map<String,dynamic>.from(jsonDecode(stored) as Map);error=null;});
  }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load offers. Retry.');}
  finally{if(mounted)setState(()=>loading=false);}
 }
 Future<void> sendPending()async{
  if(pending==null||busy)return;setState(()=>busy=true);
  try{final p=pending!;await widget.api.call('POST',suffix:p['type']=='buy'?'/programs/buy':'/programs/payments',fields:Map<String,dynamic>.from(p['fields'] as Map));final prefs=await SharedPreferences.getInstance();await prefs.remove(pendingKey);pending=null;if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Saved. Membership activation or payment status comes from the server.')));await load();}}
  catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Request not confirmed. Retry the same request below.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> cancelPending()async{
  if(pending==null||busy)return;setState(()=>busy=true);
  try{
   final fields=Map<String,dynamic>.from(pending!['fields'] as Map);
   final result=await widget.api.call('POST',suffix:'/programs/cancel/${fields['request_id']}');
   final prefs=await SharedPreferences.getInstance();await prefs.remove(pendingKey);pending=null;
   if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result['applied']==true?'This request was already saved. Status refreshed.':'Pending request cancelled.')));await load();}
  }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not resolve request. Retry.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> purchase(Map<String,dynamic> p)async{
  if(busy||pending!=null)return;
  final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('${p['title']}'),content:Text('Spend ${p['coins']} Coins for ${p['days']} days? Your active membership can renew the same tier. Included collection items are available in Mall.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm purchase'))]));
  if(accepted!=true||!mounted)return;
  pending={'type':'buy','fields':{'item_id':p['id'],'expected_coins':p['coins'],'request_id':communityRequestId()}};final prefs=await SharedPreferences.getInstance();await prefs.setString(pendingKey,jsonEncode(pending));if(mounted)await sendPending();
 }
 Future<void> payment(Map<String,dynamic> p)async{
  if(pending!=null||busy)return;final input=TextEditingController();
  final reference=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text('${p['title']}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${p['price_minor']} minor units ${p['currency']} • ${p['coins']} Coins\n${p['payment_method']}\n\n${p['instructions']}\n\nSubmit only after paying through the stated method. Staff must verify the merchant receipt before Coins are issued.'),TextField(controller:input,maxLength:100,decoration:const InputDecoration(labelText:'Payment transaction reference'))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){if(input.text.trim().length>=3)Navigator.pop(ctx,input.text.trim());},child:const Text('Submit for verification'))]));
  await Future<void>.delayed(const Duration(milliseconds:300));input.dispose();if(reference==null||!mounted)return;
  pending={'type':'payment','fields':{'item_id':p['id'],'request_id':communityRequestId(),'reference':reference}};final prefs=await SharedPreferences.getInstance();await prefs.setString(pendingKey,jsonEncode(pending));if(mounted)await sendPending();
 }
 Future<void> referral()async{
  final input=TextEditingController();final code=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Enter inviter ID'),content:TextField(controller:input,keyboardType:TextInputType.number,maxLength:20,decoration:const InputDecoration(labelText:'Inviter public ID')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,input.text.trim()),child:const Text('Link inviter'))]));
  await Future<void>.delayed(const Duration(milliseconds:300));input.dispose();if(code==null||code.isEmpty||!mounted)return;
  try{await widget.api.call('POST',suffix:'/programs/referral',fields:{'public_id':code});await load();}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not link inviter.');}
 }
 Future<void> claimReferral(String target)async{
  if(busy)return;setState(()=>busy=true);try{await widget.api.call('POST',suffix:'/programs/referral/${Uri.encodeComponent(target)}/claim');await load();}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Referral is not yet qualified.');}finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){final packs=(data?['items'] as List? ?? []).map((r)=>Map<String,dynamic>.from(r as Map)).toList();return Scaffold(appBar:AppBar(title:const Text('Sovera Benefits'),actions:[IconButton(onPressed:loading?null:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(18),children:[
  Wrap(spacing:8,children:[for(final t in const [('vip','VIP & SVIP'),('referral','Referrals'),('recharge','Recharge'),('agency','Agency income')])ChoiceChip(label:Text(t.$2),selected:section==t.$1,onSelected:(_)=>setState(()=>section=t.$1))]),
  if(loading)const LinearProgressIndicator(),if(error!=null)Text(error!,style:const TextStyle(color:Colors.orangeAccent)),
  if(pending!=null)Glass(tint:gold,child:Column(children:[const Text('An earlier request is awaiting confirmation. Retry it safely before starting another purchase.'),FilledButton(onPressed:busy?null:sendPending,child:const Text('Retry same request')),TextButton(onPressed:busy?null:cancelPending,child:const Text('Resolve / cancel this request'))])),
  if(section=='vip')...[
   if(data?['membership'] is Map)Glass(tint:gold,child:Text('${data!['membership']['title']} • Level ${data!['membership']['level']}\nActive until ${DateTime.fromMillisecondsSinceEpoch((data!['membership']['expires_at'] as num).toInt()*1000).toLocal()}')),
   for(final p in packs.where((p)=>p['kind']=='vip'||p['kind']=='svip'))Padding(padding:const EdgeInsets.only(top:16),child:Glass(tint:violet,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Jewel(Icons.workspace_premium_rounded,color:gold,size:60),Text('${p['title']}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),Text('${p['coins']} Coins • ${p['days']} days • ${p['kind']} ${p['level']}'),Text('${(p['item_ids'] as List).length} collection items included'),FilledButton(onPressed:busy||pending!=null?null:()=>purchase(p),child:const Text('Review membership'))]))),
   if(!loading&&!packs.any((p)=>p['kind']=='vip'||p['kind']=='svip'))const Glass(child:Text('No owner-published membership offers yet.')),
  ],
  if(section=='referral'&&data!=null)...[
   Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const SoveraIcon(Icons.redeem_rounded,size:60),Text('Your inviter ID: ${data!['public_id']}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),TextButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:'Join Sovera. My inviter ID: ${data!['public_id']}')),icon:const Icon(Icons.copy),label:const Text('Copy invitation')),
    Text(data!['referral_policy']['enabled']==true?'A qualified referral earns ${data!['referral_policy']['reward_coins']} Coins after ${data!['referral_policy']['recharge_target']} verified recharge Coins. Signup window: ${data!['referral_policy']['join_days']} days.':'Referral rewards are not enabled.'),
    if(data!['referral']==null&&data!['referral_policy']['enabled']==true)FilledButton(onPressed:referral,child:const Text('Enter inviter ID')),
   ])),
   for(final r in data!['invited'] as List)ListTile(title:Text('${r['name']}'),subtitle:Text(r['claimed_at']==null?'Waiting for verified recharge qualification':'Reward received'),trailing:r['claimed_at']==null?TextButton(onPressed:busy?null:()=>claimReferral('${r['uid']}'),child:const Text('Claim')):const Icon(Icons.check,color:cyan)),
  ],
  if(section=='recharge')...[
   const Glass(child:Text('Recharge requests are manually verified against the payment provider. A submitted reference does not credit Coins automatically.')),
   for(final p in packs.where((p)=>p['kind']=='recharge'))Padding(padding:const EdgeInsets.only(top:16),child:Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const SoveraIcon(Icons.redeem_rounded,size:60),Text('${p['title']}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text('${p['coins']} Coins • ${p['price_minor']} minor units ${p['currency']}'),Text('${p['payment_method']}'),FilledButton(onPressed:busy||pending!=null?null:()=>payment(p),child:const Text('View instructions / submit reference'))]))),
   for(final r in orders)ListTile(title:Text('${r['offer']['title']} • ${r['status']}'),subtitle:Text('${r['reference']}\n${r['note']}')),
  ],
  if(section=='agency')...[
   const Glass(child:Text('Manager performance reports use recorded agency membership periods and qualifying gift Diamonds. Settlement is in app Coins, after owner review; this is not a cash payout.')),
   for(final r in income)Padding(padding:const EdgeInsets.only(top:16),child:Glass(tint:violet,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${r['name']} • ${r['month']}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text('Commission: ${r['commission']} Coins • ${r['paid_at']==null?'Not settled':'Settled'}'),for(final h in r['hosts'] as List)Text('${h['name']}: ${h['diamonds']} gift Diamonds • ${h['salary']} salary Coins')]))),
   if(!loading&&income.isEmpty)const Text('No published manager terms for your account.'),
  ],
 ]));}
}
