import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SoveraPreferences {
  static final lowData=ValueNotifier<bool>(false);
  static Future<void> load()async{
    try{lowData.value=(await SharedPreferences.getInstance()).getBool('sovera.lowData')??false;}catch(_){}
  }
  static Future<void> setLowData(bool value)async{
    await (await SharedPreferences.getInstance()).setBool('sovera.lowData',value);
    lowData.value=value;
  }
}
/// Only immutable public catalog media is cached; tokens and balances never are.
class CatalogMediaCache {
  static final pending=<String,Future<Uint8List>>{};
  static bool valid(String id)=>RegExp(r'^[0-9a-f]{64}$').hasMatch(id);
  static Directory get directory=>Directory('${Directory.systemTemp.path}/sovera-public-art-v1');
  static Future<Uint8List> load(String id,bool still){
    if(!valid(id))return Future.error(ArgumentError('Invalid media'));
    final key='$id-${still?'still':'motion'}';
    return pending.putIfAbsent(key,()=>read(id,still,key).whenComplete((){pending.remove(key);}));
  }
  static Future<Uint8List> read(String id,bool still,String key)async{
    final dir=directory;
    await dir.create(recursive:true);
    final file=File('${dir.path}/$key');
    if(await file.exists()){
      final bytes=await file.readAsBytes();
      if(bytes.isNotEmpty)return bytes;
    }
    final uri=Uri.https('voice.soverixnet.com','/sovera/account/media/$id',
      still?{'still':'true'}:null);
    final response=await http.get(uri).timeout(const Duration(seconds:20));
    if(response.statusCode!=200||response.bodyBytes.isEmpty||response.bodyBytes.length>8*1024*1024){
      throw StateError('Artwork unavailable');
    }
    final part=File('${file.path}.part');
    await part.writeAsBytes(response.bodyBytes,flush:true);
    await part.rename(file.path);
    unawaited(trim());
    return response.bodyBytes;
  }
  static Future<void> trim()async{
    try{
      final files=await directory.list().where((x)=>x is File&&!x.path.endsWith('.part')).cast<File>().toList();
      final sizes=<File,FileStat>{};
      for(final file in files){sizes[file]=await file.stat();}
      files.sort((a,b)=>sizes[a]!.modified.compareTo(sizes[b]!.modified));
      var total=sizes.values.fold<int>(0,(sum,s)=>sum+s.size);
      for(final file in files){
        if(total<=50*1024*1024)break;
        total-=sizes[file]!.size;await file.delete();
      }
    }catch(_){}
  }
  static Future<void> evict(String id,bool still)async{
    final file=File('${directory.path}/$id-${still?'still':'motion'}');
    if(await file.exists())await file.delete();
  }
  static Future<void> clear()async{
    await Future.wait(pending.values.map((f)=>f.then<void>((_){}).catchError((Object _){})).toList());
    if(await directory.exists())await directory.delete(recursive:true);
  }
}
class CachedCatalogArtwork extends StatefulWidget {
  final String id;final bool still;final BoxFit fit;
  const CachedCatalogArtwork({super.key,required this.id,required this.still,this.fit=BoxFit.contain});
  @override State<CachedCatalogArtwork> createState()=>_CachedCatalogArtworkState();
}
class _CachedCatalogArtworkState extends State<CachedCatalogArtwork>{
  late Future<Uint8List> bytes;
  @override void initState(){super.initState();reload();}
  void reload(){bytes=CatalogMediaCache.load(widget.id,widget.still);}
  @override void didUpdateWidget(covariant CachedCatalogArtwork oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.id!=widget.id||oldWidget.still!=widget.still)reload();
  }
  Future<void> retry()async{
    await CatalogMediaCache.evict(widget.id,widget.still);
    if(mounted)setState(reload);
  }
  Widget failed()=>IconButton(tooltip:'Retry artwork',onPressed:retry,icon:const Icon(Icons.refresh));
  @override Widget build(BuildContext context)=>FutureBuilder<Uint8List>(
    future:bytes,builder:(context,snapshot){
      if(snapshot.hasError)return failed();
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      return Image.memory(snapshot.data!,fit:widget.fit,gaplessPlayback:true,errorBuilder:(_,__,___)=>failed());
    });
}
class SoveraSettingsPage extends StatefulWidget{
  final VoidCallback support,blocked;
  const SoveraSettingsPage({super.key,required this.support,required this.blocked});
  @override State<SoveraSettingsPage> createState()=>_SoveraSettingsPageState();
}
class _SoveraSettingsPageState extends State<SoveraSettingsPage>{
  bool busy=false;String? message;
  Future<void> change(bool value)async{
    setState(()=>busy=true);
    try{await SoveraPreferences.setLowData(value);}
    catch(_){if(mounted)setState(()=>message='Could not save this setting. Retry.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> clear()async{
    setState(()=>busy=true);
    try{await CatalogMediaCache.clear();if(mounted)setState(()=>message='Downloaded artwork cleared.');}
    catch(_){if(mounted)setState(()=>message='Could not clear artwork. Retry.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Settings')),
    body:ListView(children:[
      ValueListenableBuilder<bool>(valueListenable:SoveraPreferences.lowData,builder:(context,value,child)=>
        SwitchListTile(title:const Text('Low data mode'),
          subtitle:const Text('Smaller still artwork and fewer automatic home updates. Voice quality stays the same.'),
          value:value,onChanged:busy?null:change)),
      ListTile(leading:const Icon(Icons.cleaning_services_outlined),title:const Text('Clear downloaded artwork'),onTap:busy?null:clear),
      ListTile(leading:const Icon(Icons.block),title:const Text('Blocked users'),onTap:widget.blocked),
      ListTile(leading:const Icon(Icons.support_agent),title:const Text('Official support'),onTap:widget.support),
      if(message!=null)Padding(padding:const EdgeInsets.all(16),child:Text(message!)),
    ]));
}
