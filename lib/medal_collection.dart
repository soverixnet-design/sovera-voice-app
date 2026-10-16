import 'package:flutter/material.dart';
import 'role_styles.dart';

final previewRankingMedals=ValueNotifier<Set<String>>({});
class ProfileRankingMedals extends StatelessWidget{
 final Widget? extra;
 const ProfileRankingMedals({super.key,this.extra});
 @override Widget build(BuildContext context)=>ValueListenableBuilder<Set<String>>(valueListenable:previewRankingMedals,builder:(context,selected,_)=>Column(children:[
  const Text('Medals',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:8),
  if(selected.isNotEmpty||extra!=null)Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:8,children:[if(extra!=null)extra!,for(final id in ['gold','silver','bronze'])if(selected.contains(id))Image.asset('assets/medals/$id.${MediaQuery.disableAnimationsOf(context)?'png':'webp'}',width:76,height:88,semanticLabel:'$id medal preview')]),
  const ProfileRoleStyles(),
  TextButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const MedalCollection())),icon:const Icon(Icons.military_tech_rounded),label:Text(selected.isEmpty?'Choose medal previews':'Manage medal previews')),
 ]));
}
/// Bundled artwork previews; ranking awards continue to be server-owned.
class MedalCollection extends StatelessWidget {
  const MedalCollection({super.key});

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sovera medals')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const RoleMedalCollection())),icon:const Icon(Icons.shield_rounded),label:const Text('Staff & host medal designs')),
          const SizedBox(height:16),
          const Text('Ranking collection', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Gold, Silver and Bronze · Profile style previews, not awarded ranks'),
          const SizedBox(height: 20),
          for (final medal in const [
            ('gold', 'Gold · Rank 1', Color(0xFFFFD45F)),
            ('silver', 'Silver · Rank 2', Color(0xFF91DCFF)),
            ('bronze', 'Bronze · Rank 3', Color(0xFFFFAB4C)),
          ])
            Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Image.asset(
                    'assets/medals/${medal.$1}.${reducedMotion ? 'png' : 'webp'}',
                    width: 240, height: 240, fit: BoxFit.contain,
                    semanticLabel: '${medal.$2} Sovera medal',
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<Set<String>>(valueListenable:previewRankingMedals,builder:(context,selected,_)=>FilterChip(label:Text(selected.contains(medal.$1)?'Remove from profile':'Show below levels'),selected:selected.contains(medal.$1),onSelected:(value){final next={...selected}..remove(medal.$1);if(value)next.add(medal.$1);previewRankingMedals.value=next;})),
                  Text(medal.$2, style: TextStyle(color: medal.$3, fontSize: 21, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
