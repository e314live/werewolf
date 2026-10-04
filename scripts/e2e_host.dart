// 端到端测试用的迷你房主：只负责按固定剧本回消息，配合 scripts/e2e_web.mjs 驱动网页端。
// 目的是让"浏览器里那段 JS"真的跑起来连一次服务端，而不是只做语法检查。
import 'dart:async';
import 'dart:io';

import '../lib/core/judge.dart';
import '../lib/core/protocol.dart';
import '../lib/core/room.dart';
import '../lib/net/lan.dart';

const int e2ePort = 7799;

Future<void> main() async {
  final room = Room(playerCount: 6);
  final lan = LanHost();

  Future<void> poke(String peerId, String line, [int ms = 200]) async {
    await Future.delayed(Duration(milliseconds: ms));
    lan.sendToPeer(peerId, line);
  }

  final got = await lan.start(
    preferred: e2ePort,
    tries: 1,
    onMsg: (peerId, m) async {
      final t = m['t'];
      final d = (m['d'] as Map?) ?? {};

      if (t == 'join') {
        final seat = room.join(
            peerId, (d['cid'] ?? '') as String, (d['name'] ?? '玩家') as String);
        if (seat == null) {
          lan.sendToPeer(peerId, msgFull());
          return;
        }
        lan.sendToPeer(peerId, msgSeat(seat, room.playerCount));
        lan.broadcast(msgRoster(List.generate(
            room.playerCount,
            (i) => {
                  'id': i,
                  'name': room.nameAt(i),
                  'alive': true,
                  'role': null,
                  'isOwner': i == 0,
                })));
        // 剧本：这个玩家是狼人，队友是 4 号（座位 3）。队友里不含自己
        await poke(peerId, msgRole(seat, room.nameAt(seat), Role.werewolf.index));
        await poke(peerId,
            msgPhase('night', 1, alive: [0, 1, 2, 3, 4, 5]), 100);
        await poke(
            peerId,
            msgWake(seat, Role.werewolf.name,
                wolves: [3].where((w) => w != seat).toList(),
                canHeal: null,
                canPoison: null),
            100);
        return;
      }

      if (t == 'gone') {
        room.leave(peerId, keepSeatForRejoin: false);
        // node 那边收尾会 /bye 一声，我们收到就收工，测试跑得快
        await Future.delayed(const Duration(milliseconds: 150));
        await lan.stop();
        stdout.writeln('HOST DONE');
        exit(0);
      }

      if (t != 'act') return;
      final kind = d['kind'];
      final target = d['target'];

      if (kind == 'werewolf') {
        // 刀了 target（可能为空刀），天亮公示 + 开投票
        final deaths = target is int ? [target] : <int>[];
        await poke(peerId,
            msgPhase('dawn', 1, deaths: deaths, alive: [0, 1, 2, 3, 4, 5]), 120);
        await poke(peerId, msgVoteOpen(const [0, 1, 2, 3, 4, 5]), 120);
      } else if (kind == 'vote') {
        await poke(peerId, msgVoteResult({'3': 3, '2': 1}, 3, null), 120);
        await poke(peerId, msgOver('wolf'), 160);
      } else if (kind == 'guard' || kind == 'seer') {
        await poke(peerId, msgWake(1, 'seer_result', target: 3, checked: '狼人'), 120);
      } else if (kind == 'witch') {
        await poke(peerId, msgPhase('dawn', 1, deaths: const [4], alive: const [0, 1, 2, 3, 5]), 120);
      }
    },
  );

  if (got == null) {
    stderr.writeln('HOST BIND FAILED: ${lan.lastError}');
    exit(1);
  }
  stdout.writeln('HOST READY $got');

  // node 正常收尾会 /bye；万一它挂了，靠这个兜底别把测试卡死
  final limit = int.tryParse(Platform.environment['E2E_WAIT_SECONDS'] ?? '12') ?? 12;
  await Future.delayed(Duration(seconds: limit));
  await lan.stop();
  exit(0);
}
