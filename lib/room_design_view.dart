import 'firebase_profile.dart' show ProfileApiError;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Local presentation only. Tokens and wallet mutations stay in native code.
class RoomDesignView extends StatefulWidget {
  final Map<String,dynamic> snapshot;
  final Future<void> Function(Map<String,dynamic>) onAction;
  const RoomDesignView({super.key,required this.snapshot,required this.onAction});
  @override State<RoomDesignView> createState()=>_RoomDesignViewState();
}
class _RoomDesignViewState extends State<RoomDesignView>{
  late final WebViewController controller;
  bool ready=false;
  String? error;
  @override void initState(){
    super.initState();
    controller=WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff0a0820))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest:(r)=>r.url.startsWith('file:')&&r.url.endsWith('/assets/room-design/interior.html')?NavigationDecision.navigate:NavigationDecision.prevent,
        onPageFinished:(_){ready=true;publish();},
      ))
      ..addJavaScriptChannel('SoveraRoom',onMessageReceived:(event)async{
        try{
          if(event.message.length>4096)return;
          final data=jsonDecode(event.message);
          if(data is! Map)return;
          if(mounted)setState(()=>error=null);
          await widget.onAction(Map<String,dynamic>.from(data));
        }catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Room action failed. Check your connection and try again.');}
      })
      ..loadFlutterAsset('assets/room-design/interior.html');
  }
  @override void didUpdateWidget(covariant RoomDesignView old){super.didUpdateWidget(old);publish();}
  Future<void> publish()async{
    if(!ready)return;
    try{await controller.runJavaScript('window.SoveraLive?.update(${jsonEncode(widget.snapshot)});');}
    catch(_){if(mounted)setState(()=>error='Room display could not update.');}
  }
  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned.fill(child:WebViewWidget(controller:controller)),
    if(error!=null)Align(alignment:Alignment.topCenter,child:Material(color:Colors.red.shade900,child:Padding(padding:const EdgeInsets.all(8),child:Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(error!)),IconButton(tooltip:'Dismiss',onPressed:()=>setState(()=>error=null),icon:const Icon(Icons.close,color:Colors.white))])))),
  ]);
}
