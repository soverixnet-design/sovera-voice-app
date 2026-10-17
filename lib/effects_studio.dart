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
 final double portraitDiameter,portraitY;
 final int entryDurationMs;
  const EffectPack(
    this.name,
    this.asset,
    this.color, {
    this.entryAsset,
    this.voiceAsset,
    this.medalAsset,
    this.entryDurationMs=3200,this.tagAsset,this.stillAsset,this.entryStillAsset,this.portraitDiameter=.43,this.portraitY=.53,
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
 EffectPack('Ice Dragon','assets/effects/ice-dragon.webp',cyan,stillAsset:'assets/effects/ice-dragon-still.webp',entryAsset:'assets/effects/ice-king-entry.webp',entryStillAsset:'assets/effects/ice-king-still.webp',portraitDiameter:.58,portraitY:.52),
 EffectPack('Violet Phoenix','assets/effects/violet-phoenix.webp',violet,stillAsset:'assets/effects/violet-phoenix-still.webp',portraitDiameter:.59),
 EffectPack('Lion Queen','assets/effects/phoenix.png',Color(0xFFFFA43A),entryAsset:'assets/effects/lion-queen-entry.webp',entryStillAsset:'assets/effects/lion-queen-still.webp',entryDurationMs:10600),
];

/// Local visual preference only. It does not grant account inventory.
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
  const EffectPortrait({
    super.key,
    required this.pack,
    required this.child,
    this.size = 240,
    this.phase = 0,
    this.speaking = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: size * (.5-pack.portraitDiameter/2),
              top: size * (pack.portraitY-pack.portraitDiameter/2),
              width: size * pack.portraitDiameter,
              height: size * pack.portraitDiameter,
              child: ClipOval(
                child: ColoredBox(
                  color: const Color(0xFF131522),
                  child: FittedBox(fit: BoxFit.contain, child: child),
                ),
              ),
            ),
            Positioned.fill(
              child: CosmeticArt(
                asset: MediaQuery.disableAnimationsOf(context)?(pack.stillAsset??pack.asset):speaking ? (pack.voiceAsset ?? pack.asset) : pack.asset,
                phase: phase,
                label: speaking ? 'Speaking effect' : pack.name,
              ),
            ),
            if (speaking)
              Positioned.fill(
                child: IgnorePointer(
                  child:
                      CustomPaint(painter: _SpeakingPainter(pack.color, phase)),
                ),
              ),
          ],
        ),
      );
}

class FramePreviewAdapter extends StatelessWidget {
  final Widget child;
  final double size;
  final bool enabled;
  const FramePreviewAdapter({
    super.key,
    required this.child,
    this.size = 160,
    this.enabled = true,
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
  if(tag?.tagAsset!=null)SizedBox(height:76,width:270,child:CosmeticLoop(builder:(phase)=>CosmeticArt(asset:tag!.tagAsset!,phase:phase,label:'Sovera Legend cosmetic tag'))),
 ])));
}

Future<void> showEntryPreview(BuildContext context, EffectPack pack) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close entry preview',
      barrierColor: Colors.black87,
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
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: AnimatedBuilder(
                  animation: motion,
                  builder: (context, _) {
                    final t = MediaQuery.disableAnimationsOf(context)
                        ? 0.0
                        : motion.value;
                    final fadeEdge = widget.pack.entryDurationMs>5000 ? .04 : .18;
                    final fade = (t < fadeEdge
                            ? t / fadeEdge
                            : t > 1-fadeEdge
                                ? (1 - t) / fadeEdge
                                : 1.0)
                        .clamp(0.0, 1.0)
                        .toDouble();
                    final entrance = Curves.easeOutCubic.transform(
                      (t * 3).clamp(0.0, 1.0).toDouble(),
                    );
                    return Opacity(
                      opacity:
                          MediaQuery.disableAnimationsOf(context) ? 1 : fade,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          MediaQuery.disableAnimationsOf(context)
                              ? 0
                              : 65 * (1 - entrance),
                        ),
                        child: Transform.scale(
                          scale: MediaQuery.disableAnimationsOf(context)
                              ? 1
                              : .65 + .35 * entrance,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: math.min(
                                    MediaQuery.sizeOf(context).width - 40,
                                    340.0,
                                  ),
                                  height: math.min(
                                    MediaQuery.sizeOf(context).height * .5,
                                    420.0,
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: widget.pack.entryAsset == null
                                            ? EffectPortrait(
                                                pack: widget.pack,
                                                phase: t,
                                                speaking: true,
                                                child:
                                                    const BrandLogo(size: 100),
                                              )
                                            : CosmeticArt(
                                                asset: MediaQuery.disableAnimationsOf(context)?(widget.pack.entryStillAsset??widget.pack.entryAsset!):widget.pack.entryAsset!,
                                                phase: t,
                                                label: '${widget.pack.name} room arrival',
                                              ),
                                      ),
                                      if (!MediaQuery.disableAnimationsOf(
                                          context))
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: ArrivalParticles(
                                                widget.pack.color,
                                                t,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  widget.pack.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: widget.pack.color,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Sovera arrival preview',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Close entry preview',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
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
          const Text(
            '${effectPacks.length} themes · Frames, entry, voice, medals & tags',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(onPressed:browseThemes,icon:const Icon(Icons.grid_view_rounded),label:Text('Browse all ${effectPacks.length} themes')),
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
                        height: kind == 4 ? 100 : 270,
                        width: 270,
                        child: CosmeticArt(
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
