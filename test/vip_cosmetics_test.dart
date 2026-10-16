import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/account_cards.dart';
import 'package:sovera/cosmetic_art.dart';
import 'package:sovera/effects_studio.dart';
import 'package:sovera/main.dart';

Future<void> chooseVip(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Sovera VIP7').first);
  await tester.tap(find.text('Sovera VIP7').first);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) {
    final tabs = ['Frame', 'Entry', 'Speaking glow', 'Medal', 'Name tag'];
    await tester.scrollUntilVisible(target, tabs.contains(text) ? -180 : 180,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(resetCosmeticPreviews);
  tearDown(resetCosmeticPreviews);

  testWidgets(
    'Selected medal and tag appear on profile without changing verified levels',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EffectsStudio()));
      await chooseVip(tester);
      await press(tester, 'Medal');
      await press(tester, 'Use medal in preview');
      await press(tester, 'Name tag');
      await press(tester, 'Use name tag in preview');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileIdentityCard(
                name: 'Test member',
                bio: '',
                onEdit: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Style preview'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CosmeticArt && w.asset.endsWith('legend-tag.webp'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CosmeticArt && w.asset.endsWith('top-host-medal.webp'),
        ),
        findsOneWidget,
      );
      expect(find.text('Lv. —'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Selected phoenix entry plays on room visit and closes automatically',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EffectsStudio()));
      await chooseVip(tester);
      await press(tester, 'Entry');
      await press(tester, 'Use entry in preview');
      await tester.pumpWidget(
        const MaterialApp(home: VoiceRoom(name: 'Preview room')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Sovera arrival preview'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CosmeticArt && w.asset.endsWith('phoenix-entry.webp'),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('Sovera arrival preview'), findsNothing);
      expect(find.text('Preview room'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reset clears every applied cosmetic', (tester) async {
    previewAvatarFrame.value = effectPacks.last;
    previewEntryEffect.value = effectPacks.last;
    previewMedal.value = effectPacks.last;
    previewNameTag.value = effectPacks.last;
    await tester.pumpWidget(const MaterialApp(home: EffectsStudio()));
    await press(tester, 'Reset preview styles');
    expect(previewAvatarFrame.value, isNull);
    expect(previewEntryEffect.value, isNull);
    expect(previewMedal.value, isNull);
    expect(previewNameTag.value, isNull);
  });

  testWidgets('Reduced motion leaves equipped artwork still', (tester) async {
    previewAvatarFrame.value = effectPacks.last;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: FramePreviewAdapter(child: Text('Avatar'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('VIP medal and tag remain within a compact large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const EffectsStudio(),
      ),
    );
    await chooseVip(tester);
    await press(tester, 'Medal');
    await press(tester, 'Play animation');
    expect(tester.takeException(), isNull);
    await press(tester, 'Name tag');
    await press(tester, 'Play animation');
    expect(tester.takeException(), isNull);
  });
}
