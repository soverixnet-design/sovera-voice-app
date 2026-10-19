import 'room_media.dart' show EffectSound;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'main.dart';
import 'cosmetic_art.dart';
import 'medal_collection.dart';
import 'role_styles.dart';

class EffectPack {
  final String name, asset;
  final Color color;
  final String? entryAsset, voiceAsset, medalAsset, tagAsset, stillAsset, entryStillAsset;
 final double portraitDiameter,portraitY,portraitX;
 final double? portraitHeight;
 final int entryDurationMs;
  final Rect? frameNameBox;
  const EffectPack(
    this.name,
    this.asset,
    this.color, {
    this.entryAsset,
    this.voiceAsset,
    this.medalAsset,
    this.frameNameBox,this.portraitX=.5,this.portraitHeight,this.entryDurationMs=3200,this.tagAsset,this.stillAsset,this.entryStillAsset,this.portraitDiameter=.43,this.portraitY=.53,
  });
}

const effectPacks = [
  EffectPack('Phoenix Fire', 'assets/effects/phoenix.png', Color(0xFFFF8B3D)),
  EffectPack('Ice Wings', 'assets/effects/ice.png', cyan),
  EffectPack('Royal Dragon', 'assets/effects/dragon.png', Color(0xFF50D9A0)),
  EffectPack(
    'Sovera VIP7',
    'assets/effects/vip7.webp',
    gold,
    entryAsset: 'assets/effects/phoenix-entry.webp',
    voiceAsset: 'assets/effects/voice-gold.webp',
    medalAsset: 'assets/effects/top-host-medal.webp',
    tagAsset: 'assets/effects/legend-tag.webp',
  ),
 EffectPack('Royal Gold','assets/effects/royal-gold.webp',gold,stillAsset:'assets/effects/royal-gold-still.png',portraitDiameter:.61,portraitY:.52),
 EffectPack('Violet Love','assets/effects/violet-love.webp',pink,stillAsset:'assets/effects/violet-love-still.png',portraitDiameter:.59),
 EffectPack('Ice Admin','assets/effects/ice-admin.webp',cyan,stillAsset:'assets/effects/ice-admin-still.png',portraitDiameter:.59),
 EffectPack('Golden Dragon','assets/effects/dragon-gold.webp',gold,stillAsset:'assets/effects/dragon-gold-still.png',entryAsset:'assets/effects/dragon-queen-entry.webp',entryStillAsset:'assets/effects/dragon-queen-entry.webp',portraitDiameter:.59,portraitY:.51),
 EffectPack('Ice Dragon','assets/effects/ice-dragon.webp',cyan,stillAsset:'assets/effects/ice-dragon-still.webp',entryAsset:'assets/effects/ice-king-entry.webp',entryDurationMs:4500,entryStillAsset:'assets/effects/ice-king-still.webp',portraitDiameter:.58,portraitY:.52),
 EffectPack('Violet Phoenix','assets/effects/violet-phoenix.webp',violet,stillAsset:'assets/effects/violet-phoenix-still.webp',portraitDiameter:.59),
 EffectPack('Castle Flag','assets/effects/royal-gold.webp',gold,stillAsset:'assets/effects/royal-gold-still.png',entryAsset:'assets/effects/castle-entry.webp',entryStillAsset:'assets/effects/castle-entry.webp',entryDurationMs:7000,portraitDiameter:.61,portraitY:.52),
 EffectPack('Lion Queen','assets/effects/phoenix.png',Color(0xFFFFA43A),entryAsset:'assets/effects/lion-queen-entry.webp',entryStillAsset:'assets/effects/lion-queen-still.webp',entryDurationMs:10600),
 EffectPack('Phoenix Queen','assets/effects/phoenix.png',Color(0xFFFF8B3D),entryAsset:'assets/effects/phoenix-queen-entry.webp',entryStillAsset:'assets/effects/phoenix-queen-still.webp',entryDurationMs:13800),
 EffectPack('Tiger Queen','assets/effects/royal-gold.webp',gold,stillAsset:'assets/effects/royal-gold-still.png',entryAsset:'assets/effects/tiger-queen-entry.webp',entryStillAsset:'assets/effects/tiger-queen-still.webp',entryDurationMs:12000,portraitDiameter:.61,portraitY:.52),
 EffectPack('Crown Violet','assets/effects/crown-violet.webp',violet,stillAsset:'assets/effects/crown-violet-still.webp',portraitDiameter:.50,portraitY:.46,frameNameBox:Rect.fromLTWH(.23,.77,.54,.10)),
 EffectPack('Royal Horses','assets/effects/royal-horses-clean.png',gold,stillAsset:'assets/effects/royal-horses-clean.png',portraitDiameter:.43,portraitY:.44,frameNameBox:Rect.fromLTWH(.18,.74,.64,.10)),
 EffectPack('Solar Crown','assets/effects/solar-crown.webp',gold,stillAsset:'assets/effects/solar-crown-still.webp',portraitDiameter:.40,portraitHeight:.414,portraitX:.493,portraitY:.525,tagAsset:'assets/effects/solar-nameplate.webp'),
 EffectPack('Sunrise Crown','assets/effects/sunrise-crown.webp',gold,stillAsset:'assets/effects/sunrise-crown-still.webp',portraitDiameter:.398,portraitHeight:.44,portraitX:.608,portraitY:.499,tagAsset:'assets/effects/solar-nameplate.webp'),
 EffectPack('Rose Crown','assets/effects/rose-crown.webp',pink,stillAsset:'assets/effects/rose-crown-still.webp',portraitDiameter:.417,portraitHeight:.487,portraitX:.61,portraitY:.446,tagAsset:'assets/effects/rose-nameplate.webp'),

];

