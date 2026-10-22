import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'firebase_catalog.dart';
import 'sovera_visuals.dart' show Glass,cyan,gold,violet;
import 'country_picker.dart' show countryFlag;

/// Original Sovera profile-card arrangement; profile comes only from the
/// signed-in Sovera server. No Supabase access and no invented levels/IDs.
class FirebaseOriginalProfileCard extends StatelessWidget {
  final Map<String,dynamic>? profile;
  final String name;
  final VoidCallback onEdit;final bool editable;
  const FirebaseOriginalProfileCard({
    super.key,required this.profile,required this.name,required this.onEdit,this.editable=true,
  });

  Widget portrait(){
    final avatar=profile?['avatar_url'];
    final frame=catalogAsset(profile?['equipped'],'frame');
    if(frame!=null)return CatalogPortrait(asset:frame,avatarUrl:avatar as String?,size:128);
    return CatalogPortrait(avatarUrl:avatar as String?,size:128);
  }

  String get membershipLabel {final v=profile?['vip'];if(v is! Map)return 'Not active';return '${v['kind'].toString().toUpperCase()} ${v['level']}';}
  Widget rank(String label,IconData icon,Color color)=>Container(
    padding:const EdgeInsets.symmetric(vertical:9,horizontal:12),
    decoration:BoxDecoration(border:Border.all(color:color.withValues(alpha:.5)),
      borderRadius:BorderRadius.circular(24),
      gradient:LinearGradient(colors:[color.withValues(alpha:.35),const Color(0xff192137)]),
      boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.3),blurRadius:8,offset:const Offset(0,4))]),
    child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,color:color,size:18),
      const SizedBox(width:6),Text(label=='VIP'?membershipLabel:
        '${label=='Wealth'?'↑ Sending':'↓ Receiving'} Lv.${profile?[label=='Wealth'?'wealth_level':'charm_level']??'—'}',
        style:TextStyle(fontSize:12,fontWeight:FontWeight.w800,color:color)),
    ]));

  @override Widget build(BuildContext context){
    final country=(profile?['country']??'').toString().toUpperCase();
    final bio=(profile?['bio']??'').toString().trim();
    // The Firebase UID is never masqueraded as an old numeric public ID.
    // A legacy public ID is displayed only if returned by the server.
    final id=profile?['public_id']?.toString();
    final hasId=id!=null&&RegExp(r'^\d{4,20}$').hasMatch(id);
    return Glass(tint:cyan,child:Column(children:[
      Center(child:portrait()),
      const SizedBox(height:7),
      Text(name,
        textAlign:TextAlign.center,
        style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
      if(profile?['is_coin_seller']==true)
        const Chip(avatar:Icon(Icons.verified_rounded,color:gold),label:Text('Approved Coin Seller')),
      const SizedBox(height:9),
      Wrap(alignment:WrapAlignment.center,crossAxisAlignment:WrapCrossAlignment.center,spacing:8,children:[
        Text(countryFlag(country),style:const TextStyle(fontSize:22)),
        if(profile?['gender']!=null)Icon(profile?['gender']=='female'?Icons.female:profile?['gender']=='male'?Icons.male:Icons.person_outline,color:violet),
        Text(hasId?'ID · $id':'ID · Waiting for verified server ID',style:const TextStyle(fontSize:13,color:cyan,fontWeight:FontWeight.w600)),
        if(hasId)IconButton(tooltip:'Copy user ID',onPressed:()async{await Clipboard.setData(ClipboardData(text:id));},icon:const Icon(Icons.copy_rounded,size:18)),
      ]),
      for(final kind in const ['medal','tag'])if(catalogAsset(profile?['equipped'],kind)!=null)SizedBox(height:60,child:CatalogImage(asset:catalogAsset(profile?['equipped'],kind)!)),
      const SizedBox(height:19),
      Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:8,children:[
        rank('Wealth',Icons.diamond_rounded,cyan),
        rank('Charm',Icons.favorite_rounded,const Color(0xFFF18AA6)),
        rank('VIP',Icons.workspace_premium_rounded,gold),
      ]),
      const SizedBox(height:14),
      const Text('Wealth & Charm: one level per 10,000 gift Coins / Diamonds.',
        textAlign:TextAlign.center,
        style:TextStyle(fontSize:11,color:Colors.white54)),
      const SizedBox(height:19),
      Container(padding:const EdgeInsets.symmetric(horizontal:15,vertical:7),
        decoration:BoxDecoration(color:violet.withValues(alpha:.19),
          borderRadius:BorderRadius.circular(21)),
        child:Text(profile==null?'Profile not yet saved':'Sovera member',
          style:const TextStyle(color:Colors.white70,fontSize:11))),
      if(bio.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),
        child:Text(bio,textAlign:TextAlign.center,
          style:const TextStyle(color:Colors.white70,height:1.45))),
      const SizedBox(height:12),
      if(editable)TextButton.icon(onPressed:onEdit,
        icon:const Icon(Icons.edit_outlined),label:const Text('Edit Profile')),
    ]));
  }
}
