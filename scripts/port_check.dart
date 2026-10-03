// 端口自愈逻辑自检：占用顺延 / 成功后不残留错误 / 回调不重复
import 'dart:io';

import '../lib/net/lan.dart';

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

Future<void> main() async {
  print('--- LanHost 端口顺延 ---');
  final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, 7788);

  final h = LanHost();
  var hits = 0;
  final got = await h.start(onMsg: (_, __) => hits++);
  ok(got == 7789, '7788 被占用时自动顺延到 7789（实际 $got）');
  ok(h.lastError == null, '成功后 lastError 被清空（实际 ${h.lastError}）');
  ok(h.lastErrorIsPermission == false, '成功后权限标记为 false');
  ok(h.running, '服务处于运行态');

  print('--- 重复开房不叠加回调 ---');
  final again = await h.start(onMsg: (_, __) => hits++);
  ok(again != null, '二次开房成功');
  ok(h.listeners.length == 1, 'listeners 只有 1 个（实际 ${h.listeners.length}）');

  print('--- 客户端收发 ---');
  final c = LanGuest();
  final e = await c.connect('127.0.0.1', again!);
  ok(e == null, '回环直连 OK${e == null ? '' : ' —— $e'}');
  c.send('{"t":"ping","d":{}}\n');
  await Future.delayed(const Duration(milliseconds: 300));
  ok(hits == 1, '房主收到 1 条消息（实际 $hits）');

  await h.stop();
  c.close();
  await blocker.close();
  ok(!h.running && h.listeners.isEmpty, 'stop() 清干净');

  print('\n通过 $pass 项，失败 $fail 项');
  exit(fail == 0 ? 0 : 1);
}
