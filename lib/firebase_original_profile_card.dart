import 'package:flutter/material.dart';
import 'firebase_catalog.dart';
import 'sovera_visuals.dart' show Glass,BrandLogo,cyan,gold,violet;
import 'country_picker.dart' show countryFlag;

/// Original Sovera profile-card arrangement; profile comes only from the
/// signed-in Sovera server. No Supabase access and no invented levels/IDs.
class FirebaseOriginalProfileCard extends StatelessWidget {
  final Map<String,dynamic>? profile;
  final String name;
  final VoidCallback onEdit;
  const FirebaseOriginalProfileCard({
    super.key,required this.profile,required this.name,required this.onEdit,
  });

  Widget portrait(){
    final avatar=profile?['avatar_url'];
    final frame=catalogAsset(profile?['equipped'],'frame');
    if(frame!=null)return CatalogPortrait(asset:frame,avatarUrl:avatar as String?,size:242);
    return CatalogPortrait(avatarUrl:avatar as String?,size:242);
  }

  Widget rank(String label,IconData icon,Color color)=>Container(
    width:93,padding:const EdgeInsets.symmetric(vertical:15,horizontal:6),
    decoration:BoxDecoration(border:Border.all(color:color.withValues(alpha:.5)),
      borderRadius:BorderRadius.circular(19),
      color:color.withValues(alpha:.08)),
    child:Column(children:[
      Icon(icon,color:color,size:25),const SizedBox(height:8),
      Text('Lv. —',style:TextStyle(fontSize:15,fontWeight:FontWeight.w800,color:color)),
      const SizedBox(height:5),Text(label,style:const TextStyle(fontSize:11,color:Colors.white70)),
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
      Text('$name ${countryFlag(country)}'.trim(),
        textAlign:TextAlign.center,
        style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
      const SizedBox(height:9),
      for(final kind in const ['medal','tag'])if(catalogAsset(profile?['equipped'],kind)!=null)SizedBox(height:72,child:CatalogImage(asset:catalogAsset(profile?['equipped'],kind)!)),
      Text(hasId?'ID · $id':'ID · Waiting for verified server ID',
        textAlign:TextAlign.center,
        style:const TextStyle(fontSize:13,color:cyan,fontWeight:FontWeight.w600)),
      const SizedBox(height:19),
      Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:8,children:[
        rank('Wealth',Icons.diamond_rounded,cyan),
        rank('Charm',Icons.favorite_rounded,const Color(0xFFF18AA6)),
        rank('VIP',Icons.workspace_premium_rounded,gold),
      ]),
      const SizedBox(height:14),
      const Text('Levels appear when verified activity is available.',
        textAlign:TextAlign.center,
        style:TextStyle(fontSize:11,color:Colors.white54)),
      const SizedBox(height:19),
      const Text('Style preview',style:TextStyle(fontSize:12,color:Colors.white54)),
      const SizedBox(height:12),
      const Text('Medals',style:TextStyle(fontSize:21,fontWeight:FontWeight.w800)),
      const SizedBox(height:15),
      Row(children:[
        for(final asset in const ['assets/medals/gold.webp',
          'assets/medals/silver.webp','assets/medals/bronze.webp'])
          Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),
            child:Image.asset(asset,height:95,fit:BoxFit.contain,
              errorBuilder:(_,__,___)=>const Icon(Icons.military_tech_rounded,
                color:gold,size:45)))),
      ]),
      const SizedBox(height:15),
      TextButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(ctx)=>
        AlertDialog(title:const Text('Medal previews'),
          content:const Text('The original medal designs are available to preview. '
            'Awards and verified ownership will appear after the server ranking service is connected.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))])),
        icon:const Icon(Icons.military_tech_rounded),
        label:const Text('Manage medal previews')),
      const SizedBox(height:13),
      Container(padding:const EdgeInsets.symmetric(horizontal:15,vertical:7),
        decoration:BoxDecoration(color:violet.withValues(alpha:.19),
          borderRadius:BorderRadius.circular(21)),
        child:Text(profile==null?'Profile not yet saved':'Sovera member',
          style:const TextStyle(color:Colors.white70,fontSize:11))),
      if(bio.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),
        child:Text(bio,textAlign:TextAlign.center,
          style:const TextStyle(color:Colors.white70,height:1.45))),
      const SizedBox(height:12),
      TextButton.icon(onPressed:onEdit,
        icon:const Icon(Icons.edit_outlined),label:const Text('Edit Profile')),
    ]));
  }
}
