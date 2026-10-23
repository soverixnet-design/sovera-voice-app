import 'dart:async';
import 'package:flutter/material.dart';
import 'firebase_rewards.dart' show RewardPodium;
import 'sovera_visuals.dart' show cyan,gold;

/// Runs once per signed-in app session. Home is not mounted behind the intro.
class RankingWelcomeGate extends StatefulWidget {
  final Future<Map<String,dynamic>> Function() load;
  final Widget child;
  const RankingWelcomeGate({super.key,required this.load,required this.child});
  @override State<RankingWelcomeGate> createState()=>_RankingWelcomeGateState();
}
class _RankingWelcomeGateState extends State<RankingWelcomeGate>{
  bool finished=false;
  int remaining=5;
  String period='weekly',metric='rich';
  List<Map<String,dynamic>> rows=[];
  Timer? timer;
  @override void initState(){super.initState();start();}
  Future<void> start()async{
    try{
      final result=await widget.load().timeout(const Duration(seconds:4));
      if(!mounted)return;
      final people=(result['items'] as List? ?? []).whereType<Map>().map((p)=>Map<String,dynamic>.from(p)).take(3).toList();
      if(result['enabled']!=true||people.isEmpty){finish();return;}
      setState((){rows=people;remaining=result['seconds']==10?10:5;period=result['period']?.toString()??'weekly';metric=result['metric']?.toString()??'rich';});
      timer=Timer.periodic(const Duration(seconds:1),(_){if(remaining<=1){finish();}else if(mounted){setState(()=>remaining--);}});
    }catch(_){finish();}
  }
  void finish(){timer?.cancel();if(mounted)setState(()=>finished=true);}
  @override void dispose(){timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    if(finished)return widget.child;
    final bangla=Localizations.localeOf(context).languageCode=='bn';
    return Scaffold(body:DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xff351876),Color(0xff11152c),Color(0xff123a49)])),child:SafeArea(child:LayoutBuilder(builder:(context,box)=>SingleChildScrollView(child:ConstrainedBox(constraints:BoxConstraints(minHeight:box.maxHeight),child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      const Icon(Icons.auto_awesome_rounded,color:gold,size:48),
      const SizedBox(height:16),
      Text(bangla?'সোভেরার সেরা তারকা':'SOVERA TOP STARS',textAlign:TextAlign.center,style:const TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:Colors.white)),
      const SizedBox(height:12),
      if(rows.isEmpty) const CircularProgressIndicator(color:cyan)
      else ...[
        Text(bangla?'সার্ভারের র‍্যাংকিংয়ের শীর্ষ ৩ জন':'Top 3 · $period · ${const {'rich':'Gift sending','charm':'Gift receiving','play':'Game wins','recharge':'Recharge'}[metric]??metric}',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70)),
        const SizedBox(height:28),
        RewardPodium(rows:rows,onTap:(_){}),
        const SizedBox(height:28),
        Text(bangla?'$remaining সেকেন্ড পর অ্যাপ খুলবে':'Opening Sovera in $remaining seconds',style:const TextStyle(color:cyan,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        TextButton(onPressed:finish,child:Text(bangla?'এখনই প্রবেশ করুন':'Enter now')),
      ],
    ]))))))));
  }
}
