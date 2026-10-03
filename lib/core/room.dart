/// 房间座位管理（纯逻辑，不依赖 Flutter，可以在本机直接跑测试）
///
/// 座位规则：
///   - 0 号永远是房主本人
///   - 远端玩家拿 1..playerCount-1 里最靠前的空位
///   - 认连接（peerId）和客户端的稳定身份（cid），就是不认 IP
///   - 开局后有人掉线：座位保留，等他带着同一个 cid 回来
///   - 开局前有人离开：座位立刻腾出来给别人
class Room {
  Room({required int playerCount, this.hostName = '房主(你)'})
      : _playerCount = playerCount {
    names.add(hostName);
    joined.add(0); // 房主占 0 号，他自己也在玩
  }

  final String hostName;

  int _playerCount;
  int get playerCount => _playerCount;

  /// 各座位上的名字（下标 = 座位号）
  final List<String> names = [];

  /// 已被占用的座位（含"开局后掉线但保留着"的）
  final Set<int> joined = {};

  final Map<String, int> seatOf = {}; // peerId -> 座位
  final Map<int, String> peerAt = {}; // 座位 -> peerId（只记在线的）
  final Map<String, int> seatByCid = {}; // 客户端身份 -> 座位

  bool get full => joined.length >= _playerCount;

  String nameAt(int s) =>
      (s >= 0 && s < names.length && names[s].isNotEmpty) ? names[s] : '玩家${s + 1}';

  /// 改人数：把超出范围的座位清掉（0 号是房主，永远保留）
  void setPlayerCount(int n) {
    _playerCount = n;
    joined.removeWhere((s) => s >= n);
    peerAt.removeWhere((s, _) => s >= n);
    seatOf.removeWhere((_, s) => s >= n);
    seatByCid.removeWhere((_, s) => s >= n);
    while (names.length > n) {
      names.removeLast();
    }
  }

  /// 1..playerCount-1 里最靠前的空位；满了返回 null
  int? freeSeat() {
    for (var s = 1; s < _playerCount; s++) {
      if (!joined.contains(s)) return s;
    }
    return null;
  }

  /// 入座。返回分到的座位；房间满了返回 null。
  int? join(String peerId, String cid, String name) {
    int? seat = seatOf[peerId];
    if (seat == null && cid.isNotEmpty) seat = seatByCid[cid]; // 掉线重连认回原座位
    seat ??= freeSeat();
    if (seat == null) return null;

    // 同一个座位被另一个连接占着（比如又开了一个标签页），先解绑旧的
    final prev = peerAt[seat];
    if (prev != null && prev != peerId) seatOf.remove(prev);

    seatOf[peerId] = seat;
    peerAt[seat] = peerId;
    if (cid.isNotEmpty) seatByCid[cid] = seat;
    joined.add(seat);

    while (names.length <= seat) {
      names.add('');
    }
    final t = name.trim();
    names[seat] = t.isEmpty ? '玩家${seat + 1}' : t;
    return seat;
  }

  /// 离开。返回被让出来的座位号（保留座位等情况返回 null）。
  ///
  /// [keepSeatForRejoin] = 真：开局后掉线，座位留着等他回来。
  int? leave(String peerId, {required bool keepSeatForRejoin}) {
    final seat = seatOf.remove(peerId);
    if (seat == null) return null;
    peerAt.remove(seat);
    if (keepSeatForRejoin) return null; // 座位仍算有人，等他重连
    seatByCid.removeWhere((_, s) => s == seat);
    joined.remove(seat);
    if (seat < names.length) names[seat] = '';
    return seat;
  }

  /// 在线人数
  int get online => peerAt.length;

  List<int> get aliveSeats => joined.toList()..sort();
}
