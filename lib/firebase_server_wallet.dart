import 'firebase_programs.dart';
import 'firebase_rewards.dart';
import 'firebase_original_coin_sellers.dart';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_community.dart' show communityRequestId;
import 'sovera_visuals.dart' show Glass, Jewel, gold, cyan;

/// A wallet view whose only source is the Sovera-owned account server.
/// Firebase Auth supplies identity tokens; it does not store Coins or Diamonds.
/// Never display a made-up zero for an identity that has not been migrated.
class FirebaseServerWalletPage extends StatefulWidget {
  final FirebaseProfileApi api;
  const FirebaseServerWalletPage({super.key,required this.api});
  @override State<FirebaseServerWalletPage> createState()=>_FirebaseServerWalletPageState();
}

class _FirebaseServerWalletPageState extends State<FirebaseServerWalletPage>{
  bool loading=true, loadingMore=false, hasMore=false;
  String filter='All';
  String? error;
  Map<String,dynamic>? pendingExchange;
  Map<String,dynamic>? wallet;
  List<Map<String,dynamic>> entries=[];
  @override void initState(){super.initState();refresh();}
  Future<void> refresh()async{
    setState(()=>loading=true);
    try{
      final result=await widget.api.call('GET',suffix:'/wallet');
      if(result['source']!='sovera-server'||
          result['status'] is! String||result['verified'] is! bool||
          result['canSpend'] is! bool){
        throw const ProfileApiError('Invalid wallet server response.');
      }
      List<Map<String,dynamic>> history=[];
      var more=false;
      if(result['verified']==true){
        if(result['coins'] is! String||result['diamonds'] is! String){
          throw const ProfileApiError('Wallet balances are unverified.');
        }
        final rows=await widget.api.call('GET',suffix:'/wallet/history');
        if(rows['entries'] is! List){
          throw const ProfileApiError('Wallet history unavailable.');
        }
        more=rows['has_more']==true;
        history=(rows['entries'] as List).whereType<Map>()
          .map((x)=>Map<String,dynamic>.from(x)).toList();
      }
      if(mounted)setState((){wallet=result;entries=history;hasMore=more;error=null;});
    }catch(e){
      if(mounted)setState((){
        error=e is ProfileApiError?e.message:
          'Could not connect to the Sovera wallet server.';
        wallet=null;entries=[];hasMore=false;
      });
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }
  Future<void> exchange()async{
    var draft=pendingExchange?['diamonds']?.toString()??'100';
    var working=false;String? message;
    final saved=await showDialog<bool>(context:context,builder:(context)=>StatefulBuilder(
      builder:(context,update)=>AlertDialog(
        title:const Text('Exchange Diamonds'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('100 Diamonds = 70 Coins'),
          const SizedBox(height:12),
          TextFormField(initialValue:draft,readOnly:pendingExchange!=null||working,
            keyboardType:TextInputType.number,maxLength:16,
            decoration:const InputDecoration(labelText:'Diamonds to exchange'),
            onChanged:(value)=>update(()=>draft=value.trim())),
          Text('You receive: ${((int.tryParse(draft)??0)~/100)*70} Coins'),
          if(message!=null)Text(message!),
        ]),
        actions:[
          TextButton(onPressed:working?null:()=>Navigator.pop(context,false),child:const Text('Close')),
          FilledButton(onPressed:working?null:()async{
            final value=int.tryParse(draft);
            if(value==null||value<100||value>9007199254740991||value%100!=0){
              update(()=>message='Enter a multiple of 100 Diamonds.');return;
            }
            if(pendingExchange==null&&(BigInt.tryParse(wallet?['diamonds']?.toString()??'')??BigInt.zero)<BigInt.from(value)){
              update(()=>message='Insufficient Diamonds.');return;
            }
            pendingExchange??={'diamonds':value,'request_id':communityRequestId()};
            update(()=>working=true);
            try{
              await widget.api.call('POST',suffix:'/wallet/exchange',fields:pendingExchange);
              pendingExchange=null;
              if(context.mounted)Navigator.pop(context,true);
            }catch(e){
              if(e is ProfileApiError&&e.status==409)pendingExchange=null;
              if(context.mounted)update(()=>message=e is ProfileApiError?e.message:'Could not confirm. Retry the same exchange.');
            }finally{if(context.mounted)update(()=>working=false);}
          },child:Text(working?'Exchanging…':pendingExchange==null?'Confirm exchange':'Retry exchange')),
        ])));
    if(saved==true&&mounted){
      await refresh();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Exchange completed.')));
    }
  }
  Future<void> loadMore()async{
    if(loading||loadingMore||!hasMore||entries.isEmpty)return;
    setState(()=>loadingMore=true);
    try{
      final last=entries.last;
      final cursor=Uri(queryParameters:{
        'before_time':'${last['created_at']}',
        'before_ref':'${last['reference']}',
      }).query;
      final result=await widget.api.call('GET',suffix:'/wallet/history?$cursor');
      if(result['entries'] is! List)throw const ProfileApiError('Wallet history unavailable.');
      final rows=(result['entries'] as List).whereType<Map>()
        .map((x)=>Map<String,dynamic>.from(x)).toList();
      if(mounted)setState((){
        final known=entries.map((x)=>x['reference']).toSet();
        entries.addAll(rows.where((x)=>known.add(x['reference'])));
        hasMore=result['has_more']==true;error=null;
      });
    }catch(e){
      if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load older transactions.');
    }finally{if(mounted)setState(()=>loadingMore=false);}
  }
  static String category(Object? kind)=>switch(kind){
    'recharge'=>'Recharge',
    'gift'=>'Gifts',
    'game_debit'||'game_win'||'refund'=>'Games',
    'exchange'=>'Exchange',
    'verified_import'=>'Imported',
    _=>'Other',
  };
  static String label(Object? kind)=>switch(kind){
    'game_debit'=>'Game stake',
    'game_win'=>'Game winnings',
    'refund'=>'Game refund',
    'verified_import'=>'Imported balance',
    'admin_adjust'=>'Admin adjustment',
    _=>category(kind),
  };
  static String signed(Object? value){
    final number=BigInt.tryParse(value?.toString()??'');
    if(number==null)return '—';
    return '${number.isNegative?'-':number>BigInt.zero?'+':''}${amount(number.abs())}';
  }
  static String date(Object? value){
    final seconds=int.tryParse(value?.toString()??'');
    if(seconds==null)return '';
    final time=DateTime.fromMillisecondsSinceEpoch(seconds*1000).toLocal();
    return '${time.year}-${time.month.toString().padLeft(2,'0')}-${time.day.toString().padLeft(2,'0')} '
      '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}';
  }
  void receipt(Map<String,dynamic> item){
    showDialog<void>(context:context,builder:(context)=>AlertDialog(
      title:Text((item['reference']?.toString().startsWith('reward:')==true?'Reward received':label(item['kind']))),
      content:SelectableText('${date(item['created_at'])}\n'
        'Coins: ${signed(item['coin_delta'])}\nDiamonds: ${signed(item['diamond_delta'])}\n\n'
        'Reference: ${item['reference']}'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))]));
  }
  static String amount(Object? value){
    final text=value?.toString()??'';
    if(!RegExp(r'^\d+$').hasMatch(text))return '—';
    return text.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match)=>'${match[1]},');
  }
  Widget balance(String title,String value,IconData icon,Color color)=>
    Expanded(child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(gradient:LinearGradient(colors:[color.withValues(alpha:.24),const Color(0xff192137)]),borderRadius:BorderRadius.circular(22),border:Border.all(color:color.withValues(alpha:.5)),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.3),blurRadius:16,offset:const Offset(0,8))]),child:Column(children:[
      Jewel(icon,color:color,size:45),const SizedBox(height:8),
      Text(title,style:const TextStyle(fontSize:12,color:Colors.white70)),
      const SizedBox(height:5),
      FittedBox(fit:BoxFit.scaleDown,child:Text(value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    ])));
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('My Sovera Wallet'),
      actions:[IconButton(tooltip:'Refresh verified balance',
        onPressed:loading?null:refresh,icon:const Icon(Icons.refresh_rounded))]),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
      Glass(tint:gold,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Coins & Diamonds',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
        const SizedBox(height:6),
        const Text('Balances come only from the Sovera account server.',
          style:TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:20),
        if(loading)const Center(child:CircularProgressIndicator()),
        if(!loading&&error!=null)Text(error!,style:const TextStyle(color:Colors.orangeAccent)),
        if(!loading&&wallet?['verified']==false)
          const Text('Your previous wallet is not yet verified on this server. '
            'No balance has been reset and no new Coins were created.',
            style:TextStyle(color:Colors.amberAccent)),
        if(!loading&&wallet?['verified']==true)Row(children:[
          balance('Coins',amount(wallet!['coins']),Icons.toll_rounded,gold),
          const SizedBox(width:16),
          balance('Diamonds',amount(wallet!['diamonds']),Icons.diamond_rounded,cyan),
        ]),
        const SizedBox(height:18),
        if(wallet?['verified']==true&&wallet?['status']=='active')
          FilledButton.icon(onPressed:loading?null:exchange,icon:const Icon(Icons.swap_horiz),
            label:Text(pendingExchange==null?'Exchange Diamonds → Coins':'Retry pending exchange')),
        if(wallet?['verified']==true&&wallet?['status']=='active')
          const Text('Wallet verified · Your Coins and Diamonds are linked to this account.',
            style:TextStyle(fontSize:12,color:Colors.white70)),
        if(wallet?['verified']==true&&wallet?['canSpend']!=true)
          const Text('Coin games are not yet enabled. Wallet verification does not activate betting.',
            style:TextStyle(fontSize:12,color:Colors.white70)),
        if(wallet?['status']=='frozen')
          const Text('Wallet frozen · Contact support',
            style:TextStyle(color:Colors.orangeAccent)),
      ])),
      const SizedBox(height:16),
      FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseProgramsPage(api:widget.api,initialSection:'recharge'))),icon:const Icon(Icons.payments_rounded),label:const Text('Recharge offers & payment status')),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseRewardsPage(api:widget.api,initialTab:'recharge'))),icon:const Icon(Icons.redeem_rounded),label:const Text('Recharge Rewards')),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseOriginalCoinSellers(api:widget.api))),icon:const Icon(Icons.storefront_rounded),label:const Text('Coin seller list')),
      if(entries.isNotEmpty)...[
        const SizedBox(height:20),
        const Text('Server transaction history',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        Wrap(spacing:6,children:[for(final name in const ['All','Recharge','Gifts','Games','Exchange','Imported','Other'])
          ChoiceChip(label:Text(name),selected:filter==name,onSelected:(_)=>setState(()=>filter=name))]),
        const SizedBox(height:10),
        for(final item in entries.where((x)=>filter=='All'||category(x['kind'])==filter))
          ListTile(
            onTap:()=>receipt(item),
            title:Text((item['reference']?.toString().startsWith('reward:')==true?'Reward received':label(item['kind']))),
            subtitle:Text(date(item['created_at'])),
            trailing:Text('C ${signed(item['coin_delta'])}  ·  D ${signed(item['diamond_delta'])}'),
          ),
        if(!entries.any((x)=>filter=='All'||category(x['kind'])==filter))
          const Padding(padding:EdgeInsets.all(12),child:Text('No matching transactions in loaded history.')),
        if(hasMore)TextButton(onPressed:loadingMore?null:loadMore,
          child:Text(loadingMore?'Loading older transactions…':'Load older transactions')),
      ],
    ])),
  );
}
