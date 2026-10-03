import 'dart:io';

import '../core/protocol.dart';

/// 本机在局域网里的可用 IPv4（排除回环/广播）
Future<List<String>> localIps() async {
  final out = <String>[];
  try {
    final list = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final i in list) {
      // NetworkInterface 没有 .address 字段，只有 .addresses(List<InternetAddress>)
      for (final a in i.addresses) {
        final s = a.address;
        if (!s.endsWith('.255') && !s.endsWith('.0')) out.add(s);
      }
    }
  } on SocketException {
    // 无网络时忽略
  }
  return out;
}

/// 房主：起一个局域网 TCP 服务当"法官主机"
class LanHost {
  ServerSocket? _ss;
  int? _port;
  String? lastError;

  /// 上一次失败是不是"没权限"而不是"端口被占用"
  bool lastErrorIsPermission = false;
  final List<Socket> clients = [];
  final List<void Function(String, Map<String, dynamic>)> listeners = [];

  bool get running => _ss != null;

  /// 实际监听的端口（默认端口被占用时自动顺延）
  int get port => _port ?? defaultPort;

  /// 把底层异常翻译成能看懂的原因
  static bool _isPermDenied(String msg) {
    final m = msg.toLowerCase();
    return m.contains('denied') ||
        m.contains('permitted') ||
        m.contains('eacces') ||
        m.contains('eperm') ||
        m.contains('permission');
  }

  /// 开房。preferred 起试，被占用就往后顺延，最多试 tries 个。
  /// 返回实际端口；全部失败返回 null（原因在 lastError）。
  Future<int?> start({
    int preferred = defaultPort,
    int tries = 12,
    void Function(String, Map<String, dynamic>)? onMsg,
  }) async {
    // 先停旧的，再注册回调，避免重复开房时回调被叠加多次
    await stop();
    if (onMsg != null) listeners.add(onMsg);
    lastError = null;
    lastErrorIsPermission = false;
    for (var i = 0; i < tries; i++) {
      final p = preferred + i;
      if (p > 65535) break;
      try {
        _ss = await ServerSocket.bind(InternetAddress.anyIPv4, p);
        _port = p;
        // 成功就把前面几次试错留下的错误清掉，别让 UI 误报
        lastError = null;
        lastErrorIsPermission = false;
        break;
      } on SocketException catch (e) {
        final raw = e.message.isEmpty ? e.osError?.message ?? '' : e.message;
        lastErrorIsPermission = _isPermDenied(raw);
        lastError = lastErrorIsPermission
            ? '本机不允许 App 联网（缺少 INTERNET 权限），不是端口问题'
            : (raw.isEmpty ? '端口 $p 不可用' : raw);
        _ss = null;
      }
    }
    if (_ss == null) return null;
    _ss!.listen((sock) {
      clients.add(sock);
      final buf = StringBuffer();
      sock.listen(
        (data) {
          buf.write(String.fromCharCodes(data));
          final parts = buf.toString().split('\n');
          for (var i = 0; i < parts.length - 1; i++) {
            final m = fromLine(parts[i]);
            if (m != null) {
              for (final l in List.from(listeners)) l('${sock.remoteAddress.address}', m);
            }
          }
          buf.clear();
          buf.write(parts.last);
        },
        onError: (_) => _drop(sock),
        onDone: () => _drop(sock),
      );
    });
    return _port;
  }

  void _drop(Socket s) {
    s.destroy();
    clients.remove(s);
  }

  void sendTo(String ip, String line) {
    for (final c in clients) {
      if (c.remoteAddress.address == ip) c.write(line);
    }
  }

  void broadcast(String line) {
    for (final c in List.from(clients)) {
      try {
        c.write(line);
      } catch (_) {
        _drop(c);
      }
    }
  }

  /// 按座位序号发送（座位号与 clients 顺序绑定）
  void sendToSeat(int seat, String line) {
    if (seat >= 0 && seat < clients.length) {
      try {
        clients[seat].write(line);
      } catch (_) {}
    }
  }

  int get connected => clients.length;

  Future<void> stop() async {
    for (final c in List.from(clients)) {
      try {
        c.destroy();
      } catch (_) {}
    }
    clients.clear();
    listeners.clear();
    await _ss?.close();
    _ss = null;
    _port = null;
  }
}

/// 玩家：连房主的 TCP 服务
class LanGuest {
  Socket? _sock;
  final List<void Function(Map<String, dynamic>)> listeners = [];

  bool get connected => _sock != null;

  Future<String?> connect(String host, int port,
      {void Function(Map<String, dynamic>)? onMsg}) async {
    if (onMsg != null) listeners.add(onMsg);
    try {
      _sock = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
    } on Exception catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('denied') || m.contains('permitted') || m.contains('eacces') || m.contains('eperm')) {
        return '连不上房主：本机不允许 App 联网（缺少 INTERNET 权限），不是地址填错，请装最新版的狼邮杀';
      }
      return '连不上房主 $host:$port —— 检查是不是同一个 WiFi、房主屏幕上的地址有没有填错';
    }
    final buf = StringBuffer();
    _sock!.listen(
      (data) {
        buf.write(String.fromCharCodes(data));
        final parts = buf.toString().split('\n');
        for (var i = 0; i < parts.length - 1; i++) {
          final m = fromLine(parts[i]);
          if (m != null) for (final l in List.from(listeners)) l(m);
        }
        buf.clear();
        buf.write(parts.last);
      },
      onError: (_) => _gone(),
      onDone: () => _gone(),
    );
    return null;
  }

  void _gone() {
    _sock?.destroy();
    _sock = null;
    for (final l in List.from(listeners)) l({'t': 'gone', 'd': {}});
  }

  void send(String line) {
    try {
      _sock?.write(line);
    } catch (_) {}
  }

  void close() {
    _sock?.destroy();
    _sock = null;
  }
}
