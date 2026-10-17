import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_gate.dart';
import 'main.dart' show BrandLogo, Glass, gold, cyan;
import 'member_directory.dart' show SupabaseMemberStore;
import 'room_media.dart' show GiftAnimationCard;

class MemberProfileStore {
  const MemberProfileStore();
  Future<Map<String, dynamic>?> card(String target, String viewer) async {
    var row = await soveraClient
        .from('sovera_member_cards')
        .select()
        .eq('user_id', target)
        .maybeSingle();
    if (row == null && target == viewer) {
      final own = await soveraClient
          .from('sovera_profiles')
          .select()
          .eq('id', viewer)
          .single();
      await soveraClient
          .from('sovera_member_cards')
          .upsert(
            {
              'user_id': viewer,
              'uid': own['uid'],
              'display_name': own['display_name'],
              'avatar_url': own['avatar_url'],
              'bio': own['bio'],
              'listed': false,
            },
            onConflict: 'user_id',
            ignoreDuplicates: true,
          );
      row = await soveraClient
          .from('sovera_member_cards')
          .select()
          .eq('user_id', target)
          .maybeSingle();
    }
    return row;
  }

  Future<List<Map<String, dynamic>>> gifts(String target) async =>
      await soveraClient
          .from('sovera_profile_gifts')
          .select('gift_key,quantity,created_at')
          .eq('recipient_id', target)
          .order('created_at', ascending: false)
          .limit(50);
  Future<bool> follows(String viewer, String target) async =>
      await soveraClient
          .from('sovera_user_follows')
          .select('following_id')
          .eq('follower_id', viewer)
          .eq('following_id', target)
          .maybeSingle() !=
      null;
  Future<void> follow(String viewer, String target, bool value) =>
      const SupabaseMemberStore().follow(viewer, target, value);
  Future<void> medals(String viewer, List<String> values) async {
    await soveraClient
        .from('sovera_member_cards')
        .update({'medal_styles': values})
        .eq('user_id', viewer)
        .select('user_id')
        .single();
  }
}

