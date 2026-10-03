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
  WinMode winMode = WinMode.slaughterSide;
  int? wolfOverride; // null = 按人数自动配狼

  final portCtrl = TextEditingController(text: '$defaultPort');

  List<String> ips = [];
  final lan = LanHost();
  bool serving = false;
  String? serveErr;

  /// 解析客户端上报的数字/布尔，收到脏数据不崩
  static int? _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);
  static bool? _asBool(dynamic v) => v is bool ? v : null;

  Judge? j;
  final List<String> names = ['房主(你)'];
  final Set<int> joined = {0};
  final Set<String> nightDone = {};
  final Set<int> voted = {};
  bool revote = false;      // 上一轮平票，正在重投
  bool hostVoted = false;   // 房主（0 号）这一轮投过票没

  bool get allJoined => joined.length >= peopleCount;

  @override
  void dispose() {
    lan.stop();
    portCtrl.dispose();
    super.dispose();
  }

  /* ---------------- 开房间 ---------------- */
  Future<void> _serve() async {
    final want = int.tryParse(portCtrl.text.trim()) ?? defaultPort;
    if (want < 1024 || want > 65535) {
      setState(() => serveErr = '端口请填 1024~65535 之间的数字');
      return;
    }
    setState(() => serveErr = null);
    // 被占用会自动往后顺延，最多试 12 个
    final got = await lan.start(preferred: want, onMsg: _onFromClient);
    if (!mounted) return;
    if (got == null) {
      setState(() => serveErr = lan.lastErrorIsPermission
          ? '开房失败：${lan.lastError}。这不是端口的问题，换端口也没用，请装最新版的狼邮杀。'
          : '端口 $want ~ ${want + 11} 全被占用（${lan.lastError ?? '未知原因'}），换个端口号再试');
      return;
    }
    setState(() => serving = true);
    if (got != want) _toast('端口 $want 被占用，已自动改用 $got');
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
        while (names.length <= seat) {
          names.add('');
        }
        names[seat] = name;
        joined.add(seat);
      });
      // 此时还没发牌，只广播名册；牌在开局时单独下发
      lan.broadcast(msgRoster(_rosterJson()));
    } else if (t == 'act' || t == 'pass') {
      final seat = _seatByIp(ip);
      if (seat == null) return;
      if (t == 'pass') {
        _handleAction(seat, 'pass');
        return;
      }
      final kind = d['kind'] as String?;
      if (kind == 'vote') {
        final target = _asInt(d['target']);
        if (target != null) {
          setState(() {
            _votes[target] = (_votes[target] ?? 0) + 1;
            voted.add(seat);
          });
        }
        return;
      }
      _handleAction(seat, kind,
          target: _asInt(d['target']), save: _asBool(d['save']), poison: _asInt(d['poison']));
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
    final judge = Judge(
      playerCount: peopleCount,
      sheriffEnabled: sheriffOn,
      winMode: winMode,
      wolfOverride: wolfOverride,
    );
    setState(() {
      j = judge;
      nightDone.clear();
      voted.clear();
      hostVoted = false;
      revote = false;
      _votes.clear();
    });
    judge.deal();
    for (var s = 1; s < peopleCount; s++) {
      lan.sendToSeat(s, msgRole(s, names[s], judge.seats[s].role!.index));
    }
    lan.broadcast(msgRoster(_rosterJson()));
    lan.broadcast(msgPhase('night', judge.round));
  }

  List<dynamic> _rosterJson() => List.generate(peopleCount, (i) => {
        'id': i,
        'name': i < names.length && names[i].isNotEmpty ? names[i] : (i == 0 ? '房主' : '玩家${i + 1}'),
        'alive': true,
        'role': null,
        'isOwner': i == 0,
      });

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
    // 女巫需要知道今夜被刀的是谁 + 自己药还剩几瓶
    final witchSeat = r == Role.witch ? judge.witchSeat : null;
    lan.sendToSeat(
        seat,
        msgWake(
          seat,
          r.name,
          wolves: wolves,
          target: r == Role.witch ? judge.nightVictim : null,
          canHeal:
              witchSeat != null ? !judge.seats[witchSeat].usedHeal : null,
          canPoison:
              witchSeat != null ? !judge.seats[witchSeat].usedPoison : null,
        ));
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

  /// 开投票；isRevote=true 表示上一轮平票重投
  void _openVote({bool isRevote = false}) {
    revote = isRevote;
    voted.clear();
    hostVoted = false;
    _votes.clear();
    lan.broadcast(msgVoteOpen(_aliveList(), revote: isRevote));
    setState(() {});
  }

  void _checkOver() {
    final judge = j!;
    final w = judge.checkWinner();
    if (w != null) {
      judge.phase = Phase.over;
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
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: peopleCount > minPlayers
                    ? () => setState(() {
                          peopleCount--;
                          wolfOverride = null;
                        })
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Center(
                  child: Text('$peopleCount 人',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                ),
              ),
              IconButton.filledTonal(
                onPressed: peopleCount < maxPlayers
                    ? () => setState(() {
                          peopleCount++;
                          wolfOverride = null;
                        })
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [6, 7, 8, 9, 10, 11, 12, 14, 16]
                .map((n) => ChoiceChip(
                      label: Text('$n'),
                      selected: peopleCount == n,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        peopleCount = n;
                        wolfOverride = null;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          const Text('标准局是 6 / 9 / 12 人，但人数随便定（6~18），牌堆会自动配好',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 18),
          Panel(
            color: const Color(0xFF3F8EE0),
            icon: Icons.style,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本局牌堆',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 10),
                Text(
                  _deckText(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, height: 1.6),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '狼人 ${wolfOverride ?? autoWolfCount(peopleCount)} 个'
                        '${wolfOverride == null ? '（按人数自动）' : '（手动指定）'}',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ),
                    IconButton(
                        onPressed: (wolfOverride ?? autoWolfCount(peopleCount)) > 1
                            ? () => setState(() =>
                                wolfOverride = (wolfOverride ?? autoWolfCount(peopleCount)) - 1)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline, size: 20)),
                    IconButton(
                        onPressed: (wolfOverride ?? autoWolfCount(peopleCount)) < peopleCount - 2
                            ? () => setState(() =>
                                wolfOverride = (wolfOverride ?? autoWolfCount(peopleCount)) + 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline, size: 20)),
                    if (wolfOverride != null)
                      TextButton(
                          onPressed: () => setState(() => wolfOverride = null),
                          child: const Text('自动')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('胜负条件',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SegmentedButton<WinMode>(
            segments: WinMode.values
                .map((m) => ButtonSegment(value: m, label: Text(winModeName[m]!)))
                .toList(),
            selected: {winMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => winMode = s.first),
          ),
          const SizedBox(height: 8),
          Text(winModeDesc[winMode]!,
              style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.6)),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开启警长竞选'),
            value: sheriffOn,
            onChanged: (v) => setState(() => sheriffOn = v),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('监听端口',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: portCtrl,
                  enabled: !serving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '7788', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('被占用会自动往后顺延（7788→7789→…），室友按屏幕上显示的地址填',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 24),
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
                          '$ip:${lan.port}',
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
    final p = deckFor(peopleCount, wolfOverride: wolfOverride);
    final order = <Role>[...Role.values]..sort((a, b) {
        // 展示顺序：狼、神、民
        int rank(Role r) => r == Role.werewolf ? 0 : (r == Role.villager ? 2 : 1);
        return rank(a).compareTo(rank(b));
      });
    return order
        .where((r) => (p[r] ?? 0) > 0)
        .map((r) => '${roleName[r]}×${p[r]}')
        .join('   ');
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
    final w = judge.aliveWolfCount;
    final g = judge.aliveGodCount;
    final v = judge.aliveVillagerCount;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('${alive.length}/${judge.playerCount} 存活', Colors.white70),
        _chip('狼 $w', const Color(0xFFD33F49)),
        if (g > 0) _chip('神 $g', const Color(0xFFE8A33D)),
        if (v > 0) _chip('民 $v', const Color(0xFF5A8FD6)),
        _chip(winModeName[judge.winMode]!, const Color(0xFF8E5BD6)),
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
            j!.phase = Phase.voting;
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
    final waiting = alive.length - voted.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          color: const Color(0xFF5A8FD6),
          icon: Icons.how_to_vote,
          child: Column(
            children: [
              Text(revote ? '平票，重新投票' : '投票中',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                '已收到 ${voted.length}/${alive.length} 票'
                '${waiting > 0 ? '，还差 $waiting 人' : '，人齐了'}',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // 房主也是玩家（0 号），这一票得能投，否则票永远收不齐
        Text(hostVoted ? '✓ 你已经投过票了' : '轮到你了：点一个座位投票',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: hostVoted ? const Color(0xFF4CAF7D) : Colors.white70)),
        const SizedBox(height: 12),
        PickerGrid(
          seatCount: judge.playerCount,
          target: -1,
          dead: _deadFor(0),
          enabled: !hostVoted,
          onPick: (t) {
            setState(() {
              _votes[t] = (_votes[t] ?? 0) + 1;
              voted.add(0);
              hostVoted = true;
            });
          },
          label: hostVoted ? null : '点一个座位，投出你的票',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _resolveVote,
          icon: const Icon(Icons.bolt),
          label: Text(waiting > 0 ? '不等了，直接结算' : '结算票数'),
        ),
        if (waiting > 0)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('投完的室友可以催一催；实在不投也能直接结算',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ),
      ],
    );
  }

  /// 房主视角的出局座位（不含自己）
  List<int> _deadFor(int self) {
    final judge = j!;
    final out = <int>[];
    for (var i = 0; i < judge.playerCount; i++) {
      if (!judge.seats[i].alive && i != self) out.add(i);
    }
    return out;
  }

  void _resolveVote() {
    final t = _votes;
    if (t.isEmpty) {
      _toast('一票都没有，本轮无人出局');
      _finishEject(null, null);
      return;
    }
    final max = t.values.reduce((a, b) => a > b ? a : b);
    final top = t.entries.where((e) => e.value == max).map((e) => e.key).toList();
    if (top.length > 1) {
      // 平票 -> 重新投一轮（重新广播 vote_open，玩家端才会重新弹出投票界面）
      _toast('${top.map((e) => '${e + 1}号').join('、')} 平票，重投一轮');
      j!.phase = Phase.voting;
      _openVote(isRevote: true);
      return;
    }
    final victim = top.first;
    final judge = j!;
    final role = judge.seats[victim].role;
    final canGun = role == Role.hunter && !judge.seats[victim].usedGun;
    if (canGun) {
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
        content: const Text('问猎人：开不开枪？开的话他指定一个人带走（被女巫毒死的猎人不能开枪）。'),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _finishEject(victim, null);
              },
              child: const Text('不开枪')),
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
    final judge = j!;
    final targets = List.generate(judge.playerCount, (i) => i)
        .where((i) => judge.seats[i].alive && i != victim)
        .toList();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('猎人开枪，选目标'),
        content: Text(targets.isEmpty
            ? '场上没有可带走的人了'
            : '让猎人指定带走谁：${targets.map((i) => '${i + 1}号').join('、')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ...targets.map((i) => TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _finishEject(victim, i);
                },
                child: Text('${i + 1} 号'),
              )),
        ],
      ),
    );
  }

  void _finishEject(int? victim, int? gun) {
    final judge = j!;
    if (victim != null) judge.seats[victim].alive = false;
    if (gun != null) judge.seats[gun].alive = false;
    lan.broadcast(msgVoteResult(
        {'tally': _votes.map((k, v) => MapEntry('$k', v))}, victim, gun));
    _votes.clear();
    voted.clear();
    hostVoted = false;
    revote = false;
    setState(() {});
    _checkOver();
    if (judge.phase != Phase.over) {
      judge.startNextNight();
      nightDone.clear();
      // 告诉所有玩家：新一轮天黑，清掉上一轮的投票结果等状态
      lan.broadcast(msgPhase('night', judge.round));
    }
    setState(() {});
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
          const SizedBox(height: 10),
          Text('${winModeName[j!.winMode]}局 · ${j!.winReason()}',
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 16),
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
