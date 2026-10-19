import 'package:flutter/material.dart';

class GiftChoice {
  final String id, name;
  final int coins;
  final IconData icon;
  final Color color;
  const GiftChoice(this.id, this.name, this.coins, this.icon, this.color);
}

// Display prices only. A live gift must use a server-owned price and atomic
// wallet settlement; the client must never debit balances itself.
const giftChoices = <GiftChoice>[
  GiftChoice('heart', 'Heart', 10, Icons.favorite_rounded, Colors.pink),
  GiftChoice('rose', 'Rose', 20, Icons.local_florist_rounded, Colors.pinkAccent),
  GiftChoice('diamond', 'Diamond', 100, Icons.diamond_rounded, Colors.cyan),
  GiftChoice('hands', 'Holding hands', 200, Icons.handshake_rounded, Colors.cyan),
  GiftChoice('starlight', 'Starlight', 500, Icons.auto_awesome_rounded, Colors.purpleAccent),
  GiftChoice('cp_heart', 'CP Heart', 1000, Icons.favorite_rounded, Colors.redAccent),
  GiftChoice('castle', 'Castle', 5000, Icons.castle_rounded, Colors.amber),
  GiftChoice('royal_car', 'Royal car', 10000, Icons.directions_car_rounded, Colors.orange),
];

class GiftSeatSelection {
  final GiftChoice gift;
  final int seat;
  final String userId;
  const GiftSeatSelection(this.gift, this.seat, this.userId);
}

class CompactGiftSheet extends StatefulWidget {
  final Map<int, String> recipients;
  const CompactGiftSheet({super.key, required this.recipients});
  @override
  State<CompactGiftSheet> createState() => _CompactGiftSheetState();
}

class _CompactGiftSheetState extends State<CompactGiftSheet> {
  GiftChoice? selected;
  int? seat;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: (MediaQuery.sizeOf(context).height * .48).clamp(260.0, 400.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Gifts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SizedBox(height: 42, child: widget.recipients.isEmpty
            ? const Center(child: Text('No seated recipients.'))
            : ListView(scrollDirection: Axis.horizontal, children: [
                for (final entry in widget.recipients.entries)
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                    label: Text('Seat ${entry.key + 1}'),
                    selected: seat == entry.key,
                    onSelected: (_) => setState(() => seat = entry.key),
                  )),
              ])),
          const SizedBox(height: 6),
          Expanded(child: GridView.builder(
            itemCount: giftChoices.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 3 : 4,
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 118 : 92,
              crossAxisSpacing: 6, mainAxisSpacing: 6),
            itemBuilder: (context, index) {
              final gift = giftChoices[index];
              return InkWell(onTap: () => setState(() => selected = gift), child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: selected == gift ? Colors.amber.withValues(alpha: .16) : Colors.white.withValues(alpha: .04),
                  border: Border.all(color: selected == gift ? Colors.amber : Colors.white12),
                  borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(gift.icon, color: gift.color, size: 30),
                  Text(gift.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  Text('${gift.coins} coins', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.amber, fontSize: 11)),
                ]),
              ));
            },
          )),
          const SizedBox(height: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Preview · no coins spent', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white60)),
            FilledButton(onPressed: selected == null || seat == null ? null : () {
              Navigator.pop(context, GiftSeatSelection(selected!, seat!, widget.recipients[seat]!));
            }, child: const Text('Preview to seat')),
          ]),
        ]),
      ),
    ),
  );
}

/// Coordinates are in the root overlay, taken from the selected avatar after
/// dismissing the sheet, so scrolling and different seat grids remain correct.
class FlyingSeatGift extends StatelessWidget {
  final GiftChoice gift;
  final Offset start, end;
  final VoidCallback onDone;
  const FlyingSeatGift({super.key, required this.gift, required this.start,
    required this.end, required this.onDone});
  @override
  Widget build(BuildContext context) => IgnorePointer(child: TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context) ? const Duration(milliseconds: 1) : const Duration(milliseconds: 950),
    onEnd: onDone,
    builder: (context, t, _) {
      final p = Offset.lerp(start, end, Curves.easeInOutCubic.transform(t))!;
      final arc = 60 * 4 * t * (1 - t);
      return Stack(children: [Positioned(left: p.dx - 24, top: p.dy - 24 - arc,
        child: Opacity(opacity: t > .9 ? (1-t)*10 : 1,
          child: Icon(gift.icon, color: gift.color, size: 48)))]);
    },
  ));
}
