import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'firebase_profile.dart';

/// The actual user-provided Food Wheel HTML, embedded in an isolated WebView.
/// JavaScript receives only verified server state, never a Firebase bearer token.
class FirebaseFoodWheelView extends StatefulWidget {
  final FirebaseProfileApi api;
  final bool inside;
  const FirebaseFoodWheelView({super.key,required this.api,this.inside=false});
  @override State<FirebaseFoodWheelView> createState()=>_FirebaseFoodWheelViewState();
}
class _FirebaseFoodWheelViewState extends State<FirebaseFoodWheelView>{
  late final WebViewController controller;
  String? error;
  bool loaded=false;
  @override void initState(){
    super.initState();
    controller=WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF009E92))
      ..setNavigationDelegate(NavigationDelegate(
        // No remote JavaScript is permitted to obtain this privileged bridge.
        onNavigationRequest:(request){
          final url=request.url;
          if(url.startsWith('file:///android_asset/flutter_assets/')||
             url.startsWith('file:///')||
             url.startsWith('about:blank')||
             url.startsWith('http://localhost/')){
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageFinished:(_){
          if(!mounted)return;
          setState(()=>loaded=true);
          controller.runJavaScript("window.setWheelMode('${widget.inside?'inside':'full'}');");
        },
        onWebResourceError:(issue){
          if(issue.isForMainFrame==true&&mounted){
            setState(()=>error='Could not load the original Food Wheel artwork.');
          }
        },
      ))
      ..addJavaScriptChannel('SoveraWheelBridge',
        onMessageReceived:(message)=>handle(message.message));
    controller.loadFlutterAsset('assets/games/food-wheel.html');
  }
  static const foods={
    'chicken','fish','hotdog','steak',
    'grapes','lettuce','pepper','melon',
  };
  Future<void> handle(String text)async{
    if(!mounted||text.length>512)return;
    Object? decoded;
    try{decoded=jsonDecode(text);}catch(_){return;}
    if(decoded is! Map)return;
    final id=decoded['id'];
    final op=decoded['op'];
    if(id is! int||id<1||id>1000000000||op is! String)return;
    if(op=='expand'){
      if(widget.inside) {
        Navigator.of(context).push<void>(MaterialPageRoute(
          builder:(_)=>FirebaseFoodWheelPage(api:widget.api)));
      }else if(Navigator.of(context).canPop()){
        Navigator.of(context).pop();
      }
      return;
    }
    Map<String,dynamic> response;
    try{
      Map<String,dynamic> data;
      if(op=='state'){
        data=await widget.api.call('GET',suffix:'/wheel/state');
      }else if(op=='pick'){
        final body=decoded['payload'];
        if(body is! Map||body.length!=2||
            body['round'] is! int||body['round']<1||
            body['item'] is! String||!foods.contains(body['item'])){
          throw const ProfileApiError('Invalid food selection.');
        }
        data=await widget.api.call('POST',suffix:'/wheel/pick',fields:{
          'round':body['round'],'item':body['item'],
        });
      }else{
        throw const ProfileApiError('Unsupported game action.');
      }
      response={'id':id,'ok':true,'data':data};
    }catch(e){
      response={'id':id,'ok':false,
        'error':e is ProfileApiError?e.message:'Game server unavailable. Please retry.'};
    }
    if(mounted){
      await controller.runJavaScript(
        'window.soveraReceive(${jsonEncode(response)});');
    }
  }
  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned.fill(child:WebViewWidget(controller:controller)),
    if(!loaded)const Center(child:CircularProgressIndicator()),
    if(error!=null)Positioned(left:8,right:8,top:8,
      child:Text(error!,style:const TextStyle(color:Colors.orangeAccent))),
  ]);
}

class FirebaseFoodWheelPage extends StatelessWidget {
  final FirebaseProfileApi api;
  const FirebaseFoodWheelPage({super.key,required this.api});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Food Wheel · Same live round')),
    body:SafeArea(child:FirebaseFoodWheelView(api:api)),
  );
}