class MemberProfilePage extends StatefulWidget {
  final String targetId, viewerId;
  final MemberProfileStore store;
  const MemberProfilePage({
    super.key,
    required this.targetId,
    required this.viewerId,
    this.store = const MemberProfileStore(),
  });
  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  Map<String, dynamic>? card;
  List<Map<String, dynamic>> gifts = [];
  bool loading = true, busy = false, following = false;
  String? error;
  bool get own => widget.targetId == widget.viewerId;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final row = await widget.store.card(widget.targetId, widget.viewerId);
      if (row == null) {
        if (mounted) setState(() => error = 'This profile is not shared.');
        return;
      }
      final received = await widget.store.gifts(widget.targetId);
      final followed = own
          ? false
          : await widget.store.follows(widget.viewerId, widget.targetId);
      if (mounted)
        setState(() {
          card = row;
          gifts = received;
          following = followed;
        });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not load this profile. Please retry.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void notice(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> toggleFollow() async {
    if (busy || own) return;
    setState(() => busy = true);
    try {
      await widget.store.follow(widget.viewerId, widget.targetId, !following);
      if (mounted) setState(() => following = !following);
    } catch (_) {
      notice('Follow change was not saved. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleMedal(String key) async {
    if (busy || !own) return;
    final values = List<String>.from(card?['medal_styles'] as List? ?? const <String>[]);
    values.contains(key) ? values.remove(key) : values.add(key);
    setState(() => busy = true);
    try {
      await widget.store.medals(widget.viewerId, values);
      if (mounted) setState(() => card = {...card!, 'medal_styles': values});
    } catch (_) {
      notice('Medal styles were not saved. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Member profile'),
      actions: [
        IconButton(
          tooltip: 'Refresh profile',
          onPressed: loading || busy ? null : load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: TextButton(onPressed: load, child: Text(error!)),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Glass(
                tint: cyan,
                child: Column(
                  children: [
                    ClipOval(
                      child: card?['avatar_url'] is String
                          ? Image.network(
                              card!['avatar_url'] as String,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const BrandLogo(size: 96),
                            )
                          : const BrandLogo(size: 96),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      card!['display_name'].toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SelectableText(
                          'ID · ${card!['uid']}',
                          style: const TextStyle(color: cyan),
                        ),
                        IconButton(
                          tooltip: 'Copy member ID',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: card!['uid'].toString()),
                            );
                            notice('User ID copied.');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                      ],
                    ),
                    if ((card?['bio'] ?? '').toString().isNotEmpty)
                      Text(card!['bio'].toString(), textAlign: TextAlign.center),
                    if (!own)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: busy ? null : toggleFollow,
                            icon: Icon(
                              following
                                  ? Icons.person_remove_alt_1_rounded
                                  : Icons.person_add_alt_1_rounded,
                            ),
                            label: Text(
                              busy
                                  ? 'Saving…'
                                  : following
                                  ? 'Unfollow'
                                  : 'Follow',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => DirectChatPage(
                                  viewerId: widget.viewerId,
                                  targetId: widget.targetId,
                                  name: card!['display_name'].toString(),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('Chat'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Profile medals',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Decorative medal styles · Ranking awards are separate.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 10),
              if ((card?['medal_styles'] as List? ?? []).isEmpty && !own)
                const Text('No medal styles equipped.'),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in ['gold', 'silver', 'bronze'])
                    if (own ||
                        (card!['medal_styles'] as List? ?? []).contains(key))
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/medals/$key.${MediaQuery.disableAnimationsOf(context) ? 'png' : 'webp'}',
                            width: 76,
                            height: 88,
                            semanticLabel: '$key profile medal',
                          ),
                          if (own)
                            FilterChip(
                              label: Text(key),
                              selected: (card!['medal_styles'] as List? ?? [])
                                  .contains(key),
                              onSelected: busy ? null : (_) => toggleMedal(key),
                            ),
                        ],
                      ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Recent gifts received',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (gifts.isEmpty)
                const Glass(child: Text('No received gifts yet.')),
              for (final gift in gifts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Glass(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.card_giftcard_rounded,
                        color: gold,
                      ),
                      title: Text(gift['gift_key'].toString()),
                      subtitle: Text('Quantity · ${gift['quantity']}'),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => GiftAnimationCard(
                          name: gift['gift_key'].toString(),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheet) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        const ListTile(
                          title: Text('Gift animation previews'),
                          subtitle: Text(
                            'Live gift sending is not connected yet.',
                          ),
                        ),
                        for (final name in [
                          'Heart',
                          'Diamond',
                          'Castle',
                          'Rose',
                          'Royal car',
                          'Starlight',
                          'Holding hands',
                          'CP Heart',
                        ])
                          ListTile(
                            leading: const Icon(
                              Icons.card_giftcard_rounded,
                              color: gold,
                            ),
                            title: Text(name),
                            onTap: () => showDialog<void>(
                              context: sheet,
                              builder: (_) => GiftAnimationCard(name: name),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: const Text('View gift animations'),
              ),
            ],
          ),
  );
}

class DirectMessageStore {
  const DirectMessageStore();
  Future<List<Map<String, dynamic>>> messages(
    String viewer,
    String target,
  ) async {
    final rows = await soveraClient
        .from('sovera_direct_messages')
        .select()
        .or(
          'and(sender_id.eq.$viewer,recipient_id.eq.$target),and(sender_id.eq.$target,recipient_id.eq.$viewer)',
        )
        .order('created_at', ascending: false)
        .limit(200);
    return rows.reversed.toList();
  }

  Future<void> send(String viewer, String target, String body) async {
    await soveraClient.from('sovera_direct_messages').insert({
      'sender_id': viewer,
      'recipient_id': target,
      'body': body,
    });
  }
}

class DirectChatPage extends StatefulWidget {
  final String viewerId, targetId, name;
  final DirectMessageStore store;
  const DirectChatPage({
    super.key,
    required this.viewerId,
    required this.targetId,
    required this.name,
    this.store = const DirectMessageStore(),
  });
  @override
  State<DirectChatPage> createState() => _DirectChatPageState();
}

class _DirectChatPageState extends State<DirectChatPage>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, dynamic>> rows = [];
  Timer? timer;
  bool sending = false, loading = true, fetching = false, active = true;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (active) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching || !mounted) return;
    fetching = true;
    try {
      final result = await widget.store.messages(
        widget.viewerId,
        widget.targetId,
      );
      if (mounted)
        setState(() {
          rows = result;
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'Messages could not refresh. Retry.');
    } finally {
      fetching = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final body = input.text.trim();
    if (body.isEmpty || body.length > 1000 || sending) return;
    setState(() => sending = true);
    try {
      await widget.store.send(widget.viewerId, widget.targetId, body);
      if (!mounted) return;
      input.clear();
      await load();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients)
          scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message was not sent. Your draft is kept.'),
          ),
        );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) TextButton(onPressed: load, child: Text(error!)),
          Expanded(
            child: rows.isEmpty && !loading
                ? const Center(child: Text('No messages yet.'))
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final row in rows)
                        Align(
                          alignment: row['sender_id'] == widget.viewerId
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: row['sender_id'] == widget.viewerId
                                  ? cyan.withValues(alpha: .2)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(row['body'].toString()),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    enabled: !sending,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Message…',
                      counterText: '',
                    ),
                    onSubmitted: (_) => send(),
                  ),
                ),
                IconButton(
                  tooltip: 'Send message',
                  onPressed: sending ? null : send,
                  icon: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, color: cyan),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class DirectInboxPage extends StatefulWidget {
  final String viewerId;
  const DirectInboxPage({super.key,required this.viewerId});
  @override State<DirectInboxPage> createState()=>_DirectInboxPageState();
}
class _DirectInboxPageState extends State<DirectInboxPage> {
  List<Map<String,dynamic>> threads=[];
  bool loading=true;String? error;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    setState((){loading=true;error=null;});
    try{
      final messages=await soveraClient.from('sovera_direct_messages').select('sender_id,recipient_id,body,created_at').order('created_at',ascending:false).limit(200);
      final latest=<String,Map<String,dynamic>>{};
      for(final message in messages){final other=(message['sender_id']==widget.viewerId?message['recipient_id']:message['sender_id']) as String;latest.putIfAbsent(other,()=>{...message,'target':other});}
      final cards=latest.isEmpty?<Map<String,dynamic>>[]:await soveraClient.from('sovera_member_cards').select('user_id,display_name,uid').inFilter('user_id',latest.keys.toList());
      final names={for(final card in cards)card['user_id']:card};
      if(mounted)setState(()=>threads=[for(final entry in latest.entries){...entry.value,'name':names[entry.key]?['display_name']??'Member','uid':names[entry.key]?['uid']}]);
    }catch(_){if(mounted)setState(()=>error='Could not load conversations. Please retry.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Private chats'),actions:[IconButton(tooltip:'Refresh chats',onPressed:loading?null:load,icon:const Icon(Icons.refresh_rounded))]),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:TextButton(onPressed:load,child:Text(error!))):threads.isEmpty?const Center(child:Text('No conversations yet. Open a member profile to chat.')):ListView(padding:const EdgeInsets.all(16),children:[for(final thread in threads)Card(child:ListTile(leading:const Icon(Icons.chat_bubble_outline_rounded,color:cyan),title:Text(thread['uid']==null?thread['name'].toString():'${thread['name']} · ${thread['uid']}'),subtitle:Text(thread['body'].toString(),maxLines:2,overflow:TextOverflow.ellipsis),onTap:() async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>DirectChatPage(viewerId:widget.viewerId,targetId:thread['target'] as String,name:thread['name'].toString())));if(mounted)await load();}))]));
}
