import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'sovera_visuals.dart' show BrandLogo;

Map<String,dynamic>? catalogAsset(dynamic equipped,String kind){
  if(equipped is! Map||equipped[kind] is! Map)return null;
  return Map<String,dynamic>.from(equipped[kind] as Map);
}
String catalogRequestId(){final r=Random.secure();final h=List.generate(16,(_)=>r.nextInt(256).toRadixString(16).padLeft(2,'0')).join();return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';}
class CatalogImage extends StatelessWidget{
  final Map<String,dynamic> asset;final BoxFit fit;
  const CatalogImage({super.key,required this.asset,this.fit=BoxFit.contain});
  @override Widget build(BuildContext context)=>Image.network(asset['url'].toString(),fit:fit,gaplessPlayback:true,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined));
}
/// Admin preview and app share normalized avatar size and center coordinates.
class CatalogPortrait extends StatelessWidget{
  final Map<String,dynamic>? asset;final String? avatarUrl;final double size;
  const CatalogPortrait({super.key,this.asset,this.avatarUrl,this.size=100});
  @override Widget build(BuildContext context){
    final scale=(asset?['avatar_scale'] as num?)?.toDouble()??.72;
    final x=(asset?['avatar_x'] as num?)?.toDouble()??.5;
    final y=(asset?['avatar_y'] as num?)?.toDouble()??.5;
    final diameter=size*scale;
    return SizedBox(width:size,height:size,child:Stack(clipBehavior:Clip.none,children:[
      Positioned(left:size*x-diameter/2,top:size*y-diameter/2,width:diameter,height:diameter,
        child:ClipOval(child:avatarUrl?.startsWith('https://')==true?Image.network(avatarUrl!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>BrandLogo(size:diameter)):BrandLogo(size:diameter))),
      if(asset!=null)Positioned.fill(child:IgnorePointer(child:CatalogImage(asset:asset!))),
    ]));
  }
}
class FirebaseCatalogPage extends StatefulWidget{
  final FirebaseProfileApi api;
  const FirebaseCatalogPage({super.key,required this.api});
  @override State<FirebaseCatalogPage> createState()=>_FirebaseCatalogPageState();
}
class _FirebaseCatalogPageState extends State<FirebaseCatalogPage>{
  Map<String,dynamic>? data;String kind='frame';String? error;bool busy=false;Map<String,dynamic>? pending;
  @override void initState(){super.initState();load();}
  Future<void> load()async{try{final value=await widget.api.call('GET',suffix:'/catalog');if(mounted)setState(()=>data=value);}catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not load catalog.');}}
  Future<void> choose(Map<String,dynamic> item,bool owned)async{
    if(busy)return;
    if(!owned&&pending==null){
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('Buy ${item['title']}?'),content:Text('${item['price']} Coins will be charged once. Your wallet must be verified.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Buy'))]));
      if(yes!=true)return;
    }
    if(!mounted)return;setState(()=>busy=true);
    try{
      if(!owned||pending!=null){pending??={'item_id':item['id'],'expected_price':item['price'],'request_id':catalogRequestId()};await widget.api.call('POST',suffix:'/catalog/purchase',fields:pending);pending=null;}
      await widget.api.call('PUT',suffix:'/catalog/equip',fields:{'kind':item['kind'],'item_id':item['id']});
      await load();if(mounted)setState(()=>error='Equipped successfully.');
    }catch(e){if(e is ProfileApiError&&e.status==409)pending=null;if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not save. Retry the same item.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final items=((data?['items'] as List?)??[]).whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).where((r)=>r['kind']==kind).toList();
    final owned=(data?['owned'] as List?)??[];
    return Scaffold(appBar:AppBar(title:const Text('My frames & entries')),body:SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      Wrap(spacing:7,children:[for(final k in const ['frame','entry','medal','tag','room_frame'])ChoiceChip(label:Text(k.replaceAll('_',' ')),selected:kind==k,onSelected:busy||pending!=null?null:(_)=>setState(()=>kind=k))]),
      if(data==null&&error==null)const LinearProgressIndicator(),
      if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!)),
      if(data!=null&&items.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No published items yet. Pull down to refresh.')),
      if(catalogAsset(data?['equipped'],kind)!=null)TextButton(onPressed:busy||pending!=null?null:()async{await widget.api.call('PUT',suffix:'/catalog/equip',fields:{'kind':kind,'item_id':null});await load();},child:const Text('Remove equipped item')),
      for(final item in items)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        SizedBox(height:170,child:kind=='frame'||kind=='entry'||kind=='room_frame'?CatalogPortrait(asset:item,size:170):CatalogImage(asset:item)),
        Text(item['title'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
        Text('${item['price']} Coins'),
        FilledButton(onPressed:busy||(pending!=null&&pending!['item_id']!=item['id'])?null:()=>choose(item,owned.contains(item['id'])||item['price']==0),child:Text(pending?['item_id']==item['id']?'Retry same purchase':catalogAsset(data?['equipped'],kind)?['id']==item['id']?'Equipped':owned.contains(item['id'])||item['price']==0?'Equip':'Buy & equip')),
      ]))),
    ]))));
  }
}
class CatalogRoomAnimation extends StatefulWidget{
  final Map<String,dynamic> event;final int serverNow;
  const CatalogRoomAnimation({super.key,required this.event,required this.serverNow});
  @override State<CatalogRoomAnimation> createState()=>_CatalogRoomAnimationState();
}
class _CatalogRoomAnimationState extends State<CatalogRoomAnimation>{
  Timer? timer;bool visible=true;
  @override void initState(){super.initState();final seconds=((widget.event['created_at'] as num).toInt()+15-widget.serverNow).clamp(0,15).toInt();timer=Timer(Duration(seconds:seconds),(){if(mounted)setState(()=>visible=false);});}
  @override void dispose(){timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    if(!visible)return const SizedBox.shrink();
    final asset=Map<String,dynamic>.from(widget.event['asset'] as Map);
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Text('${widget.event['sender_name']} → ${widget.event['recipient_name']}',maxLines:1,overflow:TextOverflow.ellipsis),
      SizedBox(height:210,child:asset['kind']=='entry'?CatalogPortrait(asset:asset,avatarUrl:widget.event['avatar_url'] as String?,size:210):Stack(alignment:Alignment.center,children:[Positioned(right:8,bottom:4,child:CatalogPortrait(avatarUrl:widget.event['avatar_url'] as String?,size:65)),TweenAnimationBuilder<double>(tween:Tween(begin:0,end:1),duration:const Duration(milliseconds:1000),builder:(context,t,child)=>Transform.translate(offset:Offset(50*t,20*t),child:Transform.scale(scale:1-.3*t,child:child)),child:CatalogImage(asset:asset))])),
      Text(asset['title'].toString()),
    ])));
  }
}
class FirebaseCatalogGiftPicker extends StatefulWidget{
  final List<Map<String,dynamic>> people,gifts;
  const FirebaseCatalogGiftPicker({super.key,required this.people,required this.gifts});
  @override State<FirebaseCatalogGiftPicker> createState()=>_FirebaseCatalogGiftPickerState();
}
class _FirebaseCatalogGiftPickerState extends State<FirebaseCatalogGiftPicker>{
  final selected=<String>{};Map<String,dynamic>? gift;
  @override void initState(){super.initState();if(widget.people.isNotEmpty)selected.add(widget.people.first['uid'].toString());if(widget.gifts.isNotEmpty)gift=widget.gifts.first;}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Animated gifts'),content:SizedBox(width:360,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextButton(onPressed:()=>setState((){if(selected.length==widget.people.length){selected.clear();}else{selected.addAll(widget.people.map((p)=>p['uid'].toString()));}}),child:const Text('Select / clear all')),
    for(final person in widget.people)CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,title:Text(person['name'].toString()),subtitle:Text(person['uid'].toString(),style:const TextStyle(fontSize:10)),value:selected.contains(person['uid']),onChanged:(yes)=>setState((){if(yes==true){selected.add(person['uid'].toString());}else{selected.remove(person['uid']);}})),
    Wrap(spacing:8,children:[for(final item in widget.gifts)SizedBox(width:125,child:InkWell(onTap:()=>setState(()=>gift=item),child:Card(color:gift?['id']==item['id']?const Color(0xFF66419B):null,child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[SizedBox(height:85,child:CatalogImage(asset:item)),Text(item['title'].toString(),maxLines:1,overflow:TextOverflow.ellipsis),Text('${item['price']} Coins')])))))]),
    if(gift!=null)Text('Total: ${(gift!['price'] as num)*selected.length} Coins · ${selected.length} recipient(s)'),
    const Text('Paid gifts award each recipient Diamonds equal to the gift price. Free gifts award no Diamonds.',style:TextStyle(fontSize:11)),
  ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:gift==null||selected.isEmpty?null:()=>Navigator.pop(context,{'item_id':gift!['id'],'expected_price':gift!['price'],'recipient_uids':selected.toList()..sort()}),child:const Text('Confirm gift'))]);
}
