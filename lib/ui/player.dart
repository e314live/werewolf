import 'package:flutter/material.dart';

import '../core/judge.dart';
import '../core/protocol.dart';
import '../net/lan.dart';
import 'common.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerState();
}

class _PlayerState extends State<PlayerPage> {
  final ipCtrl = TextEditingController(text: '192.168.');
  final nameCtrl = TextEditingController(text: '');
  final guest = LanGuest();

  String stage = 'connect'; // connect|wait|play|over
  String? err;
  int seat = -1;
  String yourName = '';
  Role? role;
  int seatCount = 9;
  List<int> alive = [];
  List<int> deaths = [];

  String? actor;        // 轮到我做哪个动作
  List<int> wolves = [];
  String? seerResult;   // 预言家验到的角色名
  int? nightVictim;     // 女巫看到的死者
  bool useHeal = false;
  int? poisonTarget;
  bool voting = false;      // 是否处于投票阶段
  Map<String, dynamic> tally = {};
  String? winner;

  bool get myTurn => actor != null;

  @override
  void initState() {
    super.initState();
    guest.listeners.add(_onMsg);
  }

  void _onMsg(Map<String, dynamic> m) {
    final t = m['t'] as String?;
    final d = (m['d'] as Map?) ?? {};
    if (!mounted) return;
    setState(() {
      switch (t) {
        case 'role':
          role = Role.values[(d['role'] as int?) ?? Role.villager.index];
          yourName = (d['name'] as String?) ?? '';
          stage = 'play';
        case 'roster':
          seatCount = (d['seats'] as List?)?.length ?? seatCount;
        case 'phase':
          final p = d['phase'] as String?;
          alive = List<int>.from(d['alive'] as List? ?? const []);
          deaths = List<int>.from(d['deaths'] as List? ?? const []);
          if (p == 'dawn' || p == 'vote_revote') {
            actor = null;
          }
          if (p == 'vote_revote') tally = {};
        case 'wake':
          actor = d['actor'] as String?;
          wolves = List<int>.from(d['wolves'] as List? ?? const []);
          seerResult = d['checked'] as String?;
          nightVictim = d['target'] as int?;
          useHeal = false;
          poisonTarget = null;
        case 'vote_open':
          actor = null;
          voting = true;
          tally = {};
        case 'vote_result':
          voting = false;
          final t = d['tally'];
          tally = t is Map ? Map<String, dynamic>.from(t) : {};
        case 'over':
          winner = d['winner'] as String?;
          actor = null;
          stage = 'over';
        case 'cancel':
          tally = {};
      }
    });
  }

  Future<void> _connect() async {
    final host = ipCtrl.text.trim();
    if (host.isEmpty) return;
    setState(() => err = null);
    final e = await guest.connect(host, lanPort, onMsg: _onMsg);
    if (!mounted) return;
    if (e != null) {
      setState(() => err = e);
      return;
    }
    guest.send(msgJoin(nameCtrl.text.trim().isEmpty ? '玩家' : nameCtrl.text.trim()));
    setState(() => stage = 'wait');
  }

  // save / poison 在协议里都是"目标座位号"，类型是 int? 不是 bool?
  void _sendAct(String kind, {int? target, int? save, int? poison}) {
    guest.send(actMsg(kind, target: target, save: save, poison: poison));
    setState(() => actor = null);
  }

