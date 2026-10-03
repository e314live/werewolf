import 'dart:convert';

const int lanPort = 7788;

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
String msgRole(int seat, String name, String role) =>
    toLine(enc('role', {'seat': seat, 'name': name, 'role': role}));
String msgRoster(List<dynamic> seats) => toLine(enc('roster', {'seats': seats}));
String msgWake(int seat, String actor, {List<int>? wolves, int? target, String? checked, bool? saved, int? poisoned}) =>
    toLine(enc('wake', {
      'seat': seat,
      'actor': actor,
      'wolves': wolves,
      'target': target,
      'checked': checked,
      'saved': saved,
      'poisoned': poisoned,
    }));
String msgPhase(String phase, int round, {List<int>? deaths, List<int>? alive}) => toLine(enc('phase', {
      'phase': phase,
      'round': round,
      'deaths': deaths,
      'alive': alive,
    }));
String msgVoteOpen(List<dynamic> seats) => toLine(enc('vote_open', {'seats': seats}));
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
String actMsg(String kind, {int? target, int? save, int? poison}) =>
    toLine(enc('act', {'kind': kind, 'target': target, 'save': save, 'poison': poison}));