/// Local visual preference only. It does not grant account inventory.
final effectProfileName=ValueNotifier<String>('Sovera guest');
final effectProfileId=ValueNotifier<String>('');
final previewAvatarFrame = ValueNotifier<EffectPack?>(null);
final previewEntryEffect = ValueNotifier<EffectPack?>(null);
final previewMedal = ValueNotifier<EffectPack?>(null);
final previewNameTag = ValueNotifier<EffectPack?>(null);
void resetCosmeticPreviews() {
  previewAvatarFrame.value = null;
  previewEntryEffect.value = null;
  previewMedal.value = null;
  previewNameTag.value = null;
  previewRankingMedals.value = {};
  previewRoleStyles.value = {};
}

class EffectPortrait extends StatelessWidget {
  final EffectPack pack;
  final Widget child;
  final double size, phase;
  final bool speaking;
  final double? portraitSize;
  const EffectPortrait({
    super.key,
    required this.pack,
    required this.child,
    this.size = 240,
    this.phase = 0,
    this.speaking = false,
    this.portraitSize,
  });
  @override
  Widget build(BuildContext context) {
    final artSize = portraitSize == null ? size : portraitSize! / pack.portraitDiameter;
    final canvasSize = math.max(size, artSize);
    final inset = (canvasSize - artSize) / 2;
    final width = artSize * pack.portraitDiameter;
    final height = artSize * (pack.portraitHeight ?? pack.portraitDiameter);
    return SizedBox(width: canvasSize, height: canvasSize, child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(width: canvasSize, height: canvasSize, child: Stack(children: [
        Positioned(left: inset + (artSize-width)/2,
          top: inset + artSize*pack.portraitY-height/2, width: width, height: height,
          child: ClipOval(child: ColoredBox(color: const Color(0xFF131522),
            child: FittedBox(fit: BoxFit.cover, child: child)))),
        Positioned.fill(child:ClipRect(key:const ValueKey('frame-art-viewport'),child:Stack(children:[
         Positioned(left: inset+artSize*(.5-pack.portraitX), top: inset, width: artSize, height: artSize,
          child: IgnorePointer(child: CosmeticArt(
            asset: MediaQuery.disableAnimationsOf(context) ? (pack.stillAsset ?? pack.asset)
              : speaking ? (pack.voiceAsset ?? pack.asset) : pack.asset,
            phase: phase, label: speaking ? 'Speaking effect' : pack.name))),
        ]))),
        if (pack.frameNameBox case final box?) Positioned(
          left: inset+artSize*(box.left+.5-pack.portraitX), top: inset+artSize*box.top,
          width: artSize*box.width, height: artSize*box.height,
          child: ValueListenableBuilder<String>(valueListenable: effectProfileName,
            builder: (context, name, _) => FittedBox(fit: BoxFit.scaleDown,
              child: Text(name, maxLines: 1, style: TextStyle(color: const Color(0xFFFFF1BF),
                fontSize: artSize*.055, fontWeight: FontWeight.w800,
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)]))))),
        if (speaking) Positioned.fill(child: IgnorePointer(
          child: CustomPaint(painter: _SpeakingPainter(pack.color, phase)))),
      ])),
    ));
  }
}