  @override
  void dispose() {
    guest.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入牌局')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (stage == 'connect') _connectView(),
          if (stage == 'wait') _waitView(),
          if (stage == 'play') _playView(),
          if (stage == 'over') _overView(),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(err!, style: const TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  Widget _connectView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('房主开房间后会显示一个地址，填进来就行',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 18),
        const Text('你的名字', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: '比如 老张'),
        ),
        const SizedBox(height: 14),
        const Text('房主地址', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(
          controller: ipCtrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '192.168.x.x'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _connect,
          icon: const Icon(Icons.login),
          label: const Text('进入房间'),
        ),
      ],
    );
  }

  Widget _waitView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(top: 120),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('已连上法官，等房主发牌…', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _playView() {
    if (myTurn) return _actionView();
    if (voting) return _voteView();
    if (deaths.isNotEmpty && role != null) return _dawnView();
    return _idleView();
  }

  /// 白天投票界面
  Widget _voteView() {
    final ejected = tally['ejected'] as int?;
    if (ejected != null) {
      return Panel(
        color: const Color(0xFFD33F49),
        icon: Icons.gavel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('投票结果', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('${ejected + 1} 号被放逐',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFD33F49))),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🗳️ 投票 — 把你怀疑的人投出去',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('投完就等票数结算（你的票别人看不到）',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 18),
        PickerGrid(
          seatCount: seatCount,
          target: -1,
          dead: _deadSeats(),
          onPick: (t) {
            guest.send(actMsg('vote', target: t));
            setState(() => voting = false);
          },
          label: '点一个座位',
        ),
      ],
    );
  }

  Widget _idleView() {
    final dead = deaths;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoleCard(
          role: role!,
          name: '${seat + 1} 号 · $yourName',
        ),
        const SizedBox(height: 18),
        Panel(
          color: const Color(0xFF3B3350),
          icon: Icons.emoji_events_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('局势', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text('存活：${alive.isEmpty ? seatCount : alive.length} 人',
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ...List.generate(seatCount, (i) => Chip(
                        label: Text('${i + 1}'),
                        backgroundColor: alive.contains(i)
                            ? (deaths.contains(i) ? const Color(0xFF2A2538) : const Color(0xFF3B3350))
                            : const Color(0xFF2A2538),
                      )),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (dead.isNotEmpty)
          Text(
            dead.map((x) => '${x + 1} 号出局').join('，'),
            style: const TextStyle(color: Color(0xFFD33F49), fontWeight: FontWeight.w800),
          ),
        if (role != Role.werewolf)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('盯紧发言，别被票出去',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _dawnView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('☀️ 天亮了', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Panel(
          color: const Color(0xFFD33F49),
          icon: Icons.report,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: deaths
                .map((x) => Text('${x + 1} 号出局',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFD33F49))))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _actionView() {
    switch (actor) {
      case 'guard':
        return _simplePick('守卫', '今晚要守护谁？（不能守护自己）', (t) => _sendAct('guard', target: t));
      case 'werewolf':
        return _wolfView();
      case 'seer':
        return _simplePick('预言家', '要验几号？', (t) => _sendAct('seer', target: t));
      case 'witch':
        return _witchView();
      case 'seer_result':
        return _seerResultView();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _seerResultView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🔮 查验结果', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Panel(
          color: const Color(0xFFE8A33D),
          icon: Icons.visibility,
          child: Text(
            seerResult ?? '未知',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFE8A33D)),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () {
            guest.send(msgReady());
            setState(() => actor = null);
          },
          icon: const Icon(Icons.check),
          label: const Text('记住了，闭眼'),
        ),
      ],
    );
  }

  Widget _simplePick(String title, String hint, ValueChanged<int> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('👁 $title 请睁眼', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(hint, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 18),
        PickerGrid(
          seatCount: seatCount,
          target: -1,
          dead: alive.isEmpty ? [] : _deadSeats(),
          onPick: onPick,
          label: '点一个座位',
        ),
      ],
    );
  }

  List<int> _deadSeats() {
    final out = <int>[];
    for (var i = 0; i < seatCount; i++) {
      if (!alive.contains(i) && i != seat) out.add(i);
    }
    return out;
  }

  Widget _wolfView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🐺 狼人请睁眼', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        if (wolves.isNotEmpty && wolves.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('你的狼队友：${wolves.map((w) => '${w + 1}号').join('、')}',
                style: const TextStyle(color: Color(0xFFD33F49), fontWeight: FontWeight.w800)),
          ),
        const Text('今晚要刀谁？', style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 18),
        PickerGrid(
          seatCount: seatCount,
          target: -1,
          dead: _deadSeats(),
          onPick: (t) => _sendAct('werewolf', target: t),
          label: '点一个座位（点空白=空刀）',
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () => _sendAct('werewolf', target: null),
          child: const Text('本轮空刀'),
        ),
      ],
    );
  }

  Widget _witchView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🧙 女巫请睁眼', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          nightVictim == null
              ? '今夜没有人被刀'
              : '法官告诉你：今夜 ${nightVictim! + 1} 号被刀了',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 18),
        const Text('① 要不要用解药救他？', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(
          spacing: 12,
          children: [
            ChoiceChip(
              label: const Text('救'),
              selected: useHeal,
              onSelected: (_) => setState(() => useHeal = true),
            ),
            ChoiceChip(
              label: const Text('不救'),
              selected: !useHeal,
              onSelected: (_) => setState(() => useHeal = false),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('② 要不要用毒药毒人？', style: TextStyle(fontWeight: FontWeight.w700)),
        PickerGrid(
          seatCount: seatCount,
          target: poisonTarget ?? -1,
          dead: _deadSeats(),
          onPick: (t) => setState(() => poisonTarget = t),
          label: '点一个座位（再点一次=不用毒）',
        ),
        if (poisonTarget != null)
          OutlinedButton(
            onPressed: () => setState(() => poisonTarget = null),
            child: const Text('取消毒药'),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _sendAct('witch', save: useHeal ? nightVictim : null, poison: poisonTarget),
          icon: const Icon(Icons.check),
          label: const Text('确认'),
        ),
      ],
    );
  }

  Widget _overView() {
    final win = winner == 'good' ? role != Role.werewolf : winner == 'wolf' && role == Role.werewolf;
    return Column(
      children: [
        Icon(win ? Icons.sentiment_very_satisfied : Icons.sentiment_dissatisfied,
            size: 72, color: win ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49)),
        const SizedBox(height: 14),
        Text(win ? '这局你赢了 🎉' : '这局你输了',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: win ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49))),
        const SizedBox(height: 18),
        Panel(
          color: const Color(0xFF3B3350),
          icon: Icons.loyalty,
          child: RoleCard(role: role!, name: '你本局是 ${roleName[role!]}'),
        ),
      ],
    );
  }
}
