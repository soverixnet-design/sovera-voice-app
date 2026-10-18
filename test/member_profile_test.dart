import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/member_profile.dart';

class FakeProfileStore extends MemberProfileStore {
  bool following = false, fail = false;
  List<String> equipped = [];
  @override
  Future<Map<String, dynamic>?> card(String target, String viewer) async => {
    'user_id': target,
    'uid': 10000001,
    'display_name': 'Sovera member',
    'bio': '',
    'medal_styles': equipped,
  };
  @override
  Future<List<Map<String, dynamic>>> gifts(String target) async => [];
  @override
  Future<bool> follows(String viewer, String target) async => following;
  @override
  Future<void> follow(String viewer, String target, bool value) async {
    if (fail) throw Exception();
    following = value;
  }

  @override
  Future<void> medals(String viewer, List<String> values) async {
    equipped = values;
  }
}

class FakeMessages extends DirectMessageStore {
  bool fail = false;
  final sent = <String>[];
  @override
  Future<List<Map<String, dynamic>>> messages(
    String viewer,
    String target,
  ) async => sent.map((b) => {'sender_id': viewer, 'body': b}).toList();
  @override
  Future<void> send(String viewer, String target, String body) async {
    if (fail) throw Exception();
    sent.add(body);
  }
}

void main() {
  testWidgets(
    'Profile has six-digit ID and follow commits only after server success',
    (tester) async {
      final store = FakeProfileStore();
      await tester.pumpWidget(
        MaterialApp(
          home: MemberProfilePage(
            targetId: 'target',
            viewerId: 'viewer',
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ID · 10000001'), findsOneWidget);
      expect(find.text('No received gifts yet.'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(store.following, isTrue);
      expect(find.text('Unfollow'), findsOneWidget);
      store.fail = true;
      await tester.tap(find.text('Unfollow'));
      await tester.pumpAndSettle();
      expect(store.following, isTrue);
      expect(find.text('Unfollow'), findsOneWidget);
    },
  );
  testWidgets('Owner equips saved medals and does not follow self', (
    tester,
  ) async {
    final store = FakeProfileStore();
    await tester.pumpWidget(
      MaterialApp(
        builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(disableAnimations:true),child:child!),
        home: MemberProfilePage(
          targetId: 'viewer',
          viewerId: 'viewer',
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsNothing);
    await tester.ensureVisible(find.text('gold'));
    await tester.tap(find.text('gold'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.equipped, contains('gold'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Chat keeps failed draft and sends real store message once', (
    tester,
  ) async {
    final store = FakeMessages()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DirectChatPage(
          viewerId: 'viewer',
          targetId: 'target',
          name: 'Friend',
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Hello',
    );
    expect(store.sent, isEmpty);
    store.fail = false;
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(store.sent, ['Hello']);
    expect(find.text('Hello'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Profile fits compact screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
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
        home: MemberProfilePage(
          targetId: 'target',
          viewerId: 'viewer',
          store: FakeProfileStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
