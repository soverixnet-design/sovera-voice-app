import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'firebase_community.dart' show communityRequestId;

Future<void> reportSovera(BuildContext context,FirebaseProfileApi api,String kind,String id)async{
  var reason='',busy=false;String? error,pending;
  final requestId=communityRequestId();
  await showDialog<void>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setState)=>
    AlertDialog(title:Text('Report $kind'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(maxLength:500,maxLines:4,readOnly:pending!=null,
        decoration:const InputDecoration(labelText:'Tell us what happened'),
        onChanged:(value)=>reason=value.trim()),
      if(error!=null)Text(error!),
    ]),actions:[
      TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('Close')),
      FilledButton(onPressed:busy?null:()async{
        if(reason.length<3){setState(()=>error='Please enter at least 3 characters.');return;}
        pending??=reason;setState(()=>busy=true);
        try{
          await api.call('POST',suffix:'/community/report',fields:{
            'target_kind':kind,'target_id':id,'reason':pending,'request_id':requestId});
          if(context.mounted)Navigator.pop(context);
        }catch(e){if(context.mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not send. Retry.');}
        finally{if(context.mounted)setState(()=>busy=false);}
      },child:Text(busy?'Sending…':pending==null?'Send report':'Retry report')),
    ])));
}
class SoveraSafetyMenu extends StatelessWidget{
  final FirebaseProfileApi api;final String uid,name;final VoidCallback? changed;
  const SoveraSafetyMenu({super.key,required this.api,required this.uid,required this.name,this.changed});
  @override Widget build(BuildContext context){
    if(uid==api.uid)return const SizedBox.shrink();
    return PopupMenuButton<String>(tooltip:'Member options',onSelected:(value)async{
      if(value=='report'){await reportSovera(context,api,'user',uid);return;}
      final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:Text('Block $name?'),
        content:const Text('Hide their room messages and moments, and mute their room audio. You can unblock them in Settings.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Block'))]));
      if(confirmed!=true)return;
      try{
        await api.call('PUT',suffix:'/community/blocks/${Uri.encodeComponent(uid)}');
        changed?.call();
      }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
        e is ProfileApiError?e.message:'Could not block. Retry.')));}
    },itemBuilder:(_)=>const [
      PopupMenuItem(value:'report',child:Text('Report user')),
      PopupMenuItem(value:'block',child:Text('Block user')),
    ]);
  }
}
