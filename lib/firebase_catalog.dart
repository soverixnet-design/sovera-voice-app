import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'firebase_profile.dart';
import 'app_preferences.dart';
import 'sovera_visuals.dart' show BrandLogo;

Map<String,dynamic>? catalogAsset(dynamic equipped,String kind){
  if(equipped is! Map||equipped[kind] is! Map)return null;
  return Map<String,dynamic>.from(equipped[kind] as Map);
}
String catalogRequestId(){final r=Random.secure();final h=List.generate(16,(_)=>r.nextInt(256).toRadixString(16).padLeft(2,'0')).join();return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';}
class CatalogImage extends StatelessWidget{
  final Map<String,dynamic> asset;final BoxFit fit;final bool previewStill;
  const CatalogImage({super.key,required this.asset,this.fit=BoxFit.contain,this.previewStill=false});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<bool>(
    valueListenable:SoveraPreferences.lowData,builder:(context,lowData,child){
      final id=asset['media_id']?.toString()??'';
      if(CatalogMediaCache.valid(id))return CachedCatalogArtwork(id:id,
        still:previewStill||lowData||MediaQuery.disableAnimationsOf(context),fit:fit);
      return Image.network(asset['url'].toString(),fit:fit,gaplessPlayback:true,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined));
    });
}
/// One square coordinate system for profile, seat, entry and admin preview.
class CatalogPortraitGeometry {
  final double side;
  final Rect avatar;
  const CatalogPortraitGeometry(this.side,this.avatar);
  factory CatalogPortraitGeometry.forAsset(Map<String,dynamic>? asset,double side) {
    double number(dynamic value,double fallback,double low,double high) {
      final n=value is num?value.toDouble():fallback;
      return (n.isFinite?n:fallback).clamp(low,high).toDouble();
    }
    final scale=number(asset?['avatar_scale'],asset == null ? 0.72 : 0.46,.05,1);
    final radius=scale/2;
    final x=number(asset?['avatar_x'],.5,radius,1-radius);
    final y=number(asset?['avatar_y'],.5,radius,1-radius);
    final diameter=side*scale;
    return CatalogPortraitGeometry(side,Rect.fromLTWH(
      side*x-diameter/2,side*y-diameter/2,diameter,diameter));
  }
}
class CatalogPortrait extends StatelessWidget {
  final Map<String,dynamic>? asset;
  final String? avatarUrl;
  final double size;
  final bool still;
  const CatalogPortrait({super.key,this.asset,this.avatarUrl,this.size=100,this.still=false});
  @override Widget build(BuildContext context) {
    final requested=size.isFinite&&size>0?size:100.0;
    return SizedBox(width:requested,height:requested,child:LayoutBuilder(
      builder:(context,constraints) {
        final side=min(requested,min(constraints.maxWidth,constraints.maxHeight));
        final geometry=CatalogPortraitGeometry.forAsset(asset,side);
        final rect=geometry.avatar;
        return Center(child:SizedBox(width:side,height:side,
          child:Stack(key:const ValueKey('catalog-canvas'),children:[
            Positioned.fromRect(rect:rect,child:ClipOval(
              key:const ValueKey('catalog-avatar'),
              child:avatarUrl?.startsWith('https://')==true
                ?Image.network(avatarUrl!,fit:BoxFit.cover,
                  errorBuilder:(_,__,___)=>BrandLogo(size:rect.width))
                :BrandLogo(size:rect.width))),
            if(asset!=null)Positioned.fill(child:IgnorePointer(
              child:CatalogImage(key:ValueKey('${asset!['id']}:${asset!['media_id']}'),
                asset:asset!,previewStill:still))),
          ])));
      }));
  }
}
class FirebaseCatalogPage extends StatefulWidget{
  final FirebaseProfileApi api;final String initialKind;
  const FirebaseCatalogPage({super.key,required this.api,this.initialKind='frame'});
  @override State<FirebaseCatalogPage> createState()=>_FirebaseCatalogPageState();
}
class _FirebaseCatalogPageState extends State<FirebaseCatalogPage>{
  Map<String,dynamic>? data;String kind='frame';String? error;bool busy=false;Map<String,dynamic>? pending;
  @override void initState(){super.initState();kind=widget.initialKind;load();}
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
  void preview(Map<String,dynamic> item){
    showDialog<void>(context:context,builder:(context)=>AlertDialog(
      title:Text(item['title'].toString()),
      content:SizedBox(width:240,height:240,child:
        ['frame','entry','room_frame'].contains(item['kind'])
          ?CatalogPortrait(asset:item,size:240):CatalogImage(asset:item)),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))]));
  }
  Future<void> remove()async{
    setState(()=>busy=true);
    try{await widget.api.call('PUT',suffix:'/catalog/equip',fields:{'kind':kind,'item_id':null});await load();}
    catch(e){if(mounted)setState(()=>error=e is ProfileApiError?e.message:'Could not remove item. Retry.');}
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
      if(catalogAsset(data?['equipped'],kind)!=null)TextButton(onPressed:busy||pending!=null?null:remove,child:const Text('Remove equipped item')),
      for(final item in items)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        SizedBox(height:170,child:kind=='frame'||kind=='entry'||kind=='room_frame'?CatalogPortrait(asset:item,size:170,still:true):CatalogImage(asset:item,previewStill:true)),
        Text(item['title'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
        Text(owned.contains(item['id'])?'Owned · ${item['price']} Coins':'${item['price']} Coins · Locked'),
        TextButton.icon(onPressed:()=>preview(item),icon:const Icon(Icons.play_circle_outline),label:const Text('Preview animation')),
        FilledButton(onPressed:busy||(pending!=null&&pending!['item_id']!=item['id'])?null:()=>choose(item,owned.contains(item['id'])||item['price']==0),child:Text(pending?['item_id']==item['id']?'Retry same purchase':catalogAsset(data?['equipped'],kind)?['id']==item['id']?'Equipped':owned.contains(item['id'])||item['price']==0?'Equip':'Buy & equip')),
      ]))),
    ]))));
  }
}
class CatalogRoomAnimation extends StatefulWidget{
  final Map<String,dynamic> event;final int serverNow;final List<Map<String,dynamic>> recipients;
  const CatalogRoomAnimation({super.key,required this.event,required this.serverNow,this.recipients=const []});
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
      if(asset['kind']=='gift')Wrap(alignment:WrapAlignment.center,spacing:8,children:[for(final person in widget.recipients.take(6))Column(mainAxisSize:MainAxisSize.min,children:[CatalogPortrait(avatarUrl:person['avatar_url'] as String?,size:48),SizedBox(width:72,child:Text(person['recipient_name'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center))]),if(widget.recipients.length>6)Text('+${widget.recipients.length-6} recipients')]),
    ])));
  }
}
class FirebaseCatalogGiftPicker extends StatefulWidget{
  final List<Map<String,dynamic>> people,gifts;
  final FirebaseProfileApi api;
  const FirebaseCatalogGiftPicker({super.key,required this.api,required this.people,required this.gifts});
  @override State<FirebaseCatalogGiftPicker> createState()=>_FirebaseCatalogGiftPickerState();
}
class _FirebaseCatalogGiftPickerState extends State<FirebaseCatalogGiftPicker> with WidgetsBindingObserver{
  final selected=<String>{};Map<String,dynamic>? gift;
  BigInt? coins;
  bool loadingWallet=false,canGift=false;
  String? walletError;
  Timer? walletTimer;
  BigInt get total=>BigInt.from((gift?['price'] as num?)?.toInt()??0)*BigInt.from(selected.length);
  bool get canSend=>!loadingWallet&&walletError==null&&canGift&&coins!=null&&selected.isNotEmpty&&coins!>=total;
  Future<void> refreshWallet()async{
    if(loadingWallet)return;
    setState((){loadingWallet=true;coins=null;canGift=false;walletError=null;});
    try{
      final row=await widget.api.call('GET',suffix:'/wallet');
      final amount=row['coins'] is String?BigInt.tryParse(row['coins'] as String):null;
      if(row['source']!='sovera-server'||row['verified']!=true||amount==null||amount.isNegative)throw const ProfileApiError('Your wallet balance is unavailable.');
      if(mounted)setState((){coins=amount;canGift=row['status']=='active'&&row['canGift']==true;});
    }catch(_){if(mounted)setState(()=>walletError='Could not load your real Coins. Tap refresh.');}
    finally{if(mounted)setState(()=>loadingWallet=false);}
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)refreshWallet();}
  @override void dispose(){walletTimer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);refreshWallet();walletTimer=Timer.periodic(const Duration(seconds:15),(_)=>refreshWallet());if(widget.people.isNotEmpty)selected.add(widget.people.first['uid'].toString());if(widget.gifts.isNotEmpty)gift=widget.gifts.first;}
  @override Widget build(BuildContext context)=>SizedBox(
    height:MediaQuery.sizeOf(context).height*.78,
    child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
      Row(children:[const Expanded(child:Text('Gifts',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold))),
        TextButton(onPressed:()=>setState((){if(selected.length==widget.people.length){selected.clear();}else{selected.addAll(widget.people.map((p)=>p['uid'].toString()));}}),child:const Text('Select / clear all')),
        IconButton(tooltip:'Close gifts',onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))]),
      Row(children:[const Icon(Icons.monetization_on_rounded,color:Colors.amber,size:20),const SizedBox(width:6),
        Expanded(child:Text(loadingWallet?'Loading your Coins…':coins==null?'Coins unavailable':'Your Coins: $coins',key:const ValueKey('gift-wallet-balance'),style:const TextStyle(fontWeight:FontWeight.bold))),
        IconButton(tooltip:'Refresh Coins',onPressed:loadingWallet?null:refreshWallet,icon:const Icon(Icons.refresh,size:20)),
      ]),
      if(walletError!=null)Text(walletError!,style:const TextStyle(fontSize:11,color:Colors.orange)),
      if(coins!=null&&!canGift)const Text('Your wallet is not available for gifting.',style:TextStyle(fontSize:11,color:Colors.orange)),
      if(coins!=null&&canGift&&total>coins!)const Text('Not enough Coins for these recipients.',style:TextStyle(fontSize:11,color:Colors.orange)),
      SizedBox(height:83,child:ListView(scrollDirection:Axis.horizontal,children:[
        for(final person in widget.people)Padding(padding:const EdgeInsets.only(right:8),child:InkWell(
          onTap:()=>setState((){final uid=person['uid'].toString();if(!selected.add(uid))selected.remove(uid);}),
          child:Container(width:74,padding:const EdgeInsets.all(5),decoration:BoxDecoration(
            color:selected.contains(person['uid'])?const Color(0x555C52D8):Colors.transparent,
            borderRadius:BorderRadius.circular(14),border:Border.all(color:selected.contains(person['uid'])?Colors.cyanAccent:Colors.white12)),
            child:Column(children:[CatalogPortrait(avatarUrl:person['avatar_url'] as String?,size:38),
              Text(person['name'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10)),
              if(person['public_id']!=null)Text('ID ${person['public_id']}',style:const TextStyle(fontSize:9,color:Colors.white54))])))),
      ])),
      const SizedBox(height:12),
      Expanded(child:GridView.builder(itemCount:widget.gifts.length,
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,childAspectRatio:.9,crossAxisSpacing:8,mainAxisSpacing:8),
        itemBuilder:(context,index){final item=widget.gifts[index];final chosen=gift?['id']==item['id'];
          return InkWell(onTap:()=>setState(()=>gift=item),child:Container(padding:const EdgeInsets.all(7),
            decoration:BoxDecoration(color:chosen?const Color(0x444E3795):Colors.white.withValues(alpha:.04),
              borderRadius:BorderRadius.circular(14),border:Border.all(color:chosen?Colors.cyanAccent:Colors.white12)),
            child:Column(children:[Expanded(child:CatalogImage(asset:item,previewStill:!chosen)),
              Text(item['title'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
              Text('${item['price']} Coins',style:const TextStyle(fontSize:11,color:Colors.amberAccent))])));}),
      ),
      const SizedBox(height:10),
      if(gift!=null)Row(children:[Expanded(child:Text('Total: $total Coins',style:const TextStyle(fontWeight:FontWeight.bold))),
        FilledButton(onPressed:!canSend?null:()=>Navigator.pop(context,{'item_id':gift!['id'],'expected_price':gift!['price'],'recipient_uids':selected.toList()..sort()}),child:Text('Send · ${selected.length}'))]),
      const Text('Each recipient receives Diamonds equal to the gift price.',style:TextStyle(fontSize:10,color:Colors.white54)),
    ])));
}
