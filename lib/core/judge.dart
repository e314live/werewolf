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

/// 神职 = 非狼非民（屠边判定用）
bool isGodRole(Role r) => r != Role.werewolf && r != Role.villager;

/// 人数上限/下限
const int minPlayers = 6;
const int maxPlayers = 18;

/// 胜利条件
enum WinMode {
  slaughterSide, // 屠边：狼杀光全部神职 或 杀光全部平民
  slaughterAll,  // 屠城：狼把好人一个不剩地杀光
}

const Map<WinMode, String> winModeName = {
  WinMode.slaughterSide: '屠边',
  WinMode.slaughterAll: '屠城',
};

const Map<WinMode, String> winModeDesc = {
  WinMode.slaughterSide: '狼人杀光所有神职（预言家/女巫/猎人/守卫），或杀光所有平民，即狼胜。节奏快，主流玩法。',
  WinMode.slaughterAll: '狼人必须把好人一个不剩地全杀光才算赢。拖得久，新手局更友好。',
};

/// 标准局预设牌堆（人数 -> 角色人数）
const Map<int, Map<Role, int>> presets = {
  6: {Role.werewolf: 2, Role.villager: 2, Role.seer: 1, Role.witch: 1},
  9: {Role.werewolf: 3, Role.villager: 3, Role.seer: 1, Role.witch: 1, Role.hunter: 1},
  12: {Role.werewolf: 4, Role.villager: 4, Role.seer: 1, Role.witch: 1, Role.hunter: 1, Role.guard: 1},
};

/// 神职出场优先级：人少时先上预言家、女巫
const List<Role> godOrder = [Role.seer, Role.witch, Role.hunter, Role.guard];

/// 任意人数自动配牌：
///   狼数 ≈ 人数/3（四舍五入，下限 1，至少给好人留 2 席）
///   神职数 = min(狼数, 4, 剩余席位)，按 godOrder 补，其余全是平民
/// 保证：牌堆总数 == 人数，且至少各有 1 神、1 民（除非狼数被手动调到极端值）
Map<Role, int> deckFor(int n, {int? wolfOverride}) {
  final total = n < minPlayers ? minPlayers : n;
  var w = wolfOverride ?? (total / 3).round();
  if (w < 1) w = 1;
  if (w > total - 2) w = total - 2;
  var g = w > godOrder.length ? godOrder.length : w;
  final rest = total - w;
  if (g > rest) g = rest;
  final pool = <Role, int>{Role.werewolf: w};
  for (var i = 0; i < g; i++) {
    pool[godOrder[i]] = 1;
  }
  final v = total - w - g;
  if (v > 0) pool[Role.villager] = v;
  return pool;
}

/// 该人数的自动狼数（UI 展示用）
int autoWolfCount(int n) => deckFor(n)[Role.werewolf] ?? 1;

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
  final WinMode winMode;
  final int? wolfOverride; // null = 自动配狼
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

  /// 开局快照：本局是否存在神职 / 平民（屠边判定用，防止"本来就没有"被判负）
  bool hasGod = false;
  bool hasVillager = false;

  Judge({
    required this.playerCount,
    this.sheriffEnabled = true,
    this.winMode = WinMode.slaughterSide,
    this.wolfOverride,
  }) : seats = List.generate(playerCount, (i) => Seat(i, '玩家${i + 1}'));

  bool get started => phase != Phase.lobby;

  /// 本局牌堆
  Map<Role, int> get deck => deckFor(playerCount, wolfOverride: wolfOverride);

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

  /// 发牌：洗牌后按座位发，只有本 seat 知道自己的 role。
  ///
  /// [seed] 只给测试用：传了就是确定性洗牌，测试结果不会随运行次数飘
  /// （曾经有个"守卫能守别人"的用例随手挑了 0 号，守卫恰好坐上 0 号时必挂）。
  void deal({int? seed}) {
    final pool = <Role>[];
    deck.forEach((r, n) => pool.addAll(List.filled(n, r)));
    // 防御：牌堆与座位数不一致时用平民补齐/截断
    while (pool.length < seats.length) {
      pool.add(Role.villager);
    }
    if (pool.length > seats.length) pool.removeRange(seats.length, pool.length);
    pool.shuffle(seed == null ? _rnd : Random(seed));
    for (var i = 0; i < seats.length; i++) {
      seats[i].role = pool[i];
    }
    hasGod = seats.any((s) => isGodRole(s.role!));
    hasVillager = seats.any((s) => s.role == Role.villager);
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

  /// 女巫行动；解药必须用在今夜被刀的人身上，毒药可选任意人，各限一次
  void witchAct({bool? save, int? poison}) {
    if (cur != Role.witch) return;
    final w = witchSeat;
    if (w == null) return;
    // 今夜没人被刀时，解药不能凭空使用
    if (save == true && nightVictim != null && !seats[w].usedHeal) {
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
    if (p != null && _guardTarget != p && !deaths.contains(p)) deaths.add(p);
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

  /// 白天：从第一个出局者的下家开始发言
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

  int get aliveWolfCount =>
      seats.where((s) => s.alive && s.role == Role.werewolf).length;
  int get aliveGoodCount =>
      seats.where((s) => s.alive && s.role != Role.werewolf).length;
  int get aliveGodCount =>
      seats.where((s) => s.alive && s.role != null && isGodRole(s.role!)).length;
  int get aliveVillagerCount =>
      seats.where((s) => s.alive && s.role == Role.villager).length;

  /// 胜负判定，返回 'good' / 'wolf' / null(继续)
  ///
  /// 屠城：狼全灭 -> 好人胜；狼数 >= 好人数 -> 狼胜
  /// 屠边：狼全灭 -> 好人胜；神职全灭 或 平民全灭 -> 狼胜
  String? checkWinner() {
    final aliveW = aliveWolfCount;
    final aliveG = aliveGoodCount;
    if (aliveW == 0) return 'good';
    if (winMode == WinMode.slaughterAll) {
      if (aliveW >= aliveG) return 'wolf';
      return null;
    }
    // 屠边
    if (hasGod && aliveGodCount == 0) return 'wolf';
    if (hasVillager && aliveVillagerCount == 0) return 'wolf';
    return null;
  }

  /// 一句话说明当前胜利方式（房主界面/结算页展示）
  String winReason() {
    final w = checkWinner();
    if (w == 'good') return '所有狼人出局';
    if (w == null) return '';
    if (winMode == WinMode.slaughterAll) return '好人全部出局';
    if (hasGod && aliveGodCount == 0) return '神职全部出局（屠边）';
    if (hasVillager && aliveVillagerCount == 0) return '平民全部出局（屠边）';
    return '屠边成功';
  }
}
