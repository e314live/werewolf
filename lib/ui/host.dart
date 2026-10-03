import 'dart:async';

import 'package:flutter/material.dart';

import '../core/judge.dart';
import '../core/protocol.dart';
import '../net/lan.dart';
import 'common.dart';

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostState();
}

class _HostState extends State<HostPage> {
  int peopleCount = 9;
  bool sheriffOn = true;

  List<String> ips = [];
  final lan = LanHost();
  bool serving = false;
  String? serveErr;

  Judge? j;
  final List<String> names = ['房主(你)'];
  final Set<int> joined = {0};
  final Set<int> roleAcked = {};
  final Set<String> nightDone = {};
  final Set<int> voted = {};
  bool revote = false;   // 上一轮平票/流局，重新投
  int? gunTarget;

  int talkLeft = 0;
  Timer? _t;

  bool get allJoined => joined.length >= peopleCount;

  @override
  void dispose() {
    _t?.cancel();
    lan.stop();
    super.dispose();
  }

  /* ---------------- 开房间 ---------------- */
  Future<void> _serve() async {
    final err = await lan.start(lanPort, onMsg: _onFromClient);
    if (!mounted) return;
    setState(() => serveErr = err);
    if (err != null) return;
    setState(() => serving = true);
    _ips();
  }

  Future<void> _ips() async {
    final l = await localIps();
    if (mounted) setState(() => ips = l);
  }

  void _onFromClient(String ip, Map<String, dynamic> m) {
    final t = m['t'] as String?;
    final d = (m['d'] as Map?) ?? {};
    if (t == 'join') {
      final name = (d['name'] as String? ?? '室友').trim();
      final seat = lan.clients.length - 1; // 房主占 0 号
      if (seat < 0 || seat >= peopleCount) return;
      if (!mounted) return;
      setState(() {
        if (seat >= names.length) names.add('');
        names[seat] = name;
        joined.add(seat);
      });
      lan.sendToSeat(seat, msgRole(seat, name, '...'));
    } else if (t == 'act' || t == 'pass') {
      final seat = _seatByIp(ip);
      if (seat == null) return;
      if (t == 'pass') {
        _handleAction(seat, 'pass');
        return;
      }
      final kind = d['kind'] as String?;
      if (kind == 'vote') {
        final target = d['target'] as int?;
        if (target != null) {
          setState(() {
            _votes[target] = (_votes[target] ?? 0) + 1;
            voted.add(seat);
          });
        }
        return;
      }
      _handleAction(seat, kind,
          target: d['target'] as int?,
          save: d['save'] as bool?,
          poison: d['poison'] as int?);
    }
  }

  int? _seatByIp(String ip) {
    for (var i = 0; i < lan.clients.length; i++) {
      if (lan.clients[i].remoteAddress.address == ip) return i == 0 ? null : i;
    }
    return null;
  }

  /// 客户端上报夜动作，房主记账并推进
  void _handleAction(int seat, String? kind, {int? target, bool? save, int? poison}) {
    final judge = j;
    if (judge == null || kind == null) return;
    if (kind == 'pass') {
      setState(() => nightDone.add(judge.pendingRole?.name ?? 'pass'));
      return;
    }
    setState(() => nightDone.add(kind));
    switch (kind) {
      case 'guard':
        judge.guardProtect(target ?? -1);
        break;
      case 'werewolf':
        if (target != null) judge.wolfKill(target);
        break;
      case 'seer':
        if (target != null) {
          final res = judge.seerCheck(target);
          if (res != null) {
            lan.sendToSeat(seat, msgWake(seat, 'seer_result', target: target, checked: roleName[res]));
          }
        }
        break;
      case 'witch':
        judge.witchAct(save: save, poison: poison);
        break;
      default:
        break;
    }
  }

