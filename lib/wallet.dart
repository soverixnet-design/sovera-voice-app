import 'community_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_gate.dart';
import 'main.dart' show Glass, Jewel, BrandLogo, gold, cyan, pink, SupportPage;
import 'support_tickets.dart';

abstract class CoinStore {
 const CoinStore();
 Future<Map<String,dynamic>?> balance(String userId);
 Future<List<Map<String,dynamic>>> entries(String userId,int offset,String currency);
 Future<List<Map<String,dynamic>>> sellers(String search,String country,int offset);
}
class SupabaseCoinStore extends CoinStore {
 const SupabaseCoinStore();
 @override Future<Map<String,dynamic>?> balance(String userId)=>soveraClient.from('sovera_wallet_balances').select().eq('user_id',userId).maybeSingle();
 @override Future<List<Map<String,dynamic>>> entries(String userId,int offset,String currency) async {
  var query=soveraClient.from('sovera_wallet_entries').select().eq('user_id',userId);
  if(currency!='All')query=query.neq(currency=='Coins'?'coin_delta':'diamond_delta',0);
  return await query.order('created_at',ascending:false).order('id',ascending:false).range(offset,offset+19);
 }
 @override Future<List<Map<String,dynamic>>> sellers(String search,String country,int offset) async {
  var query=soveraClient.from('sovera_coin_sellers').select('seller_uid,display_name,country,languages,description').eq('published',true);
  if(country!='All')query=query.eq('country',country);
  if(search.isNotEmpty){
   final id=int.tryParse(search);
   if(id!=null){query=query.eq('seller_uid',id);}else{
    final safe=search.replaceAll('\\',r'\\').replaceAll('%',r'\%').replaceAll('_',r'\_');
    query=query.ilike('display_name','%$safe%');
   }
  }
  return await query.order('display_name').order('seller_uid').range(offset,offset+19);
 }
}
String coinNumber(Object? value){
 final raw=value?.toString()??'—';
 if(!RegExp(r'^-?\d+$').hasMatch(raw))return '—';
 return raw.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),(m)=>'${m[1]},');
}
String deltaText(Object? value){final raw=value?.toString()??'0';return '${raw.startsWith('-')?'':'+'}${coinNumber(raw)}';}
void openRechargeSupport(BuildContext context,Map<String,dynamic>? profile)=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>profile==null?const SupportPage(title:'Recharge support'):const SavedSupportPage(title:'Recharge support')));

class WalletPage extends StatefulWidget {
 final Map<String,dynamic>? profile;final CoinStore store;
 const WalletPage({super.key,this.profile,this.store=const SupabaseCoinStore()});
 @override State<WalletPage> createState()=>_WalletPageState();
}
class _WalletPageState extends State<WalletPage>{
 Map<String,dynamic>? balance;bool loading=false,hidden=false;String? error;
 @override void initState(){super.initState();if(widget.profile!=null)load();}
 Future<void> load() async {
  setState((){loading=true;error=null;balance=null;});
  try{final result=await widget.store.balance(widget.profile!['id'] as String);if(mounted)setState(()=>balance=result);}
  catch(_){if(mounted)setState(()=>error='Could not load your wallet.');}
  finally{if(mounted)setState(()=>loading=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Wallet'),actions:[IconButton(tooltip:hidden?'Show balances':'Hide balances',onPressed:()=>setState(()=>hidden=!hidden),icon:Icon(hidden?Icons.visibility_off_outlined:Icons.visibility_outlined)),if(widget.profile!=null)IconButton(tooltip:'Refresh wallet',onPressed:loading?null:load,icon:const Icon(Icons.refresh_rounded))]),body:ListView(padding:const EdgeInsets.all(20),children:[
  Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   const Row(children:[BrandLogo(size:52),SizedBox(width:12),Expanded(child:Text('My Sovera wallet',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800)))]),
   const SizedBox(height:18),Text(widget.profile==null?'Sign in to view your wallet':'User ID · ${widget.profile!['uid']}',style:const TextStyle(color:Colors.white60)),
   const SizedBox(height:12),if(loading)const LinearProgressIndicator(),
   if(error!=null)TextButton(onPressed:load,child:Text('$error Retry')),
   const SizedBox(height:10),_Balance(label:'Coins',value:hidden?'••••':coinNumber(balance?['coins']),icon:Icons.toll_rounded,color:gold),
   const Divider(height:28),_Balance(label:'Diamonds',value:hidden?'••••':coinNumber(balance?['diamonds']),icon:Icons.diamond_rounded,color:cyan),
   const SizedBox(height:18),Text(balance==null?'No verified wallet loaded':balance!['status']=='frozen'?'Wallet frozen · Contact support':'Verified ledger balance',style:const TextStyle(color:Colors.white60,fontSize:12)),
  ])),
  const SizedBox(height:22),const Text('Recharge & manage',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:12),
  if(widget.profile!=null)_Action(icon:Icons.swap_horiz_rounded,title:'Exchange Diamonds',subtitle:'View the current rate and exchange',color:cyan,onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const DiamondExchange()))),
  _Action(icon:Icons.storefront_rounded,title:'Coin seller list',subtitle:'Find owner-approved sellers by name or ID',color:gold,onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>CoinSellerList(profile:widget.profile,store:widget.store)))),
  _Action(icon:Icons.receipt_long_rounded,title:'Transaction history',subtitle:'Coins and Diamonds · Private ledger',color:cyan,onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>WalletHistory(profile:widget.profile,store:widget.store)))),
  _Action(icon:Icons.support_agent_rounded,title:'Recharge support',subtitle:'Ask about your recharge or seller',color:pink,onTap:()=>openRechargeSupport(context,widget.profile)),
  const SizedBox(height:12),const Glass(tint:cyan,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Diamond exchange',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),SizedBox(height:10),Text('100 Diamonds = 70 Coins',style:TextStyle(color:gold,fontSize:18)),SizedBox(height:10),Text('Exchange and recharge transfers are not enabled yet. This screen only reads verified records.',style:TextStyle(color:Colors.white60,height:1.5))])),
 ]));
}
class _Balance extends StatelessWidget{
 final String label,value;final IconData icon;final Color color;
 const _Balance({required this.label,required this.value,required this.icon,required this.color});
 @override Widget build(BuildContext context)=>Row(children:[Jewel(icon,color:color,size:46),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.white70)),const SizedBox(height:6),Text(value,style:TextStyle(fontSize:28,fontWeight:FontWeight.w800,color:color))]))]);
}
class _Action extends StatelessWidget{
 final IconData icon;final String title,subtitle;final Color color;final VoidCallback onTap;
 const _Action({required this.icon,required this.title,required this.subtitle,required this.color,required this.onTap});
 @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(tint:color,padding:const EdgeInsets.all(6),child:ListTile(onTap:onTap,leading:Icon(icon,color:color),title:Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(subtitle,style:const TextStyle(color:Colors.white60,fontSize:12)),trailing:const Icon(Icons.chevron_right_rounded))));
}