class FramePreviewAdapter extends StatelessWidget {
  final Widget child;
  final double size;
  final bool enabled;
  final double? portraitSize;
  const FramePreviewAdapter({
    super.key,
    required this.child,
    this.size = 160,
    this.enabled = true,
    this.portraitSize,
  });
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EffectPack?>(
        valueListenable: previewAvatarFrame,
        builder: (context, pack, _) => pack == null || !enabled
            ? child
            : CosmeticLoop(
                builder: (phase) => EffectPortrait(
                  pack: pack,
                  size: size,
                  portraitSize: portraitSize,
                  phase: phase,
                  child: child,
                ),
              ),
      );
}

class _SpeakingPainter extends CustomPainter {
  final Color color;
  final double phase;
  _SpeakingPainter(this.color, this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .53);
    for (int i = 0; i < 3; i++) {
      final t = (phase + i / 3) % 1;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - t) + 0.5
        ..color = color.withValues(alpha: (1 - t) * .65);
      canvas.drawCircle(center, size.width * (.23 + t * .21), paint);
    }
    final paint = Paint()..color = color;
    for (int i = 0; i < 16; i++) {
      final angle = i * math.pi / 8 + phase * math.pi * 2;
      final radius = size.width * (.38 + .035 * math.sin(angle * 3));
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        1.5 + 1.5 * math.sin(angle).abs(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeakingPainter old) =>
      old.phase != phase || old.color != color;
}

/// Cosmetic art is explicitly separate from server-verified VIP/rank badges.
class ProfileStylePreview extends StatelessWidget {
 const ProfileStylePreview({super.key});
 @override Widget build(BuildContext context)=>ValueListenableBuilder<EffectPack?>(valueListenable:previewMedal,builder:(context,medal,_)=>ValueListenableBuilder<EffectPack?>(valueListenable:previewNameTag,builder:(context,tag,_)=>Column(children:[
  const Text('Style preview',style:TextStyle(fontSize:11,color:Colors.white54)),const SizedBox(height:8),
  ProfileRankingMedals(extra:medal?.medalAsset==null?null:SizedBox(width:76,height:88,child:CosmeticLoop(builder:(phase)=>CosmeticArt(asset:medal!.medalAsset!,phase:phase,label:'Top Host cosmetic medal')))),
  if(tag?.tagAsset!=null)SizedBox(height:32,width:120,child:CosmeticLoop(builder:(phase)=>NamedTagArt(asset:tag!.tagAsset!,phase:phase))),
 ])));
}

Future<void> showEntryPreview(BuildContext context, EffectPack pack) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close entry preview',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, __) => _EntryPreview(pack: pack),
    );

class _EntryPreview extends StatefulWidget {
  final EffectPack pack;
  const _EntryPreview({required this.pack});
  @override
  State<_EntryPreview> createState() => _EntryPreviewState();
}

