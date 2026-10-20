import 'package:flutter/material.dart';
import 'sovera_visuals.dart' show Glass,Jewel,gold;

/// Original Coin Seller directory appearance, but never invents a seller.
/// Publishing/search are server functions and still need migration.
class FirebaseOriginalCoinSellers extends StatefulWidget {
  const FirebaseOriginalCoinSellers({super.key});
  @override State<FirebaseOriginalCoinSellers> createState()=>_FirebaseOriginalCoinSellersState();
}
class _FirebaseOriginalCoinSellersState extends State<FirebaseOriginalCoinSellers>{
  String country='All',query='';
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Coin seller list'),actions:[
      IconButton(tooltip:'Seller directory status',
        icon:const Icon(Icons.refresh_rounded),
        onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Seller directory is awaiting a verified Sovera server connection.')))),
    ]),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const SizedBox(height:10),
      const Glass(tint:gold,child:Row(children:[
        Jewel(Icons.storefront_rounded,color:gold,size:53),
        SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Sovera coin sellers',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
          SizedBox(height:8),
          Text('Only owner-approved listings appear here.',
            style:TextStyle(fontSize:13,color:Colors.white60,height:1.4)),
        ])),
      ])),
      const SizedBox(height:19),
      TextField(onChanged:(v)=>setState(()=>query=v),
        decoration:InputDecoration(hintText:'Seller name or ID',
          prefixIcon:const Icon(Icons.search_rounded),
          suffixIcon:const Icon(Icons.arrow_forward_rounded),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(22)))),
      const SizedBox(height:17),
      Wrap(spacing:8,runSpacing:8,children:[
        for(final option in const ['All','Bangladesh','Oman','Saudi Arabia'])
          ChoiceChip(label:Text(option),selected:country==option,
            onSelected:(_)=>setState(()=>country=option)),
      ]),
      const SizedBox(height:22),
      const Glass(tint:gold,child:Column(children:[
        Icon(Icons.verified_user_outlined,color:gold,size:32),
        SizedBox(height:10),
        Text('Approved sellers will appear here.',
          textAlign:TextAlign.center,
          style:TextStyle(fontWeight:FontWeight.w700)),
        SizedBox(height:8),
        Text('The seller directory is not yet connected to the new Sovera server. '
          'The old test seller is deliberately not displayed.',
          textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Colors.white60)),
      ])),
      const SizedBox(height:16),
      TextButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(ctx)=>
        AlertDialog(title:const Text('Recharge support'),
          content:const Text('Recharge support is awaiting the verified Sovera server service. '
            'Do not send funds to unverified sellers.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))])),
        icon:const Icon(Icons.support_agent_rounded),
        label:const Text('Recharge support')),
    ]));
}