class CoinSellerList extends StatefulWidget{
 final Map<String,dynamic>? profile;final CoinStore store;
 const CoinSellerList({super.key,this.profile,this.store=const SupabaseCoinStore()});
 @override State<CoinSellerList> createState()=>_CoinSellerListState();
}
class _CoinSellerListState extends State<CoinSellerList>{
 final search=TextEditingController();String country='All';
 List<Map<String,dynamic>> rows=[];bool loading=true,more=false;String? error;int request=0;
 @override void initState(){super.initState();load();}
 @override void dispose(){request++;search.dispose();super.dispose();}
 Future<void> load({bool next=false}) async {
  final token=++request;final offset=next?rows.length:0;
  setState((){loading=true;error=null;if(!next)rows=[];});
  try{final result=await widget.store.sellers(search.text.trim(),country,offset);if(mounted&&token==request)setState((){rows=[if(next)...rows,...result];more=result.length==20;});}
  catch(_){if(mounted&&token==request)setState(()=>error='Could not load sellers. Please retry.');}
  finally{if(mounted&&token==request)setState(()=>loading=false);}
 }
 void details(Map<String,dynamic> seller)=>showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(sheet)=>SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
  const Jewel(Icons.verified_rounded,color:gold,size:58),const SizedBox(height:16),Text(seller['display_name'].toString(),style:const TextStyle(fontSize:25,fontWeight:FontWeight.bold)),const SizedBox(height:12),Text('Seller ID · ${seller['seller_uid']}'),const SizedBox(height:8),Text('${seller['country']} · ${seller['languages']}'),const SizedBox(height:14),Text(seller['description'].toString()),const SizedBox(height:16),
  OutlinedButton.icon(onPressed:()async{await Clipboard.setData(ClipboardData(text:seller['seller_uid'].toString()));if(sheet.mounted)ScaffoldMessenger.of(sheet).showSnackBar(const SnackBar(content:Text('Seller ID copied.')));},icon:const Icon(Icons.copy_rounded),label:const Text('Copy seller ID')),
  const SizedBox(height:8),FilledButton.icon(onPressed:(){Navigator.pop(sheet);openRechargeSupport(context,widget.profile);},icon:const Icon(Icons.support_agent_rounded),label:const Text('Recharge support')),
  const SizedBox(height:14),const Text('Listing approval is managed by Sovera. In-app payments and seller transfers are not enabled.',style:TextStyle(color:Colors.white60,fontSize:12,height:1.5)),
 ]))));
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Coin seller list'),actions:[IconButton(tooltip:'Refresh sellers',onPressed:()=>load(),icon:const Icon(Icons.refresh_rounded))]),body:ListView(padding:const EdgeInsets.all(20),children:[
  const Glass(tint:gold,child:Row(children:[Jewel(Icons.storefront_rounded,color:gold,size:52),SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Sovera coin sellers',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),SizedBox(height:8),Text('Only owner-approved listings appear here.',style:TextStyle(color:Colors.white60,height:1.5))]))])),
  const SizedBox(height:20),TextField(controller:search,maxLength:80,textInputAction:TextInputAction.search,onSubmitted:(_)=>load(),decoration:InputDecoration(labelText:'Seller name or ID',counterText:'',prefixIcon:const Icon(Icons.search_rounded),suffixIcon:IconButton(tooltip:'Search sellers',onPressed:()=>load(),icon:const Icon(Icons.arrow_forward_rounded)),border:const OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(18))))),
  const SizedBox(height:14),Wrap(spacing:8,runSpacing:8,children:[for(final value in ['All','Bangladesh','Oman','Saudi Arabia'])ChoiceChip(label:Text(value),selected:country==value,onSelected:(_){country=value;load();})]),
  const SizedBox(height:20),if(loading)const LinearProgressIndicator(),if(error!=null)TextButton(onPressed:()=>load(next:rows.isNotEmpty),child:Text(error!)),
  if(!loading&&error==null&&rows.isEmpty)const Glass(tint:cyan,child:Column(children:[Icon(Icons.person_search_rounded,color:cyan,size:48),SizedBox(height:16),Text('No approved sellers found',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),SizedBox(height:10),Text('Try another name, ID or country. New sellers appear after owner approval.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,height:1.5))])),
  for(final seller in rows)_Action(icon:Icons.verified_rounded,title:seller['display_name'].toString(),subtitle:'ID ${seller['seller_uid']} · ${seller['country']}\n${seller['languages']}',color:gold,onTap:()=>details(seller)),
  if(more&&!loading)TextButton(onPressed:()=>load(next:true),child:const Text('Load more sellers')),
  const SizedBox(height:16),TextButton.icon(onPressed:()=>openRechargeSupport(context,widget.profile),icon:const Icon(Icons.support_agent_rounded),label:const Text('Recharge support')),
 ]));
}

class WalletHistory extends StatefulWidget{
 final Map<String,dynamic>? profile;final CoinStore store;
 const WalletHistory({super.key,this.profile,this.store=const SupabaseCoinStore()});
 @override State<WalletHistory> createState()=>_WalletHistoryState();
}
class _WalletHistoryState extends State<WalletHistory>{
 List<Map<String,dynamic>> rows=[];String currency='All';bool loading=false,more=false;String? error;int request=0;
 @override void initState(){super.initState();if(widget.profile!=null)load();}
 @override void dispose(){request++;super.dispose();}
 Future<void> load({bool next=false})async{
  final token=++request;final offset=next?rows.length:0;
  setState((){loading=true;error=null;if(!next)rows=[];});
  try{final result=await widget.store.entries(widget.profile!['id'] as String,offset,currency);if(mounted&&token==request)setState((){rows=[if(next)...rows,...result];more=result.length==20;});}
  catch(_){if(mounted&&token==request)setState(()=>error='Could not load transaction history.');}
  finally{if(mounted&&token==request)setState(()=>loading=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Transaction history'),actions:[if(widget.profile!=null)IconButton(tooltip:'Refresh history',onPressed:()=>load(),icon:const Icon(Icons.refresh_rounded))]),body:ListView(padding:const EdgeInsets.all(20),children:[
  const Text('Wallet activity',style:TextStyle(fontWeight:FontWeight.w800,fontSize:25)),const SizedBox(height:10),const Text('Posted ledger entries · Most recent first',style:TextStyle(color:Colors.white60)),const SizedBox(height:18),
  Wrap(spacing:8,children:[for(final value in ['All','Coins','Diamonds'])ChoiceChip(label:Text(value),selected:currency==value,onSelected:widget.profile==null?null:(_){currency=value;load();})]),const SizedBox(height:20),
  if(widget.profile==null)const Glass(child:Text('Sign in to view your private transaction history.'))
  else ...[
   if(loading)const LinearProgressIndicator(),if(error!=null)TextButton(onPressed:()=>load(next:rows.isNotEmpty),child:Text('$error Retry')),
   if(!loading&&error==null&&rows.isEmpty)const Glass(tint:cyan,child:Column(children:[Icon(Icons.receipt_long_rounded,size:48,color:cyan),SizedBox(height:14),Text('No transactions yet',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),SizedBox(height:10),Text('Verified activity will appear here.',style:TextStyle(color:Colors.white60))])),
   for(final row in rows)Padding(padding:const EdgeInsets.only(bottom:12),child:Glass(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(row['kind'].toString().toUpperCase(),style:const TextStyle(fontWeight:FontWeight.bold,color:gold)),const SizedBox(height:12),if(row['coin_delta'].toString()!='0')Text('${deltaText(row['coin_delta'])} Coins',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),if(row['diamond_delta'].toString()!='0')Text('${deltaText(row['diamond_delta'])} Diamonds',style:const TextStyle(fontSize:20,color:cyan)),const SizedBox(height:10),Text(DateTime.tryParse(row['created_at'].toString())?.toLocal().toString().split('.').first??'Date unavailable',style:const TextStyle(color:Colors.white60,fontSize:12)),const SizedBox(height:8),SelectableText('Reference · ${row['reference']}',style:const TextStyle(color:Colors.white54,fontSize:12))]))),
   if(more&&!loading)TextButton(onPressed:()=>load(next:true),child:const Text('Load more transactions')),
  ],
 ]));
}
