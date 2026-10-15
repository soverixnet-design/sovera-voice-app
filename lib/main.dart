import 'package:flutter/material.dart';

void main() => runApp(const Sovera());
const violet = Color(0xFF8C69FF);
const ink = Color(0xFF0C0D1C);
const cyan = Color(0xFF69E4EB);

class Sovera extends StatelessWidget {
  const Sovera({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sovera', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: ink, colorScheme: const ColorScheme.dark(primary: violet, secondary: cyan),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    ), home: const Home(),
  );
}

class Glass extends StatelessWidget {
  final Widget child;
  final Color tint;
  final EdgeInsets padding;
  const Glass({super.key, required this.child, this.tint = violet, this.padding = const EdgeInsets.all(18)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .22), const Color(0xFF17192C), const Color(0xFF111222)]),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
      boxShadow: [BoxShadow(color: tint.withValues(alpha: .12), blurRadius: 24, offset: const Offset(0, 12))],
    ), child: child,
  );
}

class Jewel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const Jewel(this.icon, {super.key, this.color = violet, this.size = 54});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * .32),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, .45)!, color, Color.lerp(color, Colors.black, .4)!]),
      border: Border.all(color: Colors.white.withValues(alpha: .32)),
      boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 16, offset: const Offset(0, 7))]),
    child: Icon(icon, color: Colors.white, size: size * .49),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  int tab = 0;
  String query = '';
  final search = TextEditingController();
  final rooms = <String, (IconData, Color, String)>{
    'Moonlight Lounge': (Icons.nightlight_round, violet, 'Music & conversation'),
    'Ocean Avenue': (Icons.waves_rounded, cyan, 'A little space to unwind'),
    'Golden Hour': (Icons.wb_sunny_rounded, const Color(0xFFFFC477), 'Meet your next good friend'),
    'Sovera Studio': (Icons.mic_rounded, const Color(0xFFFF8CAF), 'Your voice. Your stage.'),
  };
  void notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  void dispose() { search.dispose(); super.dispose(); }
  void openRoom(String name) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VoiceRoom(name: name)));
  Widget heading(String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -.8)),
    const SizedBox(height: 6), Text(subtitle, style: const TextStyle(color: Colors.white54)),
  ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28), children: [
        Row(children: [const Jewel(Icons.graphic_eq_rounded, size: 42), const SizedBox(width: 12), const Text('sovera', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -1)), const Spacer(), IconButton(tooltip: 'About this preview', onPressed: () => notice('Offline design preview. Voice, payments and login are not connected.'), icon: const Icon(Icons.info_outline_rounded))]),
        const SizedBox(height: 14), const Chip(avatar: Icon(Icons.science_outlined, size: 16), label: Text('OFFLINE DESIGN PREVIEW')),
        const SizedBox(height: 22),
        if(tab == 0) ...[
          heading('Find your people.', 'Beautiful rooms. Better conversations.'), const SizedBox(height: 24),
          Glass(tint: violet, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Chip(label: Text('THE SOVERA EXPERIENCE')), Spacer(), Jewel(Icons.auto_awesome_rounded, color: cyan)]),
            const SizedBox(height: 18), const Text('Every voice\nhas a place.', style: TextStyle(fontSize: 34, height: 1.12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14), const Text('Create your own corner of the world.', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 20), FilledButton.icon(onPressed: createRoom, icon: const Icon(Icons.add_rounded), label: const Text('Create a room')),
          ])), const SizedBox(height: 24),
          TextField(controller: search, onChanged: (value) => setState(() => query = value), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Search preview rooms', filled: true, fillColor: Colors.white.withValues(alpha: .04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
          const SizedBox(height: 24), const Text('Explore rooms', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 14),
          for (final entry in rooms.entries.where((e) => e.key.toLowerCase().contains(query.toLowerCase()))) Padding(padding: const EdgeInsets.only(bottom: 14), child: Semantics(button: true, label: 'Open ${entry.key}', child: InkWell(borderRadius: BorderRadius.circular(26), onTap: () => openRoom(entry.key), child: Glass(tint: entry.value.$2, child: Row(children: [Jewel(entry.value.$1, color: entry.value.$2, size: 66), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(entry.key, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(entry.value.$3, style: const TextStyle(color: Colors.white54, fontSize: 12)), const SizedBox(height: 10), const Text('PREVIEW ROOM', style: TextStyle(color: cyan, fontSize: 10, letterSpacing: 2))])), const Icon(Icons.arrow_forward_ios_rounded, size: 16)]))))),
          if(rooms.keys.where((e) => e.toLowerCase().contains(query.toLowerCase())).isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No rooms match your search.')),
        ],
        if(tab == 1) ...[heading('Moments', 'A space for stories worth sharing.'), const SizedBox(height: 24), const Glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Jewel(Icons.auto_awesome_rounded, color: cyan), SizedBox(height: 24), Text('Welcome to Sovera', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), SizedBox(height: 12), Text('This is a sample community post. Real posts and comments need the social backend.', style: TextStyle(color: Colors.white60))]))],
        if(tab == 2) ...[heading('Messages', 'Your conversations, all together.'), const SizedBox(height: 24),
          for(final item in [(Icons.support_agent_rounded, 'Official support', const Color(0xFFFFB782)), (Icons.campaign_rounded, 'Official notices', cyan), (Icons.account_balance_wallet_rounded, 'Recharge support', violet)]) Padding(padding: const EdgeInsets.only(bottom: 14), child: InkWell(onTap: () => notice('${item.$2} needs the support backend.'), child: Glass(tint: item.$3, child: Row(children: [Jewel(item.$1, color: item.$3), const SizedBox(width: 16), Expanded(child: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right_rounded)])))),
          const SizedBox(height: 22), const Text('No conversations yet. Sign-in and live messaging will be connected in the backend phase.', style: TextStyle(color: Colors.white54)),
        ],
        if(tab == 3) ...[heading('Your space', 'Make it feel like you.'), const SizedBox(height: 24),
          const Glass(child: Column(children: [Jewel(Icons.person_rounded, size: 90), SizedBox(height: 18), Text('Preview guest', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)), SizedBox(height: 8), Text('Not signed in', style: TextStyle(color: Colors.white54))])),
          const SizedBox(height: 18), Glass(tint: cyan, child: Column(children: [const ListTile(leading: Icon(Icons.toll_rounded, color: Color(0xFFFFCC7E)), title: Text('Coins'), trailing: Text('0')), const ListTile(leading: Icon(Icons.diamond_outlined, color: cyan), title: Text('Diamonds'), trailing: Text('0')), const Divider(), const Text('100 Diamonds = 70 Coins', style: TextStyle(color: Colors.white60)), const SizedBox(height: 12), OutlinedButton(onPressed: () => notice('Exchange requires a signed-in account and server-verified balance.'), child: const Text('Exchange diamonds'))])),
        ],
      ],
    )))),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, backgroundColor: const Color(0xFF141527), onDestinationSelected: (value) => setState(() => tab = value), destinations: const [
      NavigationDestination(icon: Icon(Icons.spatial_audio_off_rounded), label: 'Rooms'), NavigationDestination(icon: Icon(Icons.auto_awesome_rounded), label: 'Moments'), NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Messages'), NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Me'),
    ]),
  );
  Future<void> createRoom() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Create preview room'), content: TextField(controller: controller, maxLength: 40, autofocus: true, decoration: const InputDecoration(labelText: 'Room name')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { if(controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim()); }, child: const Text('Create'))]));
    // Let the dialog route finish its disposal before releasing the controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if(!mounted || value == null) return;
    setState(() => rooms[value] = (Icons.mic_rounded, violet, 'Your local preview room'));
    openRoom(value);
  }
}