class _EntryPreviewState extends State<_EntryPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  bool started = false;
  final sound = EffectSound();
  @override
  void initState() {
    super.initState();
    motion = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.pack.entryDurationMs),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted)
          Navigator.of(context).pop();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      if (MediaQuery.disableAnimationsOf(context))
        motion.duration = const Duration(milliseconds: 2400);
      motion.forward();
      sound.play(widget.pack.name);
    }
  }

  @override
  void dispose() {
    sound.dispose();
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: SafeArea(child:LayoutBuilder(builder:(context,constraints){
      final width=math.min(constraints.maxWidth,480.0);
      final height=math.min(constraints.maxHeight*.84,width*1.65);
      final reduced=MediaQuery.disableAnimationsOf(context);
      return Stack(children:[
        Positioned(left:12,top:12,child:IconButton(tooltip:sound.muted?'Enable entry sound':'Mute entry sound',onPressed:(){setState(()=>sound.muted=!sound.muted);if(sound.muted){sound.stop();}else{sound.play(widget.pack.name);}},icon:Icon(sound.muted?Icons.volume_off_rounded:Icons.volume_up_rounded,color:Colors.white))),
        Center(child:SizedBox(width:width,height:height,child:AnimatedBuilder(animation:motion,builder:(context,_){
          final t=reduced?0.0:motion.value;
          final edge=widget.pack.entryDurationMs>5000 ? .04 : .18;
          final fade=reduced?1.0:(t<edge?t/edge:t>1-edge?(1-t)/edge:1.0).clamp(0.0,1.0).toDouble();
          return IgnorePointer(child:Opacity(opacity:fade,child:Stack(children:[
            Positioned.fill(child:DecoratedBox(decoration:BoxDecoration(gradient:RadialGradient(colors:[widget.pack.color.withValues(alpha:.25),Colors.transparent],stops:const [.2,1])))),
            Positioned.fill(child:ShaderMask(
              key:const ValueKey('arrival-edge-blend'),blendMode:BlendMode.dstIn,
              shaderCallback:(rect)=>const RadialGradient(radius:.72,colors:[Colors.white,Colors.white,Colors.transparent],stops:[0,.58,1]).createShader(rect),
              child:widget.pack.entryAsset==null?EffectPortrait(pack:widget.pack,phase:t,speaking:true,child:const BrandLogo(size:100)):
                CosmeticArt(asset:reduced?(widget.pack.entryStillAsset??widget.pack.entryAsset!):widget.pack.entryAsset!,phase:t,label:'${widget.pack.name} room arrival'),
            )),
            if(!reduced)Positioned.fill(child:CustomPaint(painter:ArrivalParticles(widget.pack.color,t))),
          ])));
        }))),
        Positioned(left:24,right:24,bottom:math.max(12.0,constraints.maxHeight*.08),child:IgnorePointer(child:Center(child:Container(
          padding:const EdgeInsets.symmetric(horizontal:18,vertical:10),
          decoration:BoxDecoration(color:const Color(0xD912172D),borderRadius:BorderRadius.circular(28),border:Border.all(color:widget.pack.color.withValues(alpha:.5)),boxShadow:[BoxShadow(color:widget.pack.color.withValues(alpha:.18),blurRadius:18)]),
          child:Column(mainAxisSize:MainAxisSize.min,children:[ValueListenableBuilder<String>(valueListenable:effectProfileName,builder:(context,name,_)=>Text(name,maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w800))),Text(widget.pack.name,maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:TextStyle(color:widget.pack.color,fontSize:12,fontWeight:FontWeight.w600)),ValueListenableBuilder<String>(valueListenable:effectProfileId,builder:(context,id,_)=>id.isEmpty?const SizedBox.shrink():Text('ID · $id',style:const TextStyle(fontSize:11,color:cyan))),ValueListenableBuilder<EffectPack?>(valueListenable:previewNameTag,builder:(context,tag,_)=>CompactCosmeticTag(pack:tag))]),
        )))),
        Positioned(top:8,right:8,child:IconButton.filled(tooltip:'Close entry preview',style:IconButton.styleFrom(backgroundColor:const Color(0xCC12172D)),onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))),
      ]);
    })),
  );
}

class EffectsStudio extends StatefulWidget {
  const EffectsStudio({super.key});
  @override
  State<EffectsStudio> createState() => _EffectsStudioState();
}

