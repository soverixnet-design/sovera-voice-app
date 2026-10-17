import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'main.dart' show BrandLogo, gold, pink, cyan, violet;

/// A short, scoped sound. Closing or backgrounding its visual stops playback.
class EffectSound with WidgetsBindingObserver {
  AudioPlayer? _player;
  bool muted = false, _disposed = false;
  EffectSound() {
    WidgetsBinding.instance.addObserver(this);
  }
  Future<void> play(String name) async {
    if (muted || _disposed) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      if (_disposed || muted) return;
      final lower = name.toLowerCase();
      final asset = lower.contains('ice') || lower.contains('diamond')
          ? 'ice'
          : lower.contains('dragon') ||
                lower.contains('tiger') ||
                lower.contains('lion')
          ? 'royal'
          : 'sparkle';
      await player.play(AssetSource('sounds/$asset.wav'), volume: .32);
    } catch (_) {
      /* Missing audio hardware must not block the room. */
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  Future<void> _release() async {
    try {
      await _player?.dispose();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _release();
  }
}

class RoomPhoto extends StatefulWidget {
  final String? roomId;
  final bool canEdit;
  final double size;
  const RoomPhoto({
    super.key,
    this.roomId,
    this.canEdit = false,
    this.size = 48,
  });
  @override
  State<RoomPhoto> createState() => _RoomPhotoState();
}

class _RoomPhotoState extends State<RoomPhoto> {
  Uint8List? photo;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (widget.roomId == null) return;
    try {
      final row = await soveraClient
          .from('sovera_rooms')
          .select('photo_path')
          .eq('id', widget.roomId!)
          .single();
      final path = row['photo_path'] as String?;
      if (path == null) return;
      final data = await soveraClient.storage
          .from('sovera-room-photos')
          .download(path);
      if (mounted) setState(() => photo = data);
    } catch (_) {
      /* Keep the existing logo when offline. */
    }
  }

  void notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> choose() async {
    if (busy || !widget.canEdit) return;
    setState(() => busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 768,
        maxHeight: 768,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        notice('Choose an image smaller than 10 MB.');
        return;
      }
      // Normalize gallery formats to PNG for a stable, validated storage path.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
      final frame = await codec.getNextFrame();
      final encoded = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      codec.dispose();
      if (encoded == null) throw StateError('Image could not be decoded');
      final png = encoded.buffer.asUint8List();
      if (png.length > 5 * 1024 * 1024) {
        notice('Choose a smaller image.');
        return;
      }
      if (!mounted) return;
      if (widget.roomId != null) {
        final user = soveraClient.auth.currentUser;
        if (user == null) throw StateError('Sign in first');
        final path = '${user.id}/${widget.roomId}/cover.png';
        await soveraClient.storage
            .from('sovera-room-photos')
            .uploadBinary(
              path,
              png,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: true,
              ),
            );
        await soveraClient
            .from('sovera_rooms')
            .update({'photo_path': path})
            .eq('id', widget.roomId!)
            .eq('owner_id', user.id)
            .select('id')
            .single();
      }
      if (mounted) setState(() => photo = png);
      notice(
        widget.roomId == null
            ? 'Room picture changed for this preview.'
            : 'Room picture saved.',
      );
    } catch (_) {
      notice(
        'Could not save the picture. Check photo access and your connection, then retry.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.canEdit
        ? 'Change room picture from gallery'
        : 'Room picture',
    child: InkWell(
      onTap: widget.canEdit && !busy ? choose : null,
      borderRadius: BorderRadius.circular(widget.size),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipOval(
                child: photo == null
                    ? BrandLogo(size: widget.size)
                    : Image.memory(
                        photo!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
            ),
            if (busy)
              const Positioned.fill(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (widget.canEdit && !busy)
              const Positioned(
                right: 0,
                bottom: 0,
                child: Icon(Icons.add_a_photo_rounded, size: 12, color: gold),
              ),
          ],
        ),
      ),
    ),
  );
}

class GiftAnimationCard extends StatefulWidget {
  final String name;
  const GiftAnimationCard({super.key, required this.name});
  @override
  State<GiftAnimationCard> createState() => _GiftAnimationCardState();
}

class _GiftAnimationCardState extends State<GiftAnimationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  final sound = EffectSound();
  @override
  void initState() {
    super.initState();
    motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    sound.play(widget.name);
  }

  @override
  void dispose() {
    sound.dispose();
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (widget.name) {
      'Heart' || 'CP Heart' => (Icons.favorite_rounded, pink),
      'Diamond' => (Icons.diamond_rounded, cyan),
      'Castle' => (Icons.castle_rounded, gold),
      'Rose' => (Icons.local_florist_rounded, pink),
      'Royal car' => (Icons.directions_car_rounded, gold),
      'Holding hands' => (Icons.handshake_rounded, cyan),
      _ => (Icons.auto_awesome_rounded, violet),
    };
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF171425),
      title: Text('${widget.name} preview'),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: motion,
                builder: (context, _) {
                  final t = reduced ? 0.0 : motion.value;
                  return Container(
                    height: 210,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: RadialGradient(
                        colors: [
                          color.withValues(alpha: .12 + t * .2),
                          Colors.transparent,
                        ],
                      ),
                      border: Border.all(color: color.withValues(alpha: .5)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (var i = 0; i < 8; i++)
                          Transform.translate(
                            offset: Offset(
                              (i.isEven ? 1 : -1) *
                                  (35 + i * 8.0) *
                                  (1 + t * .2),
                              (i - 3.5) * 21 * (1 + t * .12),
                            ),
                            child: Opacity(
                              opacity: .25 + t * .6,
                              child: Icon(
                                Icons.auto_awesome,
                                size: 12 + i.toDouble(),
                                color: color,
                              ),
                            ),
                          ),
                        Transform.scale(
                          scale: 1 + t * .18,
                          child: Icon(icon, size: 100, color: color),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Visual preview only. No gift is sent and no coins are spent.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: sound.muted ? 'Enable gift sound' : 'Mute gift sound',
          onPressed: () {
            setState(() => sound.muted = !sound.muted);
            if (sound.muted) {
              sound.stop();
            } else {
              sound.play(widget.name);
            }
          },
          icon: Icon(
            sound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
