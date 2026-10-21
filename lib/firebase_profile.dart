import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'country_picker.dart';

class ProfileApiError implements Exception {
  final String message;
  final int? status;
  const ProfileApiError(this.message,{this.status});
}

class FirebaseProfileApi {
  final String uid;
  final Future<String?> Function() token;
  final http.Client client;
  FirebaseProfileApi({required this.uid, required this.token, required this.client});
  static final endpoint = Uri.parse('https://voice.soverixnet.com/sovera/account');

  Future<Map<String, dynamic>> call(String method, {String suffix='', Map<String,dynamic>? fields}) async {
    final access = await token();
    if (access == null || access.isEmpty) throw const ProfileApiError('Please sign in again.');
    final route = Uri.parse('${endpoint.path}$suffix');
    final req = http.Request(method, endpoint.replace(path:route.path,query:route.hasQuery?route.query:null))..followRedirects = false;
    req.headers.addAll({'Authorization': 'Bearer $access', 'Content-Type': 'application/json','X-Sovera-Client':'Sovera Android/iOS 0.19.0'});
    if (fields != null) req.body = jsonEncode(fields);
    final response = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 15)))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) throw const ProfileApiError('Your session expired. Sign out and sign in again.');
    if(response.statusCode==403){String detail='Access is unavailable.';try{final body=jsonDecode(response.body);if(body is Map&&body['detail'] is String)detail=body['detail'] as String;}catch(_){}throw ProfileApiError(detail,status:403);}
    if(response.statusCode==429) throw const ProfileApiError('Please wait a moment before sending again.');
    if(response.statusCode==409 && response.body.contains('Save your profile first')) throw const ProfileApiError('Save your profile before opening a room.');
    if(response.statusCode==409){String detail='Request could not be completed.';try{final body=jsonDecode(response.body);if(body is Map&&body['detail'] is String)detail=body['detail'] as String;}catch(_){}throw ProfileApiError(detail,status:409);}
    if (response.statusCode != 200) throw const ProfileApiError('Profile could not be saved or loaded. Please retry.');
    final data = jsonDecode(response.body);
    if(data is! Map) throw const ProfileApiError('Invalid server response. Please retry.');
    return Map<String,dynamic>.from(data);
  }
  Future<Map<String, dynamic>?> request(String method, [Map<String,dynamic>? fields]) async {
    final data=await call(method,fields:fields);
    if (!data.containsKey('profile')) throw const ProfileApiError('Invalid profile response. Please retry.');
    final row = data['profile'];
    if (row == null && method == 'GET') return null;
    if (row is! Map || row['firebase_uid'] != uid || row['display_name'] is! String || row['country'] is! String) {
      throw const ProfileApiError('Invalid profile response. Please retry.');
    }
    return Map<String, dynamic>.from(row);
  }
  Future<String> uploadAvatar(XFile image) => uploadPhoto(image);
  Future<String> uploadPhoto(XFile image,{String suffix='/avatar'}) async {
    final access = await token();
    if (access == null || access.isEmpty) throw const ProfileApiError('Please sign in again.');
    if (await image.length() > 8 * 1024 * 1024) throw const ProfileApiError('Choose a photo smaller than 8 MB.');
    final request = http.Request('POST', endpoint.replace(path:'${endpoint.path}$suffix'))..followRedirects=false;
    request.headers.addAll({'Authorization':'Bearer $access','Content-Type':'application/octet-stream'});
    request.bodyBytes = await image.readAsBytes();
    final response = await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds:30))).timeout(const Duration(seconds:30));
    if (response.statusCode != 200) throw const ProfileApiError('Photo could not be uploaded. Please retry.');
    final data = jsonDecode(response.body);
    final url = data is Map ? data['avatar_url'] : null;
    if (url is! String || !(url.startsWith('${endpoint.toString()}/avatar/')||url.startsWith('${endpoint.toString()}/room-photo/'))) throw const ProfileApiError('Invalid photo response.');
    return url;
  }
  Future<Map<String, dynamic>?> load() => request('GET');
  Future<Map<String, dynamic>?> save({required String name, required String country, required String bio, String? avatarUrl, String? gender, String? birthday}) =>
      request('PUT', {'display_name':name.trim(), 'country':country, 'bio':bio.trim(), 'avatar_url':avatarUrl, 'gender':gender, 'birthday':birthday});
}