class _EffectsStudioState extends State<EffectsStudio>
    with SingleTickerProviderStateMixin {
  int selected = 3, kind = 0;
  late final AnimationController pulse;
  @override
  void initState() {
    super.initState();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  void play() {
    if (kind == 1) {
      showEntryPreview(context, effectPacks[selected]);
    } else if (!MediaQuery.disableAnimationsOf(context)) {
      pulse.forward(from: 0);
    }
  }

  Widget themeTile(int i,BuildContext sheet){
    final pack=effectPacks[i];
    return Card(child:InkWell(onTap:(){setState(()=>selected=i);Navigator.pop(sheet);},child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[Expanded(child:Image.asset(pack.stillAsset??pack.asset)),const SizedBox(height:8),Text(pack.name,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))]))));
  }
  Future<void> browseThemes()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(sheet){
    return SafeArea(child:SizedBox(height:MediaQuery.sizeOf(sheet).height*.75,child:GridView.builder(padding:const EdgeInsets.all(16),itemCount:effectPacks.length,gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:190,mainAxisExtent:178,crossAxisSpacing:10,mainAxisSpacing:10),itemBuilder:(_,i)=>themeTile(i,sheet))));
  });
  Future<void> browseEntries()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(sheet){final entries=List.generate(effectPacks.length,(i)=>i).where((i)=>effectPacks[i].entryAsset!=null).toList();return SafeArea(child:SizedBox(height:MediaQuery.sizeOf(sheet).height*.75,child:GridView.builder(padding:const EdgeInsets.all(16),itemCount:entries.length,gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:190,mainAxisExtent:178,crossAxisSpacing:10,mainAxisSpacing:10),itemBuilder:(_,i)=>Card(child:InkWell(onTap:(){setState((){selected=entries[i];kind=1;});Navigator.pop(sheet);},child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[Expanded(child:Image.asset(effectPacks[entries[i]].entryStillAsset??effectPacks[entries[i]].entryAsset!)),Text(effectPacks[entries[i]].name,textAlign:TextAlign.center)])))))));});
  @override
  Widget build(BuildContext context) {
    final pack = effectPacks[selected];
    return Scaffold(
      appBar: AppBar(title: const Text('Frames & effects')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const MedalCollection())),
              icon: const Icon(Icons.military_tech_rounded),
              label: const Text('Animated medals')),
          const SizedBox(height: 16),
          const Text(
            'Sovera signature collection',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '${effectPacks.length} themes · Frames, entry, voice, medals & tags',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(onPressed:browseThemes,icon:const Icon(Icons.grid_view_rounded),label:Text('Browse all ${effectPacks.length} themes')),
          OutlinedButton.icon(onPressed:browseEntries,icon:const Icon(Icons.login_rounded),label:const Text('Browse room entries')),
          const SizedBox(height:12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final i in [3, 0, 1, 2,...List.generate(effectPacks.length-4,(i)=>i+4)])
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      selected: selected == i,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => selected = i),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 126,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selected == i
                                ? effectPacks[i].color.withValues(alpha: .15)
                                : Colors.white.withValues(alpha: .03),
                            border: Border.all(
                              color: selected == i
                                  ? effectPacks[i].color
                                  : Colors.white12,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              Image.asset(
                                effectPacks[i].stillAsset??effectPacks[i].asset,
                                height: 98,
                                width: 98,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                effectPacks[i].name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < 5; i++)
                ChoiceChip(
                  label: Text(
                    ['Frame', 'Entry', 'Speaking glow', 'Medal', 'Name tag'][i],
                  ),
                  selected: kind == i,
                  onSelected: (_) {
                    pulse.reset();
                    setState(() => kind = i);
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          Glass(
            tint: pack.color,
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) {
                    final asset = kind == 3
                        ? pack.medalAsset
                        : kind == 4
                            ? pack.tagAsset
                            : kind == 1
                                ? pack.entryAsset
                                : null;
                    if (kind >= 3 && asset == null)
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Choose Sovera VIP7 for this collection.'),
                      );
                    if (asset != null)
                      return SizedBox(
                        height: kind == 4 ? 36 : 270,
                        width: kind == 4 ? 140 : 270,
                        child:kind==4?NamedTagArt(asset:asset,phase:pulse.value):CosmeticArt(
                          asset: MediaQuery.disableAnimationsOf(context)&&kind==1?(pack.entryStillAsset??asset):asset,
                          phase: pulse.value,
                          label: kind == 3
                              ? 'Top Host medal artwork'
                              : kind == 4
                                  ? 'Sovera Legend name tag'
                                  : 'Phoenix room arrival',
                        ),
                      );
                    return EffectPortrait(
                      pack: pack,
                      size: math.min(
                        MediaQuery.sizeOf(context).width - 80,
                        270.0,
                      ),
                      phase: pulse.value,
                      speaking: kind == 2,
                      child: const BrandLogo(size: 100),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  pack.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  [
                    'A decorative frame around your portrait.',
                    'An animated room-arrival overlay with wings, light and particles.',
                    'A visual pulse around the avatar. This preview does not listen to your microphone.',
                    'A decorative Top Host medal. This style preview does not award a rank.',
                    'A decorative Sovera Legend nameplate for your profile.',
                  ][kind],
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, height: 1.5),
                ),
                const SizedBox(height: 18),
                if (kind == 1 || kind == 2)
                  FilledButton.icon(
                    onPressed: play,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      kind == 1 ? 'Preview entry' : 'Preview speaking glow',
                    ),
                  ),
                if (kind != 1 && kind != 2)
                  FilledButton.icon(
                    onPressed: kind >= 3 &&
                            (kind == 3 ? pack.medalAsset : pack.tagAsset) ==
                                null
                        ? null
                        : play,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play animation'),
                  ),
                if (kind == 1)
                  FilledButton.tonal(
                    onPressed: () {
                      previewEntryEffect.value = pack;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Entry selected for your next room visit in this session.',
                          ),
                        ),
                      );
                    },
                    child: const Text('Use entry in preview'),
                  ),
                if (kind == 3 || kind == 4)
                  FilledButton.tonal(
                    onPressed: (kind == 3 ? pack.medalAsset : pack.tagAsset) ==
                            null
                        ? null
                        : () {
                            (kind == 3 ? previewMedal : previewNameTag).value =
                                pack;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Profile style selected for this preview session.',
                                ),
                              ),
                            );
                          },
                    child: Text(
                      kind == 3
                          ? 'Use medal in preview'
                          : 'Use name tag in preview',
                    ),
                  ),
                if (kind == 0)
                  FilledButton.icon(
                    onPressed: () {
                      previewAvatarFrame.value = pack;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Frame applied for this preview session.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Use frame in preview'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: resetCosmeticPreviews,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset preview styles'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Preview selections reset when the app restarts. Your selected entry plays on room visits; medals and tags appear as profile styles. Speaking glow is a visual demonstration. Live voice and account inventory are not connected.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class NamedTagArt extends StatelessWidget{
 final String asset;final double phase;const NamedTagArt({super.key,required this.asset,this.phase=0});
 @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,c){final named=asset.contains('nameplate');final still=asset.replaceFirst('.webp','-still.webp');return Stack(fit:StackFit.expand,children:[CosmeticArt(asset:named&&MediaQuery.disableAnimationsOf(context)?still:asset,phase:phase,label:'Sovera Legend cosmetic tag'),if(named)Positioned(left:c.maxWidth*.30,top:c.maxHeight*.37,width:c.maxWidth*.60,height:c.maxHeight*.34,child:ValueListenableBuilder<String>(valueListenable:effectProfileName,builder:(context,name,_)=>FittedBox(fit:BoxFit.scaleDown,child:Text(name,maxLines:1,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800,shadows:[Shadow(color:Colors.black,blurRadius:3)]))))) ]);});
}

