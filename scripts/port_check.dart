// 网络层自检（本机可跑，不需要真机）：
//   端口顺延 / 成功后不残留错误 / 回调不重复
//   网页能取到 / SSE 下行 / POST 上行 / 多端在线 / 断线腾座位
import 'dart:convert';
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

Future<void> tick([int ms = 300]) =>
    Future.delayed(Duration(milliseconds: ms));

/// 用一组冷门端口做测试。
/// 默认的 7788 很可能被你本地开着的预览服务（preview_host.dart）占着，
/// 那时候这个脚本会莫名其妙地崩，跟你改的代码其实一点关系都没有。
const int testBase = 17788;

Future<void> main() async {
  print('--- LanHost 端口顺延 ---');
  final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, testBase);

  final h = LanHost();
  final seen = <String, List<Map<String, dynamic>>>{};
  final got = await h.start(preferred: testBase, onMsg: (peer, m) {
    (seen[peer] ??= []).add(m);
  });
  ok(got == testBase + 1, '$testBase 被占用时自动顺延（实际 $got）');
  ok(h.lastError == null, '成功后 lastError 被清空（实际 ${h.lastError}）');
  ok(h.lastErrorIsPermission == false, '成功后权限标记为 false');
  ok(h.running, '服务处于运行态');

  print('--- 重复开房 ---');
  final again = await h.start(preferred: testBase, onMsg: (peer, m) {
    (seen[peer] ??= []).add(m);
  });
  ok(again != null, '二次开房成功');
  ok(h.listeners.length == 1, 'listeners 只有 1 个（实际 ${h.listeners.length}）');

  print('--- 浏览器端：GET / 能拿到玩家页 ---');
  final http = HttpClient();
  final res = await (await http.get('127.0.0.1', again!, '/')).close();
  final html = await res.transform(utf8.decoder).join();
  ok(res.statusCode == 200, 'HTTP 200（实际 ${res.statusCode}）');
  ok(res.headers.contentType?.mimeType == 'text/html', 'Content-Type 是 text/html');
  ok(html.contains('狼邮杀'), '页面里有「狼邮杀」');
  ok(html.contains('EventSource'), '页面用的是 SSE 长连接');
  ok(html.contains('/events'), '页面里有 /events 订阅地址');
  ok(html.contains('/act'), '页面里有 /act 上行地址');
  ok(html.contains('id="app"'), '页面有渲染挂载点');
  ok(!html.contains(r'\\"'), '页面里没有多余的反斜杠转义（会打断 JS）');

  final fav = await (await http.get('127.0.0.1', again, '/favicon.ico')).close();
  ok(fav.statusCode == 204, 'favicon 返回 204，不刷屏');
  await fav.drain<void>();

  print('--- SSE 下行 + POST 上行（App 与网页同一条路）---');
  final g = LanGuest('c1');
  final inb = <Map<String, dynamic>>[];
  g.listeners.add(inb.add);
  final e = await g.connect('127.0.0.1', again, name: '老张');
  ok(e == null, '连上房主 OK${e == null ? '' : ' —— $e'}');
  ok(g.connected, 'connected 为 true');

  await tick();
  final ids = seen.keys.toList();
  ok(ids.length == 1, '房主侧登记了 1 个连接（实际 ${ids.length}）');
  final pid = ids.isEmpty ? '' : ids.first;
  final msgs = seen[pid] ?? [];
  final join = msgs.where((m) => m['t'] == 'join').toList();
  ok(join.length == 1, '房主收到 join');
  ok(join.isNotEmpty && join.first['d']['name'] == '老张', 'join 里带着名字');
  ok(join.isNotEmpty && join.first['d']['cid'] == 'c1', 'join 里带着稳定身份 cid');

  h.sendToPeer(pid, '{"t":"seat","d":{"seat":3,"total":9}}\n');
  await tick();
  ok(inb.any((m) => m['t'] == 'seat'), '客户端收到下行消息');
  final seatMsg = inb.firstWhere((m) => m['t'] == 'seat', orElse: () => {});
  ok(seatMsg['d']?['seat'] == 3, '下行消息内容正确');

  g.send('{"t":"act","d":{"kind":"vote","target":2}}\n');
  await tick();
  ok((seen[pid] ?? []).any((m) => m['t'] == 'act'), '房主收到上行操作');

  print('--- 多端同时在线 ---');
  final g2 = LanGuest('c2');
  final e2 = await g2.connect('127.0.0.1', again, name: '老王');
  await tick();
  ok(e2 == null && h.connected == 2, '两个玩家同时在线（实际 ${h.connected}）');
  final pid2 = seen.keys.firstWhere((k) => k != pid, orElse: () => '');
  g2.close();
  await tick(500);
  ok(h.connected == 1, '一方断开后剩下 1 个（实际 ${h.connected}）');
  ok((seen[pid2] ?? []).any((m) => m['t'] == 'gone'), '断开有通知给上层（好腾座位）');

  print('--- 收尾 ---');
  await h.stop();
  g.close();
  await blocker.close();
  ok(!h.running && h.listeners.isEmpty && h.connected == 0, 'stop() 清干净');

  print('\n通过 $pass 项，失败 $fail 项');
  exit(fail == 0 ? 0 : 1);
}