  /* ---------------- 开局 ---------------- */
  /// 发牌：洗好整副牌，只把「你自己那张」发给你
  void _startGame() {
    if (!allJoined) {
      _toast('还差 ${peopleCount - joined.length} 人没进房间');
      return;
    }
    final judge = Judge(playerCount: peopleCount, sheriffEnabled: sheriffOn);
    setState(() {
      j = judge;
      nightDone.clear();
      voted.clear();
      _votes.clear();
    });
    judge.deal();
    for (var s = 1; s < peopleCount; s++) {
      // Map[key] 的静态类型是 V?，这里 msgRole 要的是 String，兜个底
      lan.sendToSeat(s, msgRole(s, names[s], roleName[judge.seats[s].role!] ?? ''));
    }
    lan.broadcast(msgRoster(_rosterJson()));
    lan.broadcast(msgPhase('night', judge.round));
  }

  List<dynamic> _rosterJson() => List.generate(peopleCount, (i) => {
        'id': i,
        'name': names[i],
        'alive': true,
        'role': null,
        'isOwner': i == 0,
      });

  void _beginNight() {
    final judge = j!;
    nightDone.clear();
    setState(() {});
    lan.broadcast(msgPhase('night', judge.round));
  }

  void _callWake() {
    final judge = j!;
    final r = judge.pendingRole!;
    final seat = switch (r) {
      Role.guard => judge.guardSeat,
      Role.werewolf => judge.wolfSeat,
      Role.seer => judge.seerSeat,
      Role.witch => judge.witchSeat,
      _ => null,
    };
    if (seat == null) {
      // 该角色已死或不存在 -> 直接跳过
      setState(() => nightDone.add(r.name));
      _nextStep();
      return;
    }
    final wolves = r == Role.werewolf
        ? judge.seats.where((s) => s.role == Role.werewolf && s.alive).map((s) => s.id).toList()
        : null;
    // 女巫需要知道今夜被刀的是谁，预言家/守卫/狼人不需要
    lan.sendToSeat(seat, msgWake(seat, r.name, wolves: wolves, target: r == Role.witch ? judge.nightVictim : null));
    setState(() {});
  }

  void _nextStep() {
    final judge = j!;
    final nxt = judge.nextNightRole();
    if (nxt == null) {
      _dawn();
    } else {
      _callWake();
    }
  }

  void _dawn() {
    final judge = j!;
    final deaths = judge.resolveNight();
    lan.broadcast(msgPhase('dawn', judge.round, deaths: deaths, alive: _aliveList()));
    setState(() {});
    _checkOver();
  }

  List<int> _aliveList() =>
      j!.seats.where((s) => s.alive).map((s) => s.id).toList();

  void _openVote() {
    lan.broadcast(msgVoteOpen(_aliveList()));
    voted.clear();
    revote = false;
    setState(() {});
  }

