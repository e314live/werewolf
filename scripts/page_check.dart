// 内嵌网页自检（本机可跑）：
//   1) 结构性断言：关键路由 / 消息类型 / 各界面函数是否齐全
//   2) 把 <script> 抽出来写成文件，交给 node --check 做真正的语法校验
import 'dart:io';

import '../lib/core/judge.dart';
import '../lib/web/page.dart';

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
  final p = webPlayerPage;

  print('--- 页面骨架 ---');
  ok(p.startsWith('<!DOCTYPE html>'), '以 DOCTYPE 开头');
  ok(p.contains('<meta name="viewport"'), '有 viewport，手机上不会缩成一团');
  ok(p.contains('charset="utf-8"'), '声明了 utf-8');
  ok(p.contains('狼邮杀'), '标题带「狼邮杀」');
  ok(RegExp(r'<script>[\s\S]*</script>').hasMatch(p), '有 script 块');
  ok('</html>'.allMatches(p).length == 1, 'html 正常收尾');

  print('--- 与服务端约定一致 ---');
  for (final route in ['/events', '/act', '/bye']) {
    ok(p.contains(route), '用到了 $route');
  }
  ok(p.contains('EventSource'), '用 SSE 长连接（不是 WebSocket）');
  ok(p.contains('sendBeacon'), '退出页面时会告别，好腾座位');

  print('--- 消息类型一个都不能漏 ---');
  for (final t in [
    'seat',
    'full',
    'role',
    'roster',
    'phase',
    'wake',
    'vote_open',
    'vote_result',
    'over',
    'gone',
    'cancel',
  ]) {
    ok(p.contains('t==="' + t + '"'), '处理了 $t');
  }
  for (final k in ['vote', 'guard', 'werewolf', 'seer', 'witch', 'pass']) {
    ok(p.contains(k), '能发出 $k 动作');
  }

  print('--- 各界面都在 ---');
  for (final f in [
    'viewConnect',
    'viewWait',
    'viewIdle',
    'viewVote',
    'viewResult',
    'viewDawn',
    'viewAction',
    'viewOver',
    'roleCard',
    'seatGrid',
  ]) {
    ok(p.contains('function $f('), '有 $f');
  }

  print('--- 引用的处理函数必须真的存在（防 pickPoison 那种幽灵函数） ---');
  final defined = RegExp(r'function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(')
      .allMatches(p)
      .map((x) => x.group(1)!)
      .toSet();
  final referenced = <String>{};
  // HTML 里写死的 onclick="fn(...)"（Dart 里写成 \"，所以两种都收）
  for (final x in RegExp(r'onclick=\\?"([A-Za-z_$][A-Za-z0-9_$]*)\(').allMatches(p)) {
    referenced.add(x.group(1)!);
  }
  // seatGrid(...,"fn") 这种把函数名当参数传的
  for (final x in RegExp(r',\s*"([A-Za-z_$][A-Za-z0-9_$]*)"\s*\)').allMatches(p)) {
    referenced.add(x.group(1)!);
  }
  final missing = referenced.where((f) => !defined.contains(f)).toList()..sort();
  ok(missing.isEmpty, missing.isEmpty
      ? '共引用 ${referenced.length} 个处理函数，全部已定义'
      : '有引用但没定义：${missing.join(', ')}');

  print('--- 不能有重复定义的函数（JS 后者覆盖前者，极易踩坑） ---');
  final seen = <String>{};
  final dup = <String>{};
  for (final x in RegExp(r'function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(').allMatches(p)) {
    if (!seen.add(x.group(1)!)) dup.add(x.group(1)!);
  }
  ok(dup.isEmpty, dup.isEmpty ? '没有重复定义' : '重复定义：${dup.join(', ')}');

  print('--- 角色表要和 Dart 端对得上 ---');
  final m = RegExp('var ROLES=\\[([^\\]]*)\\]').firstMatch(p);
  final listed =
      m == null ? <String>[] : m.group(1)!.split(',').map((s) => s.replaceAll('"', '').trim()).toList();
  final expected = Role.values.map((r) => roleName[r]!).toList();
  ok(listed.length == expected.length,
      '角色条目数一致（页面 ${listed.length} / Dart ${expected.length}）');
  ok(listed.join(',') == expected.join(','),
      '角色顺序一致（页面 ${listed.join('/')}）');

  print('--- 吐 JS 交给 node 验语法 ---');
  final sm = RegExp(r'<script>([\s\S]*)</script>').firstMatch(p);
  if (sm == null) {
    ok(false, '抽不出 script');
  } else {
    final js = sm.group(1)!;
    final dir = Directory('build')..createSync(recursive: true);
    final f = File('${dir.path}/web_player_check.js');
    f.writeAsStringSync(js);
    ok(f.existsSync() && f.lengthSync() > 2000, 'JS 已导出：${f.path}');
    // 顺手导出整页，方便本地双击预览"室友在浏览器里看到的样子"
    final h = File('${dir.path}/web_player.html');
    h.writeAsStringSync(p);
    ok(h.lengthSync() > 5000, '整页已导出：${h.path}（双击即可预览首屏）');
    print('  → 接着用 node --check 验语法');
  }

  print('\n通过 $pass 项，失败 $fail 项');
  exit(fail == 0 ? 0 : 1);
}
