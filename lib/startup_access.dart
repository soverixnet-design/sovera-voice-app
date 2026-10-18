import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> requestMicrophoneAccess() async {
  if (kIsWeb) return true;
  if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) return true;
  return (await Permission.microphone.request()).isGranted;
}
class MicrophoneAccessTile extends StatefulWidget {
  const MicrophoneAccessTile({super.key});
  @override State<MicrophoneAccessTile> createState()=>_MicrophoneAccessTileState();
}
class _MicrophoneAccessTileState extends State<MicrophoneAccessTile>{
 String status='Enable your microphone before joining a seat';bool busy=false;
 Future<void> request()async{
  if(busy)return;setState(()=>busy=true);
  try{final allowed=await requestMicrophoneAccess();if(mounted)setState(()=>status=allowed?'Microphone ready':'Microphone access is off. You can still listen.');}
  catch(_){if(mounted)setState(()=>status='Check microphone access in your phone settings.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Card(child:ListTile(leading:const Icon(Icons.mic_rounded),title:const Text('Microphone access'),subtitle:Text(status),trailing:TextButton(onPressed:busy?null:request,child:const Text('Enable'))));
}
class StartupAccess extends StatefulWidget{
 final Widget child;const StartupAccess({super.key,required this.child});
 @override State<StartupAccess> createState()=>_StartupAccessState();
}
class _StartupAccessState extends State<StartupAccess>{
 @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>showAccess());}
 Future<void> showAccess()async{
  if(kIsWeb)return;
  final prefs=await SharedPreferences.getInstance();
  if(!mounted||prefs.getBool('sovera_access_intro_v1')==true)return;
  await showDialog<void>(context:context,builder:(context)=>AlertDialog(title:const Text('Get ready for Sovera'),content:const Column(mainAxisSize:MainAxisSize.min,children:[Text('Set up your microphone now so you can speak when you take a seat. Your microphone stays off until you choose to speak.'),MicrophoneAccessTile(),Text('For profile and room photos, tap Choose photo to open your phone’s gallery picker. Only the photo you select is used.')]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Continue'))]));
  await prefs.setBool('sovera_access_intro_v1',true);
 }
 @override Widget build(BuildContext context)=>widget.child;
}
