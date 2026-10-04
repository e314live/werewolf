// 本机预览服务：起一个"假房主"，让网页玩家端能在电脑浏览器里直接连上看看。
//
// 跟 e2e_host.dart 的区别：这个常驻不退出，端口用 App 的默认 7788，
// 目的是"给人看"而不是"给 CI 跑"。
//
// 用法：
//   dart run scripts/preview_host.dart
//   然后浏览器打开终端里打印的 http://127.0.0.1:7788
import 'dart:async';
import 'dart:io';

import '../lib/core/judge.dart';
import '../lib/core/protocol.dart';
import '../lib/core/room.dart';
import '../lib/net/lan.dart';

const int previewPort = 7788;

Future<void> main() async {
  final room = Room(playerCount: 9);
  final lan = LanHost();

  Future<void> poke(String peerId, String line, [int ms = 260]) async {
    await Future.delayed(Duration(milliseconds: ms));
    lan.sendToPeer(peerId, line);
  }

  List<Map<String, dynamic>> roster() => List.generate(
        room.playerCount,
        (i) => {
          'id': i,
          'name': room.nameAt(i),
          'alive': true,
          'role': null,
          'isOwner': i == 0,
        },
      );

  final got = await lan.start(
    preferred: previewPort,
    tries: 6,
    onMsg: (peerId, m) async {
      final t = m['t'];
      final d = (m['d'] as Map?) ?? {};

      if (t == 'join') {
        final name = (d['name'] ?? '室友') as String;
        final seat =
            room.join(peerId, (d['cid'] ?? '') as String, name);
        if (seat == null) {
          lan.sendToPeer(peerId, msgFull());
          return;
        }
        stdout.writeln('[预览] $name 入场 -> 座位 ${seat + 1} 号');
        lan.sendToPeer(peerId, msgSeat(seat, room.playerCount));
        lan.broadcast(msgRoster(roster()));

        // 剧本：让你当狼人，队友是 3 号位，走一遍 天黑 -> 刀人 -> 天亮 -> 投票 -> 结算
        await poke(peerId, msgRole(seat, name, Role.werewolf.index), 900);
        await poke(peerId, msgPhase('night', 1,
            alive: List.generate(room.playerCount, (i) => i)), 400);
        await poke(
            peerId,
            msgWake(seat, Role.werewolf.name,
                wolves: [3].where((w) => w != seat).toList(),
                canHeal: null,
                canPoison: null),
            500);
        return;
      }

      if (t == 'gone') {
        room.leave(peerId, keepSeatForRejoin: false);
        stdout.writeln('[预览] 有人离场，座位已腾出');
        return; // 预览模式不退，等着下一个连进来
      }

      if (t != 'act') return;
      final kind = d['kind'];
      final target = d['target'];

      if (kind == 'werewolf') {
        final deaths = target is int ? [target] : const <int>[];
        final alive = List.generate(room.playerCount, (i) => i)
            .where((i) => !deaths.contains(i))
            .toList();
        await poke(peerId, msgPhase('dawn', 1, deaths: deaths, alive: alive));
        await poke(peerId, msgVoteOpen(alive));
      } else if (kind == 'vote') {
        await poke(peerId, msgVoteResult({'3': 3, '2': 1}, 3, null));
        await poke(peerId, msgOver('wolf'), 200);
      } else if (kind == 'guard' || kind == 'seer') {
        await poke(peerId,
            msgWake(1, 'seer_result', target: 3, checked: '狼人'),
            200);
      } else if (kind == 'witch') {
        await poke(peerId, msgPhase('dawn', 1, deaths: const [4], alive: const [0, 1, 2, 3, 5]));
      }
    },
  );

  if (got == null) {
    stderr.writeln('起不来：${lan.lastError}');
    exit(1);
  }

  final ips = await localIps();
  stdout.writeln('┌─ 预览服务已就绪 ────────────────────────');
  stdout.writeln('│  本机打开：http://127.0.0.1:$got');
  for (final ip in ips) {
    stdout.writeln('│  同一 WiFi 的手机：http://$ip:$got');
  }
  stdout.writeln('│  按 Ctrl-C 结束');
  stdout.writeln('└──────────────────────────────────────────');

  // 常驻，别退出
  await Completer<void>().future;
}