/// Decorative tag, kept separate from identity and server-verified privileges.
class CompactCosmeticTag extends StatelessWidget {
 final EffectPack? pack;
 const CompactCosmeticTag({super.key, this.pack});
 @override Widget build(BuildContext context) {
  if(pack?.tagAsset==null)return const SizedBox.shrink();
  return Semantics(label:'Cosmetic name tag',child:SizedBox(width:96,height:28,
    child:NamedTagArt(asset:pack!.tagAsset!)));
 }
}

class CosmeticIdentityLine extends StatelessWidget {
 final String name, userId;
 final EffectPack? tag;
 const CosmeticIdentityLine({super.key,required this.name,this.userId='',this.tag});
 @override Widget build(BuildContext context)=>Wrap(spacing:6,runSpacing:3,
  crossAxisAlignment:WrapCrossAlignment.center,children:[
   Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
   if(userId.isNotEmpty)Text('ID · $userId',style:const TextStyle(fontSize:11,color:cyan)),
   CompactCosmeticTag(pack:tag),
  ]);
}

class RoomChatMessage {
 final String text,name,userId;
 final EffectPack? tag;
 const RoomChatMessage({required this.text,required this.name,this.userId='',this.tag});
}

class RoomChatBubble extends StatelessWidget {
 final RoomChatMessage message;
 const RoomChatBubble({super.key,required this.message});
 @override Widget build(BuildContext context)=>Glass(tint:gold,padding:const EdgeInsets.all(12),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   CosmeticIdentityLine(name:message.name,userId:message.userId,tag:message.tag),
   const SizedBox(height:5),Text(message.text),
  ]));
}
