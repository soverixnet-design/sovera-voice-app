import 'sovera_icons.dart';
import 'firebase_community.dart' show FirebaseCommunity;
import 'dart:async';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_catalog.dart';
import 'firebase_members.dart';
import 'sovera_visuals.dart' show Glass,Jewel,cyan,gold,violet,pink;

/// Reward eligibility is returned by the account server, never by this screen.
class FirebaseRewardsPage extends StatefulWidget {
  final FirebaseProfileApi api;
  final String initialTab;
  final String initialMetric;
  final String initialPeriod;
  const FirebaseRewardsPage({super.key,required this.api,this.initialTab='ranking',this.initialMetric='rich',this.initialPeriod='weekly'});
  @override State<FirebaseRewardsPage> createState()=>_FirebaseRewardsPageState();
}
class _FirebaseRewardsPageState extends State<FirebaseRewardsPage>{
  late String tab;String metric='rich',period='weekly';
  Map<String,dynamic>? board;List<Map<String,dynamic>> campaigns=[];
  String? error,claiming;bool loading=true;int generation=0,clock=0;Timer? ticker;
  @override void initState(){super.initState();tab=widget.initialTab;metric=widget.initialMetric;period=widget.initialPeriod;load();ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState(()=>clock++);});}
  @override void dispose(){ticker?.cancel();super.dispose();}
  Future<void> load()async{
    final version=++generation;setState((){loading=true;error=null;board=null;});
    try{
      final results=await Future.wait([widget.api.call('GET',suffix:'/rankings?metric=$metric&period=$period'),widget.api.call('GET',suffix:'/rewards')]);
      if(mounted&&version==generation)setState((){board=results[0];campaigns=(results[1]['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();clock=0;});
    }catch(e){if(mounted&&version==generation)setState(()=>error=e is ProfileApiError?e.message:'Could not load rewards. Retry.');}
    finally{if(mounted&&version==generation)setState(()=>loading=false);}
  }
  Future<void> claim(Map<String,dynamic> campaign)async{
    if(claiming!=null)return;setState(()=>claiming='${campaign['id']}');
    try{await widget.api.call('POST',suffix:'/rewards/${campaign['id']}/claim');if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Reward received. Coins are in your wallet; collection items are in Mall.')));await load();}
    catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Claim failed. You can safely retry.');}
    finally{if(mounted)setState(()=>claiming=null);}
  }
  String remaining(int ends){final now=(board?['server_now'] as num?)?.toInt()??DateTime.now().millisecondsSinceEpoch~/1000;final seconds=(ends-now-clock).clamp(0,40000000);return seconds==0?'Finished':'${seconds~/86400}d ${(seconds%86400)~/3600}h ${(seconds%3600)~/60}m ${seconds%60}s';}
  void member(Map<String,dynamic> p)=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseMemberProfile(api:widget.api,uid:'${p['uid']}')));
  @override Widget build(BuildContext context){
    final rows=(board?['items'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    return Scaffold(appBar:AppBar(title:const Text('Sovera Rewards'),actions:[IconButton(tooltip:'Refresh',onPressed:loading?null:load,icon:const Icon(Icons.refresh))]),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,32),children:[
      const Text('THE SPOTLIGHT',style:TextStyle(color:cyan,letterSpacing:3,fontSize:11,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),const Text('Rise. Shine. Get rewarded.',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),
      const SizedBox(height:18),SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[for(final x in const [('ranking','Rankings',Icons.emoji_events_rounded),('event','Event Rewards',Icons.celebration_rounded),('recharge','Recharge Rewards',Icons.savings_rounded)])Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(avatar:Icon(x.$3,size:17),label:Text(x.$2),selected:tab==x.$1,onSelected:(_)=>setState(()=>tab=x.$1)))])),
      if(loading)const LinearProgressIndicator(),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Text(error!,style:const TextStyle(color:Colors.orangeAccent))),
      if(tab=='event')TextButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseCommunity(api:widget.api,section:'events',title:'Community events'))),icon:const SoveraIcon(Icons.campaign_rounded,size:28),label:const Text('Event announcements')),
      if(tab=='ranking')...[
        const SizedBox(height:14),Wrap(spacing:6,children:[for(final x in const [('rich','Rich'),('charm','Charm'),('play','Game Wins'),('recharge','Recharge')])ChoiceChip(label:Text(x.$2),selected:metric==x.$1,onSelected:loading?null:(_){setState(()=>metric=x.$1);load();})]),
        Wrap(spacing:8,children:[for(final p in const ['daily','weekly','monthly'])ChoiceChip(label:Text('${p[0].toUpperCase()}${p.substring(1)}'),selected:period==p,onSelected:loading?null:(_){setState(()=>period=p);load();})]),
        const SizedBox(height:12),Text('UTC period · ${remaining((board?['ends_at'] as num?)?.toInt()??0)}',textAlign:TextAlign.center,style:const TextStyle(color:gold)),
        const SizedBox(height:12),if(rows.isNotEmpty)RewardPodium(rows:rows.take(3).toList(),onTap:member),
        if(!loading&&error==null&&rows.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:30),child:Glass(child:Text('No qualifying activity this period. Rankings use confirmed gifts, game wins and recharge receipts.'))),
        if(board?['mine'] is Map)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Glass(tint:gold,child:Text('Your rank: #${board!['mine']['rank']}   •   ${board!['mine']['score']}'))),
        for(final r in rows.skip(3))Padding(padding:const EdgeInsets.only(bottom:10),child:Glass(padding:const EdgeInsets.all(10),tint:cyan,child:ListTile(onTap:()=>member(r),leading:RewardAvatar(person:r,size:46),title:Text('#${r['rank']}  ${r['name']}',maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('ID ${r['public_id']} · ${r['country']}'),trailing:Text('${r['score']}',style:const TextStyle(color:gold,fontWeight:FontWeight.bold))))),
        const Padding(padding:EdgeInsets.symmetric(vertical:18),child:Text('Ranking Rewards',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))),
      ],
      for(final c in campaigns.where((c)=>c['category']==tab&&c['status']!='cancelled'))campaignCard(c),
      if(!loading&&error==null&&!campaigns.any((c)=>c['category']==tab&&c['status']!='cancelled'))const Padding(padding:EdgeInsets.symmetric(vertical:18),child:Glass(child:Text('No reward campaign published yet. Owner-approved prizes and rules will appear here.'))),
      const SizedBox(height:15),const Text('Rich = gift Coins sent • Charm = gift Diamonds received\nGame Wins = confirmed game payouts • Recharge = approved recharge receipts\nTies use permanent server account order. Rewards and balance adjustments never increase these scores.',style:TextStyle(color:Colors.white54,fontSize:11,height:1.6)),
    ])));
  }
  Widget campaignCard(Map<String,dynamic> c){
    final ended=c['status']=='settled';final start=(c['starts_at'] as num).toInt(),end=(c['ends_at'] as num).toInt();
    return Padding(padding:const EdgeInsets.only(top:18),child:Glass(tint:c['category']=='recharge'?cyan:violet,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[SoveraIcon(c['category']=='recharge'?Icons.redeem_rounded:Icons.card_giftcard_rounded,size:54),const SizedBox(width:12),Expanded(child:Text('${c['title']}',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:20)))]),
      const SizedBox(height:12),Text(ended?'Final results':'Ends in ${remaining(end)}',style:const TextStyle(color:gold)),
      Text('${DateTime.fromMillisecondsSinceEpoch(start*1000,isUtc:true).toIso8601String().substring(0,16)} → ${DateTime.fromMillisecondsSinceEpoch(end*1000,isUtc:true).toIso8601String().substring(0,16)} UTC',style:const TextStyle(color:Colors.white54,fontSize:10)),
      const SizedBox(height:10),Text(c['category']=='recharge'?'Recharge ${c['threshold']} Coins • Your progress: ${c['score']}':'${c['metric']} ranking • Minimum score ${c['threshold']}'),
      for(final raw in c['prizes'] as List)prizeCard(Map<String,dynamic>.from(raw as Map)),
      for(final w in (c['winners'] as List).cast<Map>())ListTile(onTap:()=>member(Map<String,dynamic>.from(w)),contentPadding:EdgeInsets.zero,leading:RewardAvatar(person:Map<String,dynamic>.from(w),size:38),title:Text('#${w['rank']}  ${w['name']}'),subtitle:Text('ID ${w['public_id']} · ${w['score']}')),
      const SizedBox(height:12),if(c['claimed']==true)const Text('✓ Reward received',style:TextStyle(color:cyan,fontWeight:FontWeight.bold))else FilledButton.icon(onPressed:c['eligible']==true&&claiming==null?()=>claim(c):null,icon:const SoveraIcon(Icons.redeem_rounded,size:28),label:Text(claiming=='${c['id']}'?'Receiving…':c['eligible']==true?'Claim reward':ended?'Not eligible':'Reward unlocks after qualification')),
    ])));
  }
  Widget prizeCard(Map<String,dynamic> p)=>Padding(padding:const EdgeInsets.only(top:16),child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xff57436a),Color(0xff222540),Color(0xff111a30)]),border:Border.all(color:gold.withValues(alpha:.5)),boxShadow:const [BoxShadow(color:Colors.black45,offset:Offset(0,7),blurRadius:10)]),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(tab=='recharge'?'Recharge milestone':'TOP ${p['rank']}',style:const TextStyle(color:gold,fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:12),Wrap(spacing:12,runSpacing:12,children:[if((p['coins'] as num)>0)SizedBox(width:85,child:Column(children:[const Jewel(Icons.monetization_on_rounded,color:gold,size:60),const SizedBox(height:8),Text('${p['coins']} Coins',textAlign:TextAlign.center,style:const TextStyle(color:gold,fontWeight:FontWeight.bold))])),for(final a in p['items'] as List)SizedBox(width:85,child:Column(children:[SizedBox(height:65,width:70,child:CatalogImage(asset:Map<String,dynamic>.from(a as Map),fit:BoxFit.contain)),Text('${a['title']}',maxLines:2,textAlign:TextAlign.center,overflow:TextOverflow.ellipsis),Text('${p['days']} days',style:const TextStyle(color:cyan,fontSize:11))]))])])));
}
class RewardAvatar extends StatelessWidget{
 final Map<String,dynamic> person;final double size;
 const RewardAvatar({super.key,required this.person,this.size=70});
 @override Widget build(BuildContext context){final url=person['avatar_url'];final frame=person['equipped'] is Map?(person['equipped'] as Map)['frame']:null;if(frame is Map)return CatalogPortrait(asset:Map<String,dynamic>.from(frame),avatarUrl:url is String?url:null,size:size);return SizedBox(width:size,height:size,child:ClipOval(child:url is String&&url.startsWith('https://')?Image.network(url,fit:BoxFit.cover,errorBuilder:(_,e,s)=>Icon(Icons.person,color:cyan,size:size*.65)):ColoredBox(color:const Color(0xff234659),child:Icon(Icons.person_rounded,color:cyan,size:size*.65))));}
}
class RewardPodium extends StatelessWidget {
 final List<Map<String,dynamic>> rows;
 final void Function(Map<String,dynamic>) onTap;
 const RewardPodium({super.key,required this.rows,required this.onTap});
 @override Widget build(BuildContext context) => Container(
  padding: const EdgeInsets.fromLTRB(8,20,8,0),
  decoration: BoxDecoration(
   borderRadius: BorderRadius.circular(30),
   gradient: const RadialGradient(colors:[Color(0xff375f70),Color(0xff17233e),Color(0xff14192d)],radius:1),
  ),
  child: Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
   for(final rank in const [2,1,3]) Expanded(
    child: rank>rows.length ? const SizedBox() : InkWell(
     onTap:()=>onTap(rows[rank-1]),
     child:Column(children:[
      if(rank==1) const Icon(Icons.workspace_premium_rounded,color:gold,size:38),
      Container(
       padding:const EdgeInsets.all(5),
       decoration:BoxDecoration(
        shape:BoxShape.circle,
        gradient:LinearGradient(colors:rank==1 ? [const Color(0xfffff3be),gold,const Color(0xff876124)] : rank==2 ? [Colors.white,cyan,const Color(0xff515a7c)] : [gold,pink,const Color(0xff75423f)]),
        boxShadow:[BoxShadow(color:gold.withValues(alpha:rank==1 ? .35 : .12),blurRadius:20,offset:const Offset(0,8))],
       ),
       child:RewardAvatar(person:rows[rank-1],size:rank==1 ? 78 : 58),
      ),
      const SizedBox(height:10),
      Text('${rows[rank-1]['name']}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w900)),
      Text('ID ${rows[rank-1]['public_id']}',style:const TextStyle(fontSize:10,color:Colors.white60)),
      FittedBox(child:Text('${rows[rank-1]['score']}',style:const TextStyle(color:gold,fontWeight:FontWeight.bold))),
      const SizedBox(height:12),
      Container(
       height:rank==1 ? 85 : rank==2 ? 58 : 42,
       alignment:Alignment.center,
       decoration:BoxDecoration(
        borderRadius:const BorderRadius.vertical(top:Radius.circular(18)),
        gradient:LinearGradient(colors:[gold.withValues(alpha:.8),const Color(0xff79603d),const Color(0xffd8bd79)],begin:Alignment.topLeft,end:Alignment.bottomRight),
        border:Border.all(color:const Color(0xffffeabd)),
        boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:10,offset:Offset(0,-3))],
       ),
       child:Text('$rank',style:const TextStyle(color:Color(0xff453323),fontSize:28,fontWeight:FontWeight.w900)),
      ),
     ]),
    ),
   ),
  ]),
 );
}