  void _checkOver() {
    final w = j!.checkWinner();
    if (w != null) {
      lan.broadcast(msgOver(w));
      setState(() {});
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    if (j == null) return _setupView();
    return _controlView();
  }

  /* ---------------- 建房页 ---------------- */
  Widget _setupView() {
    final full = allJoined;
    return Scaffold(
      appBar: AppBar(title: const Text('开房间 · 当法官')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('人数',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [6, 9, 12]
                .map((n) => ChoiceChip(
                      label: Text('$n 人'),
                      selected: peopleCount == n,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => peopleCount = n),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(
            _deckText(),
            style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.6),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开启警长竞选'),
            value: sheriffOn,
            onChanged: (v) => setState(() => sheriffOn = v),
          ),
          const SizedBox(height: 20),
          if (!serving)
            FilledButton.icon(
              onPressed: _serve,
              icon: const Icon(Icons.hub),
              label: const Text('开启房间'),
            )
          else ...[
            Panel(
              color: const Color(0xFF8E5BD6),
              icon: Icons.wifi,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('把这个地址念给室友（或截图发群里）',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                  const SizedBox(height: 12),
                  ...ips.map((ip) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          '$ip:$lanPort',
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF8E5BD6),
                              letterSpacing: 1),
                        ),
                      )),
                  if (ips.isEmpty)
                    const Text('没读到 IP，请确认连着校园网/同一个 WiFi',
                        style: TextStyle(fontSize: 12, color: Colors.white38)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('进房情况：${joined.length}/$peopleCount',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(peopleCount, (i) {
                final on = joined.contains(i);
                return Chip(
                  avatar: on ? const Icon(Icons.check, size: 16) : null,
                  label: Text(on ? names[i] : '空位 ${i + 1}'),
                  backgroundColor: on ? const Color(0xFF3B3350) : const Color(0xFF1D1A28),
                );
              }),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: full ? _startGame : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(full ? '发牌，开始第一夜' : '坐满后开始'),
            ),
          ],
          if (serveErr != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(serveErr!, style: const TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  String _deckText() {
    final p = presets[peopleCount] ?? presets[9]!;
    return '本局牌堆：${p.entries.map((e) => '${roleName[e.key]}×${e.value}').join('  ')}';
  }

  /* ---------------- 法官控制页 ---------------- */
  Widget _controlView() {
    final judge = j!;
    return Scaffold(
      appBar: AppBar(title: Text('第 ${judge.round} 夜 · 法官台')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusBar(),
          const SizedBox(height: 16),
          if (judge.phase == Phase.nightRole) _nightCard(),
          if (judge.phase == Phase.dawn) _dawnCard(),
          if (judge.phase == Phase.dayTalk) _dayCard(),
          if (judge.phase == Phase.voting) _voteCard(),
          if (judge.phase == Phase.over) _overCard(),
        ],
      ),
    );
  }

  Widget _statusBar() {
    final judge = j!;
    final alive = _aliveList();
    final w = judge.seats.where((s) => s.alive && s.role == Role.werewolf).length;
    return Row(
      children: [
        _chip('${alive.length} 人存活', Colors.white70),
        const SizedBox(width: 8),
        _chip('狼 $w', const Color(0xFFD33F49)),
      ],
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
      );

  Widget _nightCard() {
    final judge = j!;
    final r = judge.pendingRole!;
    final done = nightDone.contains(r.name);
    return Column(
      children: [
        Panel(
          color: const Color(0xFF3B3350),
          icon: Icons.nightlight_round,
          child: Column(
            children: [
              Text('当前：${roleName[r]}睁眼',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(_nightHint(r),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, height: 1.7, color: Colors.white60)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: done ? _nextStep : _callWake,
          icon: Icon(done ? Icons.arrow_forward : Icons.visibility),
          label: Text(done ? '下一位' : '叫${roleName[r]}睁眼'),
        ),
        if (!done)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('对方点完会回到这里，点「下一位」继续',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ),
      ],
    );
  }

  String _nightHint(Role r) => switch (r) {
        Role.guard => '让守卫选一个人守护（不能守自己）',
        Role.werewolf => '让狼人刀一个人（全场狼互相认识）',
        Role.seer => '让预言家验一个人，验完会显示结果',
        Role.witch => '告诉女巫今夜死了谁，让她决定救/毒',
        _ => '',
      };

  Widget _dawnCard() {
    final judge = j!;
    final d = judge.deaths;
    return Column(
      children: [
        Panel(
          color: d.isEmpty ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49),
          icon: Icons.wb_sunny,
          child: Column(
            children: [
              Text('天亮了',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              d.isEmpty
                  ? const Text('今晚是平安夜，没有人出局',
                      style: TextStyle(color: Colors.white70))
                  : Column(
                      children: d
                          .map((x) => Text('${x + 1} 号出局',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFD33F49))))
                          .toList(),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () {
            setState(() => j!.phase = Phase.dayTalk);
          },
          icon: const Icon(Icons.record_voice_over),
          label: const Text('进入白天'),
        ),
      ],
    );
  }

  Widget _dayCard() {
    final judge = j!;
    final start = judge.firstSpeaker();
    return Column(
      children: [
        Panel(
          color: const Color(0xFFE8A33D),
          icon: Icons.record_voice_over,
          child: Column(
            children: [
              const Text('白天 · 自由发言',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text('发言顺序：${_orderText(start)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, height: 1.7, color: Colors.white70)),
              if (sheriffOn)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('（警长竞选由房主口头主持）',
                      style: TextStyle(fontSize: 11, color: Colors.white38)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () {
            setState(() => j!.phase = Phase.voting);
            _openVote();
          },
          icon: const Icon(Icons.how_to_vote),
          label: const Text('开始投票'),
        ),
      ],
    );
  }

  String _orderText(int start) {
    final n = j!.playerCount;
    final buf = StringBuffer();
    for (var k = 0; k < n; k++) {
      final i = (start + k) % n;
      if (!j!.seats[i].alive) continue;
      buf.write('${i + 1}号 ');
    }
    return buf.toString().trim();
  }

  Widget _voteCard() {
    final judge = j!;
    final alive = _aliveList();
    final all = revote || voted.length >= alive.length;
    return Column(
      children: [
        Panel(
          color: const Color(0xFF5A8FD6),
          icon: Icons.how_to_vote,
          child: Column(
            children: [
              Text(revote ? '平票/流局，重新投票' : '投票中',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text('已收到 ${voted.length}/$alive 票',
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (all)
          FilledButton.icon(
            onPressed: _resolveVote,
            icon: const Icon(Icons.bolt),
            label: const Text('结算票数'),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text('等室友投完…', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
          ),
      ],
    );
  }

  void _resolveVote() {
    // 实际计数：由各客户端上报，这里用 _votes 累加
    final t = _votes;
    final max = t.values.isEmpty ? 0 : t.values.reduce((a, b) => a > b ? a : b);
    final top = t.entries.where((e) => e.value == max).map((e) => e.key).toList();
    if (top.length > 1) {
      // 平票 -> 流局，重新投
      _toast('平票，重新投票');
      voted.clear();
      _votes.clear();
      revote = true;
      lan.broadcast(msgPhase('vote_revote', j!.round));
      setState(() {});
      return;
    }
    final victim = top.isEmpty ? null : top.first;
    if (victim == null) {
      _toast('没有人得票，流局');
      voted.clear();
      setState(() {});
      return;
    }
    final judge = j!;
    final role = judge.seats[victim].role;
    final canGun = role == Role.hunter && !judge.seats[victim].usedGun;
    if (canGun) {
      setState(() => gunTarget = victim);
      _askGun(victim);
    } else {
      _finishEject(victim, null);
    }
  }

  final Map<int, int> _votes = {};

  void _askGun(int victim) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('放逐的是猎人，要问是否开枪吗？'),
        content: const Text('开枪会带走一个人（房主决定目标），被毒死不能开枪。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('不开枪')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _gunPick(victim);
              },
              child: const Text('开枪')),
        ],
      ),
    );
  }

  void _gunPick(int victim) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('猎人开枪，选目标'),
        content: const Text('选一个人带走，或留空取消'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')) ,
          ...List.generate(j!.playerCount, (i) {
            if (!j!.seats[i].alive || i == victim) return const SizedBox.shrink();
            return TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _finishEject(victim, i);
                },
                child: Text('${i + 1} 号'));
          }),
        ],
      ),
    );
  }

  void _finishEject(int victim, int? gun) {
    final judge = j!;
    final deaths = <int>[victim];
    judge.seats[victim].alive = false;
    if (gun != null) {
      judge.seats[gun].alive = false;
      deaths.add(gun);
    }
    lan.broadcast(msgVoteResult(
        {'tally': _votes, 'ejected': victim, 'gun': gun}, victim, gun));
    _votes.clear();
    voted.clear();
    judge.startNextNight();
    nightDone.clear();
    setState(() {});
    _checkOver();
  }

  Widget _overCard() {
    final w = j!.checkWinner();
    final win = w == 'good';
    return Panel(
      color: win ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49),
      icon: Icons.emoji_events,
      child: Column(
        children: [
          Text(win ? '🌅 好人胜利' : '🌙 狼人胜利',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: win ? const Color(0xFF4CAF7D) : const Color(0xFFD33F49))),
          const SizedBox(height: 14),
          const Text('翻牌时间到，大家好牌！',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: List.generate(j!.playerCount, (i) => Chip(
                  label: Text('${i + 1}号 ${names[i]}：${roleName[j!.seats[i].role!]}'),
                  backgroundColor: const Color(0xFF2A2538),
                )),
          ),
        ],
      ),
    );
  }
}
