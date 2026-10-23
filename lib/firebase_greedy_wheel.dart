import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'firebase_rewards.dart';
import 'sovera_icons.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'firebase_profile.dart';
import 'firebase_server_wallet.dart';

/// Original user-supplied Greedy UI is hosted by the isolated Greedy service.
/// It MUST be fetched from the configured verified HTTPS game endpoint; no
/// fake results, locally minted coins or unverified wallet are allowed.
class FirebaseGreedyWheelPage extends StatefulWidget {
  final FirebaseProfileApi api;
  final bool inRoom;
  const FirebaseGreedyWheelPage({super.key,required this.api,this.inRoom=false});
  @override State<FirebaseGreedyWheelPage> createState()=>_FirebaseGreedyWheelPageState();
}

class _FirebaseGreedyWheelPageState extends State<FirebaseGreedyWheelPage>{
  WebViewController? controller;
  bool loading=true;
  String? error;
  bool refreshingGameAccess=false;
  Future<void> showRanking()async{
    await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>
      FirebaseRewardsPage(api:widget.api,initialMetric:'play',initialPeriod:'daily')));
  }

  bool walletOpen=false;

  Future<void> openWallet()async{
    if(walletOpen||!mounted)return;
    walletOpen=true;
    try{
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder:(_)=>FirebaseServerWalletPage(api:widget.api)));
      if(mounted)await refreshGameAccess();
    }finally{walletOpen=false;}
  }

  /// Short-lived game JWTs are refreshed through the authenticated Firebase
  /// account API, never with a game-host password or a coin balance from JS.
  Future<void> refreshGameAccess()async{
    if(refreshingGameAccess||!mounted||controller==null)return;
    refreshingGameAccess=true;
    try{
      final reply=await widget.api.call('POST',suffix:'/greedy/access');
      final token=reply['token'],endpoint=reply['game_url'];
      if(token is! String||token.isEmpty||endpoint is! String){
        throw const ProfileApiError('Invalid game credentials');
      }
      final url=Uri.tryParse(endpoint);
      if(url==null||url.scheme!='https'||url.host!='voice.soverixnet.com'||
          url.path!='/greedy/'||url.hasQuery||url.hasFragment){
        throw const ProfileApiError('Unverified game server');
      }
      final payload=jsonEncode({
        'server':'https://voice.soverixnet.com/greedy','token':token,
      });
      if(mounted)await controller!.runJavaScript(
        'if(window.GreedyGame){window.GreedyGame.connect($payload);}');
    }catch(_){
      if(mounted)setState(()=>error=
        'Game session expired and could not refresh. Your Coins are unchanged.');
    }finally{refreshingGameAccess=false;}
  }
  @override void dispose(){
    final game=controller;
    controller=null;
    if(game!=null){
      // Tear down the game document, including WebAudio, timers and sockets.
      // This controller owns only the game; the room voice connection is separate.
      game.loadRequest(Uri.parse('about:blank')).catchError((Object _){});
    }
    super.dispose();
  }
  @override void initState(){super.initState();open();}
  Future<void> open()async{
    setState((){loading=true;error=null;});
    try{
      // Firebase ID token is used ONLY to call the authenticated account API.
      // The backend mints a separate 5-minute game-only JWT after verifying
      // both the account profile and the production wallet integration.
      final reply=await widget.api.call('POST',suffix:'/greedy/access');
      final token=reply['token'], endpoint=reply['game_url'];
      if(token is! String||token.isEmpty||endpoint is! String) {
        throw const ProfileApiError('Invalid secure game response');
      }
      final url=Uri.tryParse(endpoint);
      if(url==null||url.scheme!='https'||url.host!='voice.soverixnet.com'||
          url.path!='/greedy/'||url.hasQuery||url.hasFragment){
        throw const ProfileApiError('Unexpected Greedy game server');
      }
      late final WebViewController ctl;
      ctl=WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF1A0E2B))
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest:(request){
            if(request.url=='about:blank')return NavigationDecision.navigate;
            final target=Uri.tryParse(request.url);
            return target!=null&&target.scheme=='https'&&
                  target.host==url.host&&target.path.startsWith('/greedy/')
                ?NavigationDecision.navigate:NavigationDecision.prevent;
          },
          onPageFinished:(_)async{
            final englishUI=await rootBundle.loadString('assets/games/english-ui.js');
            await ctl.runJavaScript(englishUI);
            // Never put game JWT in navigation URL, access logs, crash logs,
            // Flutter widget labels or Firebase token storage.
            final payload=jsonEncode({'server':'https://voice.soverixnet.com/greedy',
              'token':token});
            await ctl.runJavaScript(
              "if(window.GreedyGame){window.GreedyGame.connect($payload);}"
            );
          },
          onWebResourceError:(event){
            if(event.isForMainFrame==true&&mounted){
              setState(()=>error='Greedy game host is not reachable.');
            }
          },
        ))
        ..addJavaScriptChannel('GreedyFlutter',onMessageReceived:(event){
          try{
            final message=jsonDecode(event.message);
            if(message is Map&&message['type']=='close'&&mounted){
              Navigator.of(context).maybePop();
            }
            if(message is Map&&message['type']=='auth_failed'&&mounted){
              refreshGameAccess();
            }
            if(message is Map&&message['type']=='topup'&&mounted){
              openWallet();
            }
          }catch(_){}
        });
      await ctl.loadRequest(url);
      if(mounted){setState((){controller=ctl;loading=false;});}
      else{await ctl.loadRequest(Uri.parse('about:blank'));}
    }catch(e){
      if(mounted)setState((){
        error='Greedy Wheel server and Sovera coin wallet have not been verified together yet. No fake coins or bets will run.';
        loading=false;
      });
    }
  }
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFF160C27),
    appBar:widget.inRoom?AppBar(title:const Text('Greedy · Room game'),actions:[IconButton(onPressed:showRanking,icon:const SoveraIcon(Icons.emoji_events_rounded,size:32),tooltip:'Game wins ranking')]):
      AppBar(title:const Text('Greedy Wheel'),actions:[IconButton(onPressed:showRanking,icon:const SoveraIcon(Icons.emoji_events_rounded,size:32),tooltip:'Game wins ranking')]),
    body:SafeArea(child:Column(children:[
      Expanded(child:Stack(children:[
      if(controller!=null&&error==null)Positioned.fill(
        child:WebViewWidget(controller:controller!)),
      if(loading)const Center(child:CircularProgressIndicator()),
      if(error!=null)Center(child:Padding(padding:const EdgeInsets.all(24),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.shield_outlined,size:48,color:Colors.amberAccent),
          const SizedBox(height:12),
          Text(error!,textAlign:TextAlign.center),
          const SizedBox(height:12),
          const Text('Coins are protected. The same verified game can open in or outside a voice room after server wallet connection.',
            textAlign:TextAlign.center,
            style:TextStyle(fontSize:12,color:Colors.white70)),
          const SizedBox(height:16),
          FilledButton.icon(onPressed:open,icon:const Icon(Icons.refresh),
            label:const Text('Retry secure connection')),
        ]))),
    ])),
    ])),
  );
}