class VoiceRoom extends StatefulWidget {
  final String name;
  const VoiceRoom({super.key, required this.name});
  @override
  State<VoiceRoom> createState() => _VoiceRoomState();
}
class _VoiceRoomState extends State<VoiceRoom> {
  int seats = 9;
  int? mySeat;
  final messages = <String>[];
  final input = TextEditingController();
  void notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  void dispose() { input.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name), backgroundColor: ink, actions: [IconButton(tooltip: 'Seat settings', onPressed: settings, icon: const Icon(Icons.tune_rounded))]),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(22), children: [
        const Center(child: Chip(avatar: Icon(Icons.headphones_rounded, size: 18), label: Text('PREVIEW • AUDIO NOT CONNECTED'))), const SizedBox(height: 18),
        const Glass(tint: cyan, child: Row(children: [Jewel(Icons.workspace_premium_rounded, color: Color(0xFFFFC477), size: 48), SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('A room for good energy', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Tap an empty seat to try the layout.', style: TextStyle(color: Colors.white54, fontSize: 12))]))])),
        const SizedBox(height: 28),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: seats, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: 118, mainAxisSpacing: 10, crossAxisSpacing: 10), itemBuilder: (context, index) => Semantics(button: true, label: 'Seat ${index+1}', child: InkWell(borderRadius: BorderRadius.circular(26), onTap: () => setState(() => mySeat = mySeat == index ? null : index), child: Glass(padding: const EdgeInsets.all(10), tint: mySeat == index ? cyan : violet, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Jewel(mySeat == index ? Icons.person_rounded : Icons.add_rounded, color: mySeat == index ? cyan : violet, size: 46), const SizedBox(height: 8), Text(mySeat == index ? 'You · preview' : 'Seat ${index+1}', style: const TextStyle(fontSize: 11, color: Colors.white60))]))))),
        const SizedBox(height: 26), const Text('Room conversation', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
        const Text('Messages below are local to this preview session.', style: TextStyle(color: Colors.white38, fontSize: 12)), const SizedBox(height: 12),
        for(final message in messages) Padding(padding: const EdgeInsets.only(bottom: 8), child: Glass(padding: const EdgeInsets.all(12), child: Text('You: $message'))),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 18), child: Row(children: [
        IconButton.filledTonal(tooltip: 'Microphone unavailable in preview', onPressed: () => notice('Voice is not connected. An RTC token server and Agora SDK integration are required.'), icon: const Icon(Icons.mic_off_rounded)), const SizedBox(width: 8),
        Expanded(child: TextField(controller: input, maxLength: 300, decoration: const InputDecoration(hintText: 'Local preview message', counterText: '', border: InputBorder.none), onSubmitted: (_) => send())),
        IconButton(tooltip: 'Send local message', onPressed: send, icon: const Icon(Icons.send_rounded, color: cyan)),
        IconButton.filled(tooltip: 'Preview gifts', onPressed: gifts, icon: const Icon(Icons.card_giftcard_rounded)),
      ])),
    ])))),
  );
  void send() { if(input.text.trim().isEmpty) return; setState(() { messages.add(input.text.trim()); input.clear(); }); }
  Future<void> settings() async {
    int draft = seats;
    final selected = await showModalBottomSheet<int>(context: context, showDragHandle: true, isScrollControlled: true, builder: (context) => StatefulBuilder(builder: (context, update) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Room seats', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Changes apply after you save.'), const SizedBox(height: 20), Wrap(spacing: 10, children: [5,6,9,12].map((count) => ChoiceChip(label: Text('$count seats'), selected: draft == count, onSelected: (_) => update(() => draft = count))).toList()), const SizedBox(height: 22), SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, draft), child: const Text('Save seat layout')))])))));
    if(!mounted || selected == null) return;
    setState(() { seats = selected; if(mySeat != null && mySeat! >= seats) mySeat = null; });
    notice('Seat layout saved for this preview session.');
  }
  void gifts() => showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('The gift collection', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 10), const Text('Visual preview · no wallet transaction', style: TextStyle(color: Colors.white54)), const SizedBox(height: 24), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [for(final item in [(Icons.favorite_rounded, 'Heart', const Color(0xFFFF8CAF)), (Icons.diamond_rounded, 'Diamond', cyan), (Icons.castle_rounded, 'Castle', violet)]) Column(children: [Jewel(item.$1, color: item.$3, size: 70), const SizedBox(height: 10), Text(item.$2)])]), const SizedBox(height: 24)]))));
}
