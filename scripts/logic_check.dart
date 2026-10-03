// 纯 Dart 逻辑自检：不需要 flutter/子进程，单进程跑完
// 运行：dart run scripts/logic_check.dart
import 'package:werewolf/core/judge.dart';
import 'package:werewolf/core/protocol.dart';

int pass = 0;
int fail = 0;

void check(String name, bool ok) {
  if (ok) {
    pass++;
    print('  ✓ $name');
  } else {
    fail++;
    print('  ✗ $name  << FAIL');
  }
}

/// 手工摆一副固定牌：4 狼(0-3) / 4 神(4-7) / 4 民(8-11)
Judge fixed12(WinMode m) {
  final j = Judge(playerCount: 12, winMode: m);
  const roles = <Role>[
    Role.werewolf, Role.werewolf, Role.werewolf, Role.werewolf,
    Role.seer, Role.witch, Role.hunter, Role.guard,
    Role.villager, Role.villager, Role.villager, Role.villager,
  ];
  for (var i = 0; i < 12; i++) {
    j.seats[i].role = roles[i];
  }
  j.hasGod = true;
  j.hasVillager = true;
  return j;
}

void kill(Judge j, List<int> seats) {
  for (final s in seats) {
    j.seats[s].alive = false;
  }
}

void main() {
  print('--- 标准局牌堆 ---');
  for (final n in const [6, 9, 12]) {
    final j = Judge(playerCount: n)..deal();
    final counts = <Role, int>{};
    for (final s in j.seats) {
      counts[s.role!] = (counts[s.role!] ?? 0) + 1;
    }
    final ok = presets[n]!.entries.every((e) => counts[e.key] == e.value) && j.seats.length == n;
    check('$n 人局牌数分得刚好', ok);
  }

  print('--- 任意人数自动配牌（6~18）---');
  var allOk = true;
  var balanced = true;
  final rows = <String>[];
  for (var n = minPlayers; n <= maxPlayers; n++) {
    final deck = deckFor(n);
    final total = deck.values.fold<int>(0, (a, b) => a + b);
    final w = deck[Role.werewolf] ?? 0;
    final gods = deck.entries.where((e) => isGodRole(e.key)).fold<int>(0, (a, e) => a + e.value);
    final vills = deck[Role.villager] ?? 0;
    rows.add('    $n人: 狼$w 神$gods 民$vills');
    if (total != n) allOk = false;
    if (w < 1 || gods < 1 || vills < 1 || gods > godOrder.length) balanced = false;
    // 实际发牌不能越界
    final j = Judge(playerCount: n)..deal();
    if (j.seats.any((s) => s.role == null)) allOk = false;
    final counts = <Role, int>{};
    for (final s in j.seats) {
      counts[s.role!] = (counts[s.role!] ?? 0) + 1;
    }
    for (final e in deck.entries) {
      if (counts[e.key] != e.value) allOk = false;
    }
  }
  print(rows.join('\n'));
  check('每个人数牌堆总数 == 人数，且发牌无越界', allOk);
  check('每个非标准局都有狼/神/民，神职不超过 4 种', balanced);
  check('自动狼数符合 n/3 规律', autoWolfCount(9) == 3 && autoWolfCount(12) == 4 && autoWolfCount(11) == 4);
  check('手动指定狼数生效', (deckFor(10, wolfOverride: 2)[Role.werewolf] ?? 0) == 2);

  print('--- 地址解析 ---');
  final a1 = parseAddr('10.16.3.7');
  final a2 = parseAddr('10.16.3.7:7789');
  final a3 = parseAddr('  http://10.16.3.7:7790/  ');
  check('纯 IP 走默认端口', a1.ip == '10.16.3.7' && a1.port == defaultPort);
  check('IP:端口 解析正确', a2.ip == '10.16.3.7' && a2.port == 7789);
  check('带协议头/斜杠也能解析', a3.ip == '10.16.3.7' && a3.port == 7790);

  print('--- 夜间顺序 ---');
  final j = Judge(playerCount: 12)..deal();
  check('第一夜从守卫开始', j.pendingRole == Role.guard);
  check('接着是狼人', j.nextNightRole() == Role.werewolf);
  check('接着是预言家', j.nextNightRole() == Role.seer);
  check('接着是女巫', j.nextNightRole() == Role.witch);
  check('女巫之后该天亮了', j.nextNightRole() == null && j.phase == Phase.nightRole);
  j.resolveNight();
  check('结算后进入天亮', j.phase == Phase.dawn);

  print('--- 守卫 ---');
  final g = Judge(playerCount: 12)..deal(seed: 7);
  g.cur = Role.guard;
  final me = g.guardSeat;
  check('守卫不能自守', me == null ? true : !g.guardProtect(me!));
  g.cur = Role.guard;
  // 挑一个"一定不是守卫自己"的座位：别让洗牌结果决定用例成败
  final other = List.generate(12, (i) => i).firstWhere((i) => i != me);
  check('守卫能守别人', g.guardProtect(other));

  // 上面两条只覆盖了一种洗牌。曾经就因为"随手挑了 0 号当目标"，
  // 本地侥幸过了、CI 上守卫正好坐 0 号直接挂。这里扫一遍种子，把整类问题钉死。
  var guardOk = true;
  for (var seed = 0; seed < 40; seed++) {
    final gg = Judge(playerCount: 12)..deal(seed: seed);
    gg.cur = Role.guard;
    final my = gg.guardSeat;
    if (my == null) continue;
    if (gg.guardProtect(my)) guardOk = false; // 自守必须失败
    gg.cur = Role.guard;
    final o = List.generate(12, (i) => i).firstWhere((i) => i != my);
    if (!gg.guardProtect(o)) guardOk = false; // 守非自己必须成功
  }
  check('40 种洗牌下：自守恒不成立、守别人恒成立', guardOk);

  print('--- 天黑杀人 ---');
  final k = Judge(playerCount: 12)..deal();
  k.cur = Role.werewolf;
  k.wolfKill(3);
  k.cur = Role.witch;
  k.witchAct();
  final d1 = k.resolveNight();
  check('没人救就死人', d1.length == 1 && d1.first == 3);
  check('死者标记出局', !k.seats[3].alive);

  print('--- 女巫救人 ---');
  final s = Judge(playerCount: 12)..deal();
  s.cur = Role.werewolf;
  s.wolfKill(3);
  s.cur = Role.witch;
  s.witchAct(save: true);
  final d2 = s.resolveNight();
  check('解药救下人', d2.isEmpty && s.seats[3].alive == true);

  print('--- 女巫毒药 ---');
  final p = Judge(playerCount: 12)..deal();
  p.cur = Role.werewolf;
  p.wolfKill(3);
  p.cur = Role.witch;
  p.witchAct(poison: 7);
  final d3 = p.resolveNight();
  check('毒药独立生效', d3.length == 2 && !p.seats[7].alive);

  print('--- 守卫挡刀 ---');
  final w = Judge(playerCount: 12)..deal(seed: 11);
  w.cur = Role.guard;
  // 同样：守的人必须是"守卫自己以外"的，否则 guardProtect 直接返回 false
  final gs = w.guardSeat!;
  final shielded = List.generate(12, (i) => i).firstWhere((i) => i != gs);
  w.guardProtect(shielded);
  w.cur = Role.werewolf;
  w.wolfKill(shielded);
  w.cur = Role.witch;
  w.witchAct();
  final d4 = w.resolveNight();
  check('被守的人不死', d4.isEmpty);

  print('--- 女巫药限一次 / 无人被刀不能用解药 ---');
  final u = Judge(playerCount: 12)..deal();
  u.cur = Role.witch;
  u.witchAct(save: true); // 今夜没人被刀
  final witchSeat = u.witchSeat!;
  check('没人被刀时解药不消耗', !u.seats[witchSeat].usedHeal);
  u.cur = Role.werewolf;
  u.wolfKill(2);
  u.cur = Role.witch;
  u.witchAct(save: true);
  check('有死者时解药生效', u.seats[witchSeat].usedHeal);
  // 第二夜解药已耗尽，再喊救也不该生效
  u.clearNight();
  u.cur = Role.werewolf;
  u.wolfKill(5);
  u.cur = Role.witch;
  u.witchAct(save: true);
  check('解药只生效一次（第二夜再救无效）', !u.witchSaved);
  check('第二夜目标照样出局', u.resolveNight().contains(5));

  print('--- 白天发言 ---');
  final t = Judge(playerCount: 9)..deal();
  t.deaths = [4];
  check('从死者下家开始发言', t.firstSpeaker() == 5);

  print('--- 胜负：狼全灭 ---');
  final win0 = fixed12(WinMode.slaughterSide);
  kill(win0, [0, 1, 2, 3]);
  check('狼全灭=好人胜（屠边）', win0.checkWinner() == 'good');
  final win0b = fixed12(WinMode.slaughterAll);
  kill(win0b, [0, 1, 2, 3]);
  check('狼全灭=好人胜（屠城）', win0b.checkWinner() == 'good');

  print('--- 胜负：屠边 ---');
  final side1 = fixed12(WinMode.slaughterSide);
  kill(side1, [4, 5, 6, 7]); // 四个神全灭
  check('神职全灭=狼胜', side1.checkWinner() == 'wolf');
  final side2 = fixed12(WinMode.slaughterSide);
  kill(side2, [8, 9, 10, 11]); // 四个民全灭
  check('平民全灭=狼胜', side2.checkWinner() == 'wolf');
  final side3 = fixed12(WinMode.slaughterSide);
  kill(side3, [4, 5, 6, 8, 9]); // 3神+2民出局，神还剩1、民还剩2
  check('神民都还有活人=继续（4狼4好也不提前结束）', side3.checkWinner() == null);

  print('--- 胜负：屠城 ---');
  final all1 = fixed12(WinMode.slaughterAll);
  kill(all1, [4, 5, 6, 8, 9]); // 同样局面：4狼3好
  check('屠城：狼数>=好人数=狼胜', all1.checkWinner() == 'wolf');
  final all2 = fixed12(WinMode.slaughterAll);
  kill(all2, [4, 5, 8]); // 4狼6好
  check('屠城：好人还多于狼=继续', all2.checkWinner() == null);
  final all3 = fixed12(WinMode.slaughterAll);
  kill(all3, [4, 5, 6, 7, 8, 9, 10, 11]); // 好人全灭
  check('屠城：好人全灭=狼胜', all3.checkWinner() == 'wolf');

  print('--- 屠边/屠城 判定差异（同一局面不同结论）---');
  final sA = fixed12(WinMode.slaughterSide);
  final sB = fixed12(WinMode.slaughterAll);
  kill(sA, [4, 5, 6, 8, 9]);
  kill(sB, [4, 5, 6, 8, 9]);
  check('同一中局：屠边=继续、屠城=狼胜', sA.checkWinner() == null && sB.checkWinner() == 'wolf');

  print('--- 回合推进 ---');
  final r = Judge(playerCount: 9)..deal();
  r.startNextNight();
  check('放逐后进入下一夜', r.phase == Phase.nightRole && r.round == 2);
  check('新一夜回到守卫', r.pendingRole == Role.guard);

  print('');
  print('通过 $pass 项，失败 $fail 项');
  if (fail > 0) throw StateError('有逻辑错误');
}
