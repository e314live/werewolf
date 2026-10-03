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
  final List<Socket> clients = [];
  final List<void Function(String, Map<String, dynamic>)> listeners = [];

  bool get running => _ss != null && !_ss!.address.isLoopback || _ss != null;

  Future<String?> start(int port, {void Function(String, Map<String, dynamic>)? onMsg}) async {
    if (onMsg != null) listeners.add(onMsg);
    try {
      _ss = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (e) {
      return '端口被占用：${e.message}';
    }
    _ss!.listen((sock) {
      clients.add(sock);
      final buf = StringBuffer();
      sock.listen(
        (data) {
          buf.write(String.fromCharCodes(data));
          var s = buf.toString();
          final parts = s.split('\n');
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
    return null;
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
    await _ss?.close();
    _ss = null;
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
      return '连不上房主：$e';
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
