// 座位/开局自检（纯逻辑，本机可跑）
// 这里覆盖的是之前两个致命 bug：第一个进房的人抢走房主 0 号座位、人数永远凑不满 → 开不了局
import 'dart:io';

import '../lib/core/judge.dart';
import '../lib/core/room.dart';

int pass = 0, fail = 0;
void ok(bool c, String name) {
  if (c) {
    pass++;
    print('  ✓ $name');
  } else {
    fail++;
    print('  ✗ $name');
  }
}

void main() {
  print('--- 第一个进房的人不该抢 0 号 ---');
  final r = Room(playerCount: 9);
  ok(r.joined.contains(0), '房主固定占 0 号');
  final s1 = r.join('p1', 'c1', '老张');
  ok(s1 == 1, '第 1 个远端玩家拿到 1 号（实际 $s1）');
  ok(r.nameAt(0) == '房主(你)', '0 号名字没被顶掉（实际 ${r.nameAt(0)}）');
  ok(r.nameAt(1) == '老张', '1 号名字正确');

  print('--- 8 个室友 + 房主 = 9 人局能坐满 ---');
  for (var i = 2; i <= 8; i++) {
    r.join('p$i', 'c$i', '室友$i');
  }
  ok(r.full, '坐满了（${r.joined.length}/${r.playerCount}）');
  ok(r.joined.length == 9, 'joined 正好 9 个（实际 ${r.joined.length}）');
  ok(r.freeSeat() == null, '没有空位了');
  ok(r.join('p99', 'c99', '挤进来') == null, '第 10 个人被挡在门外');
  ok(r.seatOf.values.toSet().length == r.seatOf.length, '座位号没有重复');

  print('--- 按座位发牌，每人拿到的座位唯一 ---');
  final used = <int>{};
  var dup = false;
  for (final e in r.seatOf.entries) {
    if (!used.add(e.value)) dup = true;
  }
  ok(!dup, '远端座位互不冲突');
  ok(!used.contains(0), '没人被发到房主的 0 号');

  print('--- 开局前有人走：座位立刻腾出来给别人 ---');
  final r2 = Room(playerCount: 6);
  r2.join('a', 'ca', 'A');
  r2.join('b', 'cb', 'B');
  ok(!r2.full, '还没坐满');
  final freed = r2.leave('a', keepSeatForRejoin: false);
  ok(freed == 1, 'A 让出了 1 号（实际 $freed）');
  ok(r2.freeSeat() == 1, '1 号又能被人挑中');
  final who = r2.join('c', 'cc', 'C');
  ok(who == 1, 'C 补进 1 号（实际 $who）');
  ok(r2.nameAt(1) == 'C', '1 号名字换成 C');

  print('--- 开局后掉线：座位保留，同身份能认回来 ---');
  final r3 = Room(playerCount: 6);
  r3.join('a', 'ca', 'A');
  r3.join('b', 'cb', 'B');
  final kept = r3.leave('a', keepSeatForRejoin: true);
  ok(kept == null, '开局后离开不让座');
  ok(r3.joined.contains(1), '1 号仍算被占（不会被新人抢走）');
  ok(r3.freeSeat() == 3, '新人只能去 3 号，不能抢 1 号（实际 ${r3.freeSeat()}）');
  final back = r3.join('a2', 'ca', 'A');
  ok(back == 1, 'A 用同一個 cid 认回 1 号（实际 $back）');

  print('--- 重复开标签页 / 重复 join ---');
  final r4 = Room(playerCount: 6);
  final first = r4.join('x', 'cx', 'X');
  final again = r4.join('x', 'cx', 'X');
  ok(first == again, '同一个连接重复 join 不会另占座位');
  final other = r4.join('y', 'cx', 'X-另一个标签页');
  ok(other == first, '同身份开第二个标签页拿回同一个座位（实际 $other）');
  ok(r4.seatOf.length == 1, '旧的连接绑定被顶掉（实际 ${r4.seatOf.length}）');

  print('--- 改人数要清掉越界座位 ---');
  final r5 = Room(playerCount: 9);
  for (var i = 1; i <= 8; i++) {
    r5.join('p$i', 'c$i', 'P$i');
  }
  r5.setPlayerCount(6);
  ok(r5.playerCount == 6, '人数改成 6');
  ok(!r5.joined.any((s) => s >= 6), '6 号及以后的座位被清掉');
  ok(!r5.peerAt.keys.any((s) => s >= 6), '越界连接也解绑了');
  ok(r5.joined.contains(0), '房主的 0 号在改人数后仍然保留');
  ok(r5.joined.length == 6, '剩下 6 个座位（实际 ${r5.joined.length}）');

  print('--- 整局跑通：6 人局能发牌 ---');
  final r6 = Room(playerCount: 6);
  for (var i = 1; i <= 5; i++) {
    r6.join('p$i', 'c$i', 'P$i');
  }
  ok(r6.full, '6 人局坐满');
  final judge = Judge(playerCount: r6.playerCount);
  judge.deal();
  ok(judge.seats.every((s) => s.role != null), '每个座位都拿到牌');
  final wolves =
      judge.seats.where((s) => s.role == Role.werewolf).length;
  ok(wolves == deckFor(6)[Role.werewolf], '狼数符合配牌（$wolves）');

  print('\n通过 $pass 项，失败 $fail 项');
  exit(fail == 0 ? 0 : 1);
}
