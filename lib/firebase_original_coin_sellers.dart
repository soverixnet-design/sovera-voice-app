import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_messaging.dart';
import 'country_picker.dart' show countryFlag;
import 'sovera_visuals.dart' show Glass,Jewel,gold;

class FirebaseOriginalCoinSellers extends StatefulWidget {
  final FirebaseProfileApi api;
  const FirebaseOriginalCoinSellers({super.key,required this.api});
  @override State<FirebaseOriginalCoinSellers> createState()=>_FirebaseOriginalCoinSellersState();
}
class _FirebaseOriginalCoinSellersState extends State<FirebaseOriginalCoinSellers>{
  String query='';String? error;bool loading=true;
  List<Map<String,dynamic>> rows=[];
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    setState(()=>loading=true);
    try{
      final result=await widget.api.call('GET',suffix:'/sellers');
      if(mounted)setState((){rows=(result['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();error=null;});
    }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load coin sellers.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Coin seller list'),actions:[IconButton(tooltip:'Refresh sellers',onPressed:loading?null:load,icon:const Icon(Icons.refresh))]),
    body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(20),children:[
      const Glass(tint:gold,child:Row(children:[Jewel(Icons.storefront_rounded,color:gold,size:53),SizedBox(width:14),Expanded(child:Text('Owner-approved coin sellers',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)))])),
      const SizedBox(height:18),
      TextField(onChanged:(value)=>setState(()=>query=value.toLowerCase().trim()),decoration:const InputDecoration(hintText:'Search seller name, ID or country',prefixIcon:Icon(Icons.search))),
      const SizedBox(height:18),
      if(loading)const Center(child:CircularProgressIndicator()),
      if(error!=null)Text(error!),
      if(!loading&&error==null&&rows.isEmpty)const Text('No approved sellers are available yet.'),
      for(final seller in rows.where((r)=>['name','public_id','country'].any((key)=>'${r[key]??''}'.toLowerCase().contains(query))))
        Padding(padding:const EdgeInsets.only(bottom:14),child:Glass(tint:gold,child:ListTile(
          contentPadding:EdgeInsets.zero,
          leading:CircleAvatar(radius:27,backgroundImage:seller['avatar_url'] is String&&(seller['avatar_url'] as String).isNotEmpty?NetworkImage(seller['avatar_url'] as String):null,child:seller['avatar_url']==null?const Icon(Icons.person):null),
          title:Text('${seller['name']}',style:const TextStyle(fontWeight:FontWeight.bold)),
          subtitle:Text('${countryFlag(seller['country']?.toString()??'')} ${seller['country']}\nID: ${seller['public_id']??'Not assigned'}\n${FirebaseServerWalletPageStateFormat.amount(seller['coins'])} Coins'),
          trailing:const Icon(Icons.chat_rounded,color:gold),
          onTap:seller['uid']==widget.api.uid?null:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>FirebaseDirectChat(api:widget.api,target:'${seller['uid']}',name:'${seller['name']}'))),
        ))),
    ])));
}
class FirebaseServerWalletPageStateFormat {
  static String amount(Object? value)=>(value?.toString()??'—').replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),(m)=>'${m[1]},');
}
