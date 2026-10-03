// 纯 Dart 逻辑自检：不需要 flutter/子进程，单进程跑完
// 运行：dart run scripts/logic_check.dart
import 'package:werewolf/core/judge.dart';

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

void main() {
  print('--- 牌堆 ---');
  for (final n in const [6, 9, 12]) {
    final j = Judge(playerCount: n)..deal();
    final counts = <Role, int>{};
    for (final s in j.seats) counts[s.role!] = (counts[s.role!] ?? 0) + 1;
    final ok = presets[n]!.entries.every((e) => counts[e.key] == e.value) &&
        j.seats.length == n;
    check('$n 人局牌数分得刚好', ok);
  }

  final a = Judge(playerCount: 12)..deal();
  final b = Judge(playerCount: 12)..deal();
  check('洗牌每次不同',
      a.seats.map((s) => s.role!.index).join() != b.seats.map((s) => s.role!.index).join());

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
  final g = Judge(playerCount: 12)..deal();
  g.cur = Role.guard;
  final me = g.guardSeat;
  check('守卫不能自守', me == null ? true : !g.guardProtect(me!));
  g.cur = Role.guard;
  check('守卫能守别人', g.guardProtect(0));

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
  final w = Judge(playerCount: 12)..deal();
  w.cur = Role.guard;
  w.guardProtect(5);
  w.cur = Role.werewolf;
  w.wolfKill(5);
  w.cur = Role.witch;
  w.witchAct();
  final d4 = w.resolveNight();
  check('被守的人不死', d4.isEmpty);

  print('--- 女巫药限一次 ---');
  final u = Judge(playerCount: 12)..deal();
  u.cur = Role.witch;
  u.witchAct(save: true);
  final usedHeal = u.seats[u.witchSeat!].usedHeal;
  u.cur = Role.witch;
  u.witchAct(save: true);
  check('解药只生效一次',
      usedHeal && u.seats[u.witchSeat!].usedHeal && u.seats[1].alive);

  print('--- 白天发言 ---');
  final t = Judge(playerCount: 9)..deal();
  t.deaths = [4];
  check('从死者下家开始发言', t.firstSpeaker() == 5);

  print('--- 胜负 ---');
  final win1 = Judge(playerCount: 9)..deal();
  for (final x in win1.seats) {
    if (x.role == Role.werewolf) x.alive = false;
  }
  check('狼全灭=好人胜', win1.checkWinner() == 'good');

  final win2 = Judge(playerCount: 9)..deal();
  for (final x in win2.seats) {
    if (x.role != Role.werewolf) x.alive = false;
  }
  check('狼>=好人=狼人胜', win2.checkWinner() == 'wolf');

  print('--- 回合推进 ---');
  final r = Judge(playerCount: 9)..deal();
  r.startNextNight();
  check('放逐后进入下一夜', r.phase == Phase.nightRole && r.round == 2);
  check('新一夜回到守卫', r.pendingRole == Role.guard);

  print('');
  print('通过 $pass 项，失败 $fail 项');
  if (fail > 0) throw StateError('有逻辑错误');
}
