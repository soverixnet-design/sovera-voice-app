import 'package:flutter/material.dart';
import 'firebase_profile.dart';
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
  bool loading=true;
  String? error;
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
      if(result['verified']==true){
        if(result['coins'] is! String||result['diamonds'] is! String){
          throw const ProfileApiError('Wallet balances are unverified.');
        }
        final rows=await widget.api.call('GET',suffix:'/wallet/history');
        if(rows['entries'] is! List){
          throw const ProfileApiError('Wallet history unavailable.');
        }
        history=(rows['entries'] as List).whereType<Map>()
          .map((x)=>Map<String,dynamic>.from(x)).toList();
      }
      if(mounted)setState((){wallet=result;entries=history;error=null;});
    }catch(e){
      if(mounted)setState((){
        error=e is ProfileApiError?e.message:
          'Could not connect to the Sovera wallet server.';
        wallet=null;entries=[];
      });
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }
  static String amount(Object? value){
    final text=value?.toString()??'';
    if(!RegExp(r'^\d+$').hasMatch(text))return '—';
    return text.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match)=>'${match[1]},');
  }
  Widget balance(String title,String value,IconData icon,Color color)=>
    Expanded(child:Column(children:[
      Jewel(icon,color:color,size:45),const SizedBox(height:8),
      Text(title,style:const TextStyle(fontSize:12,color:Colors.white70)),
      const SizedBox(height:5),
      Text(value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    ]));
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
          const Text('Wallet verified · Your Coins and Diamonds are linked to this account.',
            style:TextStyle(fontSize:12,color:Colors.white70)),
        if(wallet?['verified']==true&&wallet?['canSpend']!=true)
          const Text('Coin games are not yet enabled. Wallet verification does not activate betting.',
            style:TextStyle(fontSize:12,color:Colors.white70)),
        if(wallet?['status']=='frozen')
          const Text('Wallet frozen · Contact support',
            style:TextStyle(color:Colors.orangeAccent)),
      ])),
      if(entries.isNotEmpty)...[
        const SizedBox(height:20),
        const Text('Server transaction history',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        for(final item in entries)
          ListTile(
            title:Text(item['kind']?.toString()??'Server transaction'),
            subtitle:Text(item['reference']?.toString()??''),
            trailing:Text('C ${item['coin_delta']??'—'}  ·  D ${item['diamond_delta']??'—'}'),
          ),
      ],
    ])),
  );
}
