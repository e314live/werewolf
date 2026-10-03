import 'dart:math';

/// 角色定义
enum Role { werewolf, villager, seer, witch, hunter, guard }

const Map<Role, String> roleName = {
  Role.werewolf: '狼人',
  Role.villager: '平民',
  Role.seer: '预言家',
  Role.witch: '女巫',
  Role.hunter: '猎人',
  Role.guard: '守卫',
};

const Map<Role, String> roleDesc = {
  Role.werewolf: '每晚可刀一人，与其他狼互认',
  Role.villager: '没有技能，靠推理找出狼人',
  Role.seer: '每晚可查验一人的身份',
  Role.witch: '有一瓶解药(救)与一瓶毒药(毒)，各限一次',
  Role.hunter: '出局时可开枪带走一人（被毒死不能开枪）',
  Role.guard: '每晚可守护一人（不可自守），被守的人免疫刀与毒',
};

const Map<Role, int> roleColor = {
  Role.werewolf: 0xFFD33F49,
  Role.villager: 0xFF5A8FD6,
  Role.seer: 0xFFE8A33D,
  Role.witch: 0xFF8E5BD6,
  Role.hunter: 0xFF4CAF7D,
  Role.guard: 0xFF33A1B1,
};

/// 预设牌堆：人数 -> 角色人数
const Map<int, Map<Role, int>> presets = {
  6: {Role.werewolf: 2, Role.villager: 2, Role.seer: 1, Role.guard: 1},
  9: {Role.werewolf: 3, Role.villager: 3, Role.seer: 1, Role.witch: 1, Role.hunter: 1},
  12: {Role.werewolf: 4, Role.villager: 4, Role.seer: 1, Role.witch: 1, Role.hunter: 1, Role.guard: 1},
};

enum Phase {
  lobby,      // 准备
  nightRole,  // 夜: 某个角色睁眼操作中
  dawn,       // 天亮公示
  dayTalk,    // 白天发言(房主控场, 不强制)
  voting,     // 投票中
  over,       // 结束
}

/// 夜里需要依次睁眼的顺序
const List<Role> nightOrder = [Role.guard, Role.werewolf, Role.seer, Role.witch];

class Seat {
  final int id;
  String name;
  Role? role;
  bool alive = true;
  bool usedHeal = false;
  bool usedPoison = false;
  bool usedGun = false;
  bool isSheriff = false;
  int voteCount = 0;

  Seat(this.id, this.name);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role == null ? null : role!.index,
        'alive': alive,
        'usedHeal': usedHeal,
        'usedPoison': usedPoison,
        'usedGun': usedGun,
        'isSheriff': isSheriff,
      };
}

/// 一个回合事件，交给 UI 渲染
class JudgeEvent {
  final String type;
  final Map<String, dynamic> data;
  JudgeEvent(this.type, this.data);
}

/// 房主端裁判：持有全部真相，驱动状态机
class Judge {
  final int playerCount;
  final bool sheriffEnabled;
  final List<Seat> seats;
  final Random _rnd = Random();

  Phase phase = Phase.lobby;
  int round = 0;

  Role? cur;               // 当前正在睁眼的角色
  int? _guardTarget;
  int? nightVictim;        // 本夜被刀人
  bool witchSaved = false;
  int? witchPoisonTarget;
  List<int> deaths = [];   // 本日出局
  String? winner;

  Judge({required this.playerCount, this.sheriffEnabled = true})
      : seats = List.generate(playerCount, (i) => Seat(i, '玩家${i + 1}'));

  bool get started => phase != Phase.lobby;

  int? get wolfSeat {
    if (cur != Role.werewolf) return null;
    final w = seats.where((s) => s.role == Role.werewolf && s.alive).toList();
    return w.isEmpty ? null : w.first.id;
  }

  int? get seerSeat {
    if (cur != Role.seer) return null;
    final s = seats.where((x) => x.role == Role.seer && x.alive).toList();
    return s.isEmpty ? null : s.first.id;
  }

  int? get witchSeat {
    if (cur != Role.witch) return null;
    final s = seats.where((x) => x.role == Role.witch && x.alive).toList();
    return s.isEmpty ? null : s.first.id;
  }

  int? get guardSeat {
    if (cur != Role.guard) return null;
    final s = seats.where((x) => x.role == Role.guard && x.alive).toList();
    return s.isEmpty ? null : s.first.id;
  }

  Role? get pendingRole => cur;
  set pendingRole(Role? v) => cur = v;

  /// 发牌：洗牌后按座位发，只有本 seat 知道自己的 role
  void deal() {
    final pool = <Role>[];
    final preset = presets[playerCount] ?? presets[9]!;
    preset.forEach((r, n) => pool.addAll(List.filled(n, r)));
    pool.shuffle(_rnd);
    for (var i = 0; i < seats.length; i++) seats[i].role = pool[i];
    phase = Phase.nightRole;
    round = 1;
    cur = nightOrder.first;
  }

  /// 推进到下一个该睁眼的阶段；返回 null 表示入夜结束、进入天亮
  Role? nextNightRole() {
    final i = nightOrder.indexOf(cur!);
    if (i + 1 < nightOrder.length) {
      cur = nightOrder[i + 1];
      return cur;
    }
    return null;
  }

  /// 狼人刀人
  void wolfKill(int target) {
    if (cur != Role.werewolf) return;
    nightVictim = target;
  }

  /// 守卫守人（不可自守）
  bool guardProtect(int target) {
    if (cur != Role.guard) return false;
    if (target == guardSeat) return false;
    _guardTarget = target;
    return true;
  }

  /// 预言家查验，返回被验人身份
  Role? seerCheck(int target) {
    if (cur != Role.seer) return null;
    return seats[target].role;
  }

  /// 女巫行动；解药与毒药各限一次
  void witchAct({bool? save, int? poison}) {
    if (cur != Role.witch) return;
    final w = witchSeat;
    if (w == null) return;
    if (save == true && !seats[w].usedHeal) {
      witchSaved = true;
      seats[w].usedHeal = true;
    }
    if (poison != null && !seats[w].usedPoison) {
      witchPoisonTarget = poison;
      seats[w].usedPoison = true;
    }
  }

  /// 结算本夜，返回出局名单
  List<int> resolveNight() {
    deaths = [];
    final v = nightVictim;
    if (v != null) {
      final guarded = _guardTarget == v;
      if (!guarded && !witchSaved) deaths.add(v);
    }
    final p = witchPoisonTarget;
    if (p != null && _guardTarget != p) deaths.add(p);
    for (final d in deaths) {
      if (d >= 0 && d < seats.length) seats[d].alive = false;
    }
    clearNight();
    phase = Phase.dawn;
    return deaths;
  }

  void clearNight() {
    _guardTarget = null;
    nightVictim = null;
    witchSaved = false;
    witchPoisonTarget = null;
  }

  /// 白天：从第一个死亡者的下家开始发言
  int firstSpeaker() {
    if (deaths.isEmpty) return 0;
    final d = deaths.first;
    return (d + 1) % playerCount;
  }

  /// 白天放逐后进入下一夜
  void startNextNight() {
    phase = Phase.nightRole;
    round++;
    cur = nightOrder.first;
  }

  /// 胜负判定
  String? checkWinner() {
    final aliveW = seats.where((s) => s.alive && s.role == Role.werewolf).length;
    final aliveG = seats.where((s) => s.alive && s.role != Role.werewolf).length;
    if (aliveW == 0) return 'good';
    if (aliveW >= aliveG) return 'wolf';
    return null;
  }
}
