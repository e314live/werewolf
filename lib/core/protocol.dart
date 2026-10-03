import 'dart:convert';

/// 默认监听端口；被占用时房主会自动往后顺延
const int defaultPort = 7788;

/// 解析房主地址，兼容这些写法：
///   "10.16.3.7"            -> 10.16.3.7:7788
///   "10.16.3.7:7789"       -> 10.16.3.7:7789
///   "http://10.16.3.7:7789/" -> 10.16.3.7:7789
({String ip, int port}) parseAddr(String raw) {
  var t = raw.trim().replaceFirst(RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://'), '');
  t = t.split('/').first.trim();
  if (t.isEmpty) return (ip: '', port: defaultPort);
  final i = t.lastIndexOf(':');
  if (i > 0 && i < t.length - 1) {
    final p = int.tryParse(t.substring(i + 1).trim());
    if (p != null && p > 0 && p <= 65535) {
      return (ip: t.substring(0, i).trim(), port: p);
    }
  }
  return (ip: t, port: defaultPort);
}

/// 一行一条消息：{"t":"type","d":{...}}
Map<String, dynamic> enc(String type, Map<String, dynamic> data) => {'t': type, 'd': data};

String toLine(Map<String, dynamic> msg) => '${jsonEncode(msg)}\n';

Map<String, dynamic>? fromLine(String raw) {
  raw = raw.trim();
  if (raw.isEmpty) return null;
  try {
    return jsonDecode(raw) as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
}

/* ---------- 房主 -> 客户端 ---------- */
/// role 用 Role.index（int），客户端直接查表，避免中文名对不上
String msgRole(int seat, String name, int roleIndex) =>
    toLine(enc('role', {'seat': seat, 'name': name, 'role': roleIndex}));
String msgRoster(List<dynamic> seats) => toLine(enc('roster', {'seats': seats}));
String msgWake(int seat, String actor,
        {List<int>? wolves,
        int? target,
        String? checked,
        bool? saved,
        int? poisoned,
        bool? canHeal,
        bool? canPoison}) =>
    toLine(enc('wake', {
      'seat': seat,
      'actor': actor,
      'wolves': wolves,
      'target': target,
      'checked': checked,
      'saved': saved,
      'poisoned': poisoned,
      'canHeal': canHeal,
      'canPoison': canPoison,
    }));
String msgPhase(String phase, int round, {List<int>? deaths, List<int>? alive}) =>
    toLine(enc('phase', {
      'phase': phase,
      'round': round,
      'deaths': deaths,
      'alive': alive,
    }));
String msgVoteOpen(List<dynamic> seats, {bool revote = false}) =>
    toLine(enc('vote_open', {'seats': seats, 'revote': revote}));
String msgVoteResult(Map<String, dynamic> tally, int? ejected, int? gun) =>
    toLine(enc('vote_result', {'tally': tally, 'ejected': ejected, 'gun': gun}));
String msgOver(String winner) => toLine(enc('over', {'winner': winner}));
String msgSheriff(int seat, {bool? voteResult}) =>
    toLine(enc('sheriff', {'seat': seat, 'vote': voteResult}));
String msgCancel() => toLine(enc('cancel', {}));

/* ---------- 客户端 -> 房主 ---------- */
String msgJoin(String name) => toLine(enc('join', {'name': name}));
String msgReady() => toLine(enc('ready', {}));
String msgPass() => toLine(enc('pass', {}));

/// save 是「是否使用解药」（bool），poison 是「毒谁」（座位号）
String actMsg(String kind, {int? target, bool? save, int? poison}) =>
    toLine(enc('act', {'kind': kind, 'target': target, 'save': save, 'poison': poison}));
