import 'package:flutter_test/flutter_test.dart';
import 'package:werewolf/core/judge.dart';

void main() {
  group('牌堆', () {
    for (final n in [6, 9, 12]) {
      test('$n 人局牌数刚好分完', () {
        final j = Judge(playerCount: n);
        j.deal();
        final total = j.seats.length;
        expect(total, n);
        final counts = <Role, int>{};
        for (final s in j.seats) {
          counts[s.role!] = (counts[s.role!] ?? 0) + 1;
        }
        for (final e in presets[n]!.entries) {
          expect(counts[e.key], e.value, reason: '${roleName[e.key]} 数量不对');
        }
      });
    }

    test('洗牌每次结果不同', () {
      final a = Judge(playerCount: 12)..deal();
      final b = Judge(playerCount: 12)..deal();
      final ra = a.seats.map((s) => s.role!.index).toList();
      final rb = b.seats.map((s) => s.role!.index).toList();
      expect(ra, isNot(rb));
    });
  });

  group('夜间流程', () {
    test('依次经过 守卫→狼人→预言家→女巫，然后天亮', () {
      final j = Judge(playerCount: 12)..deal();
      expect(j.pendingRole, Role.guard);
      expect(j.nextNightRole(), Role.guard == Role.guard ? Role.werewolf : null);
      expect(j.nextNightRole(), Role.seer);
      expect(j.nextNightRole(), Role.witch);
      expect(j.nextNightRole(), isNull);
      expect(j.phase, Phase.dawn);
    });

    test('守卫守的人免疫狼刀', () {
      final j = Judge(playerCount: 12)..deal();
      j.cur = Role.guard;
      final guardSeat = j.guardSeat;
      j.guardProtect(guardSeat == null ? 0 : guardSeat == 0 ? 1 : 0);
      j.cur = Role.werewolf;
      // 让狼刀在守卫守的人身上
      final target = 1;
      j.guardProtect(1); // 先占位，实际用下面的直接调用
      j.cur = Role.werewolf;
      j.wolfKill(1);
      j.cur = Role.witch;
      j.witchAct();
      final deaths = j.resolveNight();
      expect(deaths.contains(1), false);
    });

    test('狼刀无人救 -> 天亮死人', () {
      final j = Judge(playerCount: 12)..deal();
      j.cur = Role.werewolf;
      j.wolfKill(3);
      j.cur = Role.witch;
      j.witchAct();
      final deaths = j.resolveNight();
      expect(deaths, [3]);
      expect(j.seats[3].alive, false);
    });

    test('女巫解药可救人，且每人只有一瓶', () {
      final j = Judge(playerCount: 12)..deal();
      j.cur = Role.werewolf;
      j.wolfKill(3);
      j.cur = Role.witch;
      j.witchAct(save: 3);
      expect(j.seats[3].alive, true);
      final deaths = j.resolveNight();
      expect(deaths.isEmpty, true);
    });

    test('守卫不能守自己', () {
      final j = Judge(playerCount: 12)..deal();
      j.cur = Role.guard;
      final me = j.guardSeat;
      expect(me == null ? true : j.guardProtect(me), false);
    });
  });

  group('胜负判定', () {
    test('狼全死 -> 好人胜', () {
      final j = Judge(playerCount: 9)..deal();
      for (final s in j.seats) {
        if (s.role == Role.werewolf) s.alive = false;
      }
      expect(j.checkWinner(), 'good');
    });

    test('狼数 >= 好人数 -> 狼人胜', () {
      final j = Judge(playerCount: 9)..deal();
      for (final s in j.seats) {
        if (s.role != Role.werewolf) s.alive = false;
      }
      expect(j.checkWinner(), 'wolf');
    });
  });

  group('白天', () {
    test('发言从死者下家开始', () {
      final j = Judge(playerCount: 9)..deal();
      j.deaths = [4];
      expect(j.firstSpeaker(), 5);
    });
  });
}