class FirebaseProfileEditor extends StatefulWidget {
  final FirebaseProfileApi api;
  final String initialName;
  final VoidCallback? onSaved;
  const FirebaseProfileEditor({
    super.key,required this.api,this.initialName='',this.onSaved,
  });
  @override State<FirebaseProfileEditor> createState() => _FirebaseProfileEditorState();
}
class _FirebaseProfileEditorState extends State<FirebaseProfileEditor> {
  final name=TextEditingController(), bio=TextEditingController();
  String country='';
  String? avatarUrl, gender, birthday;
  String? message;
  bool busy=true, loaded=false;
  @override void initState() { super.initState(); load(); }
  @override void dispose() { name.dispose(); bio.dispose(); super.dispose(); }
  String error(Object e) => e is ProfileApiError ? e.message : 'Could not connect. Check your internet and retry.';
  Future<void> load() async {
    setState(() { busy=true; message=null; });
    try {
      final row=await widget.api.load();
      if (!mounted) return;
      name.text=(row?['display_name'] as String?)??widget.initialName;
      bio.text=(row?['bio'] as String?)??'';
      avatarUrl=row?['avatar_url'] as String?;
      gender=row?['gender'] as String?;
      birthday=row?['birthday'] as String?;
      setState(() { country=(row?['country'] as String?)??''; loaded=true; });
    } catch(e) { if(mounted) setState(() => message=error(e)); }
    finally { if(mounted) setState(() => busy=false); }
  }
  Future<void> save() async {
    if(busy || !loaded) return;
    if(name.text.trim().isEmpty || !soveraCountries.containsKey(country)) {
      setState(() => message='Enter your display name and choose your country.'); return;
    }
    setState(() { busy=true; message=null; });
    try {
      final row=await widget.api.save(name:name.text,country:country,bio:bio.text,avatarUrl:avatarUrl,gender:gender,birthday:birthday);
      if(!mounted) return;
      name.text=row!['display_name'] as String;
      bio.text=(row['bio'] as String?)??'';
      setState(() { country=row['country'] as String; message='Profile saved to your server.'; });
      widget.onSaved?.call();
    } catch(e) { if(mounted) setState(() => message=error(e)); }
    finally { if(mounted) setState(() => busy=false); }
  }
  Future<void> choosePhoto() async {
    if (busy) return;
    try {
      final image = await ImagePicker().pickImage(source:ImageSource.gallery,maxWidth:1024,maxHeight:1024,imageQuality:85);
      if (image == null || !mounted) return;
      setState(() { busy=true; message=null; });
      final url=await widget.api.uploadAvatar(image);
      if (mounted) setState(() { avatarUrl=url; message='Photo selected. Tap Save profile to apply.'; });
    } catch(e) { if(mounted) setState(()=>message=error(e)); }
    finally { if(mounted) setState(()=>busy=false); }
  }
  Future<void> chooseBirthday() async {
    final selected=await showDatePicker(context:context,initialDate:DateTime.tryParse(birthday??'')??DateTime(2000),firstDate:DateTime(1900),lastDate:DateTime.now());
    if(selected!=null && mounted) setState(()=>birthday=selected.toIso8601String().substring(0,10));
  }
  @override Widget build(BuildContext context) => Card(child:Padding(
    padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Your profile',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      if(busy) const LinearProgressIndicator(),
      if(loaded)...[
        Center(child:Column(children:[
          CircleAvatar(radius:48,child:avatarUrl==null?const Icon(Icons.person,size:48):ClipOval(child:Image.network(avatarUrl!,width:96,height:96,fit:BoxFit.cover,errorBuilder:(_,error,stack)=>const Icon(Icons.person,size:48)))),
          TextButton.icon(onPressed:busy?null:choosePhoto,icon:const Icon(Icons.photo_library_outlined),label:const Text('Change photo from gallery')),
        ])),
        TextField(controller:name,enabled:!busy,maxLength:40,decoration:const InputDecoration(labelText:'Display name')),
        DropdownButtonFormField<String>(initialValue:gender??'',decoration:const InputDecoration(labelText:'Gender (optional)'),items:const [
          DropdownMenuItem(value:'',child:Text('Prefer not to say')),
          DropdownMenuItem(value:'female',child:Text('Female')),
          DropdownMenuItem(value:'male',child:Text('Male')),
          DropdownMenuItem(value:'other',child:Text('Other')),
        ],onChanged:busy?null:(value)=>setState(()=>gender=value==''?null:value)),
        ListTile(contentPadding:EdgeInsets.zero,title:const Text('Birthday (optional)'),subtitle:Text(birthday??'Not set'),onTap:busy?null:chooseBirthday,trailing:birthday==null?const Icon(Icons.calendar_month):IconButton(onPressed:busy?null:()=>setState(()=>birthday=null),icon:const Icon(Icons.clear))),
        CountryPicker(value:country,onChanged:busy?null:(value)=>setState(()=>country=value)),
        TextField(controller:bio,enabled:!busy,maxLength:150,maxLines:3,decoration:const InputDecoration(labelText:'Signature / bio (optional)')),
        FilledButton(onPressed:busy?null:save,child:const Text('Save profile')),
      ],
      if(message!=null) Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(message!)),
      if(!loaded && !busy) TextButton(onPressed:load,child:const Text('Retry profile connection')),
    ])));
}
