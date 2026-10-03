import 'dart:math';

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

  /// 本次开 App 的稳定身份：断线重连时房主凭它认回原来的座位
  final String cid =
      'g${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}';
  final guest = LanGuest(cid);

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
  bool canHeal = true;  // 解药还在
  bool canPoison = true; // 毒药还在
  bool useHeal = false;
  int? poisonTarget;

  bool voting = false;
  bool revoteHint = false;
  int? ejectedSeat;
  int? gunSeat;
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
        case 'seat':
          seat = (d['seat'] as int?) ?? seat;
          seatCount = (d['total'] as int?) ?? seatCount;
        case 'full':
          err = '房间已经坐满了，让房主把人数加一加';
          stage = 'connect';
        case 'role':
          final ri = d['role'];
          role = Role.values[
              ri is int && ri >= 0 && ri < Role.values.length ? ri : Role.villager.index];
          seat = (d['seat'] as int?) ?? seat;
          yourName = (d['name'] as String?) ?? yourName;
          if (alive.isEmpty) alive = List.generate(seatCount, (i) => i);
          stage = 'play';
        case 'roster':
          seatCount = (d['seats'] as List?)?.length ?? seatCount;
        case 'phase':
          final p = d['phase'] as String?;
          if (d['alive'] is List) alive = List<int>.from(d['alive'] as List);
          if (d['deaths'] is List) deaths = List<int>.from(d['deaths'] as List);
          if (p == 'night') {
            // 新一夜：清掉上一轮所有临时状态
            actor = null;
            voting = false;
            ejectedSeat = null;
            gunSeat = null;
            deaths = [];
          }
          if (p == 'dawn') {
            actor = null;
            voting = false;
            ejectedSeat = null;
          }
        case 'wake':
          actor = d['actor'] as String?;
          wolves = List<int>.from(d['wolves'] as List? ?? const []);
          seerResult = d['checked'] as String?;
          nightVictim = d['target'] as int?;
          canHeal = (d['canHeal'] as bool?) ?? true;
          canPoison = (d['canPoison'] as bool?) ?? true;
          useHeal = false;
          poisonTarget = null;
        case 'vote_open':
          actor = null;
          voting = true;
          ejectedSeat = null;
          gunSeat = null;
          revoteHint = (d['revote'] as bool?) ?? false;
          if (d['seats'] is List) alive = List<int>.from(d['seats'] as List);
        case 'vote_result':
          voting = false;
          final tt = d['tally'];
          tally = tt is Map ? Map<String, dynamic>.from(tt) : {};
          ejectedSeat = d['ejected'] as int?;
          gunSeat = d['gun'] as int?;
        case 'over':
          winner = d['winner'] as String?;
          actor = null;
          voting = false;
          stage = 'over';
        case 'gone':
          err = '和房主断开了，重新连一下';
          stage = 'connect';
        case 'cancel':
          tally = {};
      }
    });
  }

  Future<void> _connect() async {
    final a = parseAddr(ipCtrl.text);
    if (a.ip.isEmpty) {
      setState(() => err = '填一下房主屏幕上显示的地址');
      return;
    }
    setState(() {
      err = null;
      stage = 'wait';
    });
    // onMsg 已在 initState 注册，重复传会重复回调
    final nm = nameCtrl.text.trim().isEmpty ? '玩家' : nameCtrl.text.trim();
    final e = await guest.connect(a.ip, a.port, name: nm);
    if (!mounted) return;
    if (e != null) {
      setState(() {
        err = e;
        stage = 'connect';
      });
      return;
    }
  }

  /// save 是「是否用解药」(bool)，poison 是「毒谁」(座位号)
  void _sendAct(String kind, {int? target, bool? save, int? poison}) {
    guest.send(actMsg(kind, target: target, save: save, poison: poison));
    setState(() => actor = null);
  }

  @override
  void dispose() {
    guest.close();
    ipCtrl.dispose();
    nameCtrl.dispose();
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
        const Text('房主开房间后会显示一个地址（长这样 10.16.3.7:7788），照着填就行',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 18),
        const Text('你的名字', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: '比如 老张'),
        ),
        const SizedBox(height: 14),
        const Text('房主地址（支持带端口）', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(
          controller: ipCtrl,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(hintText: '10.16.3.7 或 10.16.3.7:7789'),
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
    return Column(
      children: [
        const SizedBox(height: 100),
        const CircularProgressIndicator(),
        const SizedBox(height: 18),
        Text(
          seat >= 0
              ? '你是 ${seat + 1} 号 · 已连上法官，等房主发牌…'
              : '已连上法官，等房主发牌…',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 28),
        TextButton(
            onPressed: () => setState(() => stage = 'connect'),
            child: const Text('返回重填地址')),
      ],
    );
  }

  Widget _playView() {
    if (myTurn) return _actionView();
    if (voting) return _voteView();
    if (ejectedSeat != null || gunSeat != null) return _resultView();
    if (deaths.isNotEmpty) return _dawnView();
    return _idleView();
  }

  /* ---------------- 投票 ---------------- */

  Widget _voteView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(revoteHint ? '🗳️ 平票了，再投一轮' : '🗳️ 投票 — 把你怀疑的人投出去',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('投完就等票数结算（你投给谁，只有法官看得到）',
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

  Widget _resultView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🗳️ 投票结果', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Panel(
          color: const Color(0xFFD33F49),
          icon: Icons.gavel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ejectedSeat == null ? '本轮无人出局' : '${ejectedSeat! + 1} 号被放逐',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFD33F49)),
              ),
              if (gunSeat != null) ...[
                const SizedBox(height: 10),
                Text('猎人开枪带走了 ${gunSeat! + 1} 号',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF4CAF7D))),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /* ---------------- 日常视图 ---------------- */

  Widget _idleView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoleCard(
          role: role ?? Role.villager,
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
                children: List.generate(
                  seatCount,
                  (i) => Chip(
                    label: Text('${i + 1}'),
                    // alive 为空 = 还没收到过存活名单，一律按"都活着"显示
                    backgroundColor: (alive.isEmpty || alive.contains(i))
                        ? const Color(0xFF3B3350)
                        : const Color(0xFF2A2538),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (deaths.isNotEmpty)
          Text(
            deaths.map((x) => '${x + 1} 号出局').join('，'),
            style: const TextStyle(color: Color(0xFFD33F49), fontWeight: FontWeight.w800),
          ),
        if (role != null && role != Role.werewolf)
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

  /* ---------------- 夜间动作 ---------------- */

  Widget _actionView() {
    switch (actor) {
      case 'guard':
        return _simplePick('守卫', '今晚要守护谁？（不能守自己）', (t) => _sendAct('guard', target: t));
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
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFE8A33D)),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () {
            // 和网页端保持一致：走 pass，房主那边直接把这位标记为"done"
            guest.send(msgPass());
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
          dead: _deadSeats(),
          onPick: onPick,
          label: '点一个座位',
        ),
      ],
    );
  }

  /// 出局的人 + 自己（守卫不能自守，但其它角色可以指自己）
  /// alive 为空 = 还没收到过存活名单，一律按"都活着"处理，
  /// 否则第一夜所有座位都会被灰掉、根本点不动。
  List<int> _deadSeats([int? excludeSelf]) {
    final out = <int>[];
    if (alive.isEmpty) return out;
    for (var i = 0; i < seatCount; i++) {
      if (i == excludeSelf) continue;
      if (!alive.contains(i)) out.add(i);
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
          label: '点一个座位',
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
    final noVictim = nightVictim == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🧙 女巫请睁眼', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(
          noVictim ? '法官告诉你：今夜没有人被刀' : '法官告诉你：今夜 ${nightVictim! + 1} 号被刀了',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Text(
          canHeal ? '① 要不要用解药救他？' : '① 解药已经用掉了',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: canHeal ? Colors.white : Colors.white38),
        ),
        const SizedBox(height: 10),
        if (canHeal && !noVictim)
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
          )
        else
          const Text('（解药只能用在今夜被刀的人身上）',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 22),
        Text(
          canPoison ? '② 要不要用毒药毒人？' : '② 毒药已经用掉了',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: canPoison ? Colors.white : Colors.white38),
        ),
        const SizedBox(height: 10),
        if (canPoison)
          PickerGrid(
            seatCount: seatCount,
            target: poisonTarget ?? -1,
            dead: _deadSeats(),
            onPick: (t) => setState(() => poisonTarget = poisonTarget == t ? null : t),
            label: '点一个座位（再点一次取消）',
          ),
        if (poisonTarget != null)
          OutlinedButton(
            onPressed: () => setState(() => poisonTarget = null),
            child: const Text('取消毒药'),
          ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => _sendAct('witch',
              save: canHeal && useHeal && !noVictim, poison: poisonTarget),
          icon: const Icon(Icons.check),
          label: const Text('确认，闭眼'),
        ),
      ],
    );
  }

  Widget _overView() {
    final win = winner == 'good'
        ? role != Role.werewolf
        : (winner == 'wolf' && role == Role.werewolf);
    return Column(
      children: [
        Icon(win ? Icons.sentiment_very_satisfied : Icons.sentiment_dissatisfied,
            size: 72, color: win ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49)),
        const SizedBox(height: 14),
        Text(win ? '这局你赢了 🎉' : '这局你输了',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: win ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49))),
        const SizedBox(height: 8),
        Text(winnerText(winner ?? ''), style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 18),
        RoleCard(role: role ?? Role.villager, name: '你本局是 ${roleName[role] ?? '平民'}'),
      ],
    );
  }
}
