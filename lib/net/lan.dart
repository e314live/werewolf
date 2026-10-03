import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/protocol.dart';
import '../web/page.dart';

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

/// 一个连上来的玩家。App 和浏览器在这一层没有区别。
class Peer {
  Peer(this.id, this.ip, this._send, this._kill);

  final String id; // 连接级唯一 id：座位认它，不认 IP
  final String ip;
  final void Function(String line) _send;
  final void Function() _kill;

  bool alive = true;

  void send(String line) {
    if (!alive) return;
    _send(line);
  }

  /// 主动掐掉这条连接（被同身份的新连接顶替时用）
  void forceClose() {
    alive = false;
    try {
      _kill();
    } catch (_) {}
  }
}

/// 房主：起一个 HTTP 服务当"法官主机"。只占一个端口，室友看到的地址只有一个。
///
///   GET  /                        -> 浏览器玩家端（手机浏览器打开就能玩）
///   GET  /events?cid=&name=       -> 服务端推送（SSE），这条连接 = 一个玩家
///   POST /act?cid=  body=一行JSON -> 玩家操作上行
///
/// 不用 WebSocket 的原因：本机 Dart 3.13 的 WebSocket.connect 握手缺
/// Connection/Upgrade 头，对着自己的 HttpServer 会被判 400。
/// SSE + POST 是纯 HTTP，浏览器和 App 都稳。
class LanHost {
  HttpServer? _http;
  int? _port;
  String? lastError;

  /// 上一次失败是不是"没权限"而不是"端口被占用"
  bool lastErrorIsPermission = false;

  final List<Peer> peers = [];
  final Map<String, Peer> _byId = {};
  final List<void Function(String, Map<String, dynamic>)> listeners = [];

  /// 客户端自报的稳定身份 -> 连接 id（断线重连认回座位用）
  final Map<String, String> _cidToPeer = {};

  int _seq = 0;

  bool get running => _http != null;

  /// 实际监听的端口（默认端口被占用时自动顺延）
  int get port => _port ?? defaultPort;

  int get connected => peers.length;

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
    void Function(String peerId, Map<String, dynamic> msg)? onMsg,
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
        _http = await HttpServer.bind(InternetAddress.anyIPv4, p);
        _port = p;
        lastError = null;
        lastErrorIsPermission = false;
        break;
      } on SocketException catch (e) {
        final raw = e.message.isEmpty ? e.osError?.message ?? '' : e.message;
        lastErrorIsPermission = _isPermDenied(raw);
        lastError = lastErrorIsPermission
            ? '本机不允许 App 联网（缺少 INTERNET 权限），不是端口问题'
            : (raw.isEmpty ? '端口 $p 不可用' : raw);
        _http = null;
      }
    }
    if (_http == null) return null;

    _http!.serverHeader = null;
    // SSE 是长时间挂着的响应，别让空闲超时把它掐了
    _http!.idleTimeout = const Duration(minutes: 30);
    _http!.listen(_onRequest, onError: (_) {});
    return _port;
  }

  Future<void> _onRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;

      if (path == '/events') {
        await _openStream(req);
        return;
      }

      if (path == '/act' && req.method == 'POST') {
        await _ingest(req);
        return;
      }

      // 客户端主动告别。Dart 这边的 HttpResponse 既不会因为 socket 断开
      // 而完成 done，也不会因为对端没了而让 write 报错 —— 只能靠对方说一声。
      if (path == '/bye') {
        final cid = req.uri.queryParameters['cid'] ?? '';
        try {
          req.response
            ..statusCode = HttpStatus.noContent
            ..headers.set('Cache-Control', 'no-store');
          await req.response.close();
        } catch (_) {}
        final peerId = _cidToPeer[cid];
        final p = peerId == null ? null : _byId[peerId];
        if (p != null) _kill(p);
        return;
      }

      if (path == '/' || path == '/index.html') {
        final bytes = utf8.encode(webPlayerPage);
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
          ..headers.set('Cache-Control', 'no-store')
          ..headers.contentLength = bytes.length;
        req.response.add(bytes);
        await req.response.close();
        return;
      }

      if (path == '/favicon.ico') {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      // 单个请求出错不能拖垮整个房间
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// 玩家上行：POST 一行 JSON，立刻 204，不当长连接用
  Future<void> _ingest(HttpRequest req) async {
    final cid = req.uri.queryParameters['cid'] ?? '';
    String body = '';
    try {
      body = await utf8.decoder.bind(req).join();
    } catch (_) {}
    try {
      req.response
        ..statusCode = HttpStatus.noContent
        ..headers.set('Cache-Control', 'no-store');
      await req.response.close();
    } catch (_) {}

    final peerId = _cidToPeer[cid];
    if (peerId == null) return;
    final m = fromLine(body);
    if (m != null) _emit(peerId, m);
  }

  /// 玩家下行：SSE 长连接
  Future<void> _openStream(HttpRequest req) async {
    final cid = req.uri.queryParameters['cid'] ?? '';
    final name = (req.uri.queryParameters['name'] ?? '室友').trim();
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';

    // 同一个身份又连上来（浏览器 EventSource 会自动重连）：顶掉旧连接，
    // 但不要发 gone，否则上层会把刚认回来的座位又腾掉。
    if (cid.isNotEmpty) {
      final oldId = _cidToPeer[cid];
      final old = oldId == null ? null : _byId[oldId];
      if (old != null) {
        _cidToPeer.remove(cid);
        _byId.remove(old.id);
        peers.remove(old);
        old.forceClose();
      }
    }

    final res = req.response;
    // 关键①：bufferOutput 默认 true，body 会攒在缓冲区里，这时连 flush()
    // 都只把响应头发出去 —— SSE 就变成"连上了但永远收不到消息"。
    // 关键②：bufferOutput=false 之后，write() 自己就是即时的；
    // 此时再调 flush() 只要有一次还没完成就又来一次，就会抛
    // `Bad state: StreamSink is bound to a stream` 把整条连接打死。
    // 所以整条链路统一：只 write，绝不 flush。
    res.bufferOutput = false;
    res
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..headers.set('Cache-Control', 'no-store')
      ..headers.set('X-Accel-Buffering', 'no');
    res.write(': ok\n\n');

    final id = 'p${++_seq}';
    Timer? beat;
    late Peer peer;
    peer = Peer(
      id,
      ip,
      (line) {
        try {
          // bufferOutput=false，write 即刻下发，不需要（也不能）flush
          res.write('data: ${line.trimRight()}\n\n');
        } catch (_) {
          _kill(peer);
        }
      },
      () {
        beat?.cancel();
        try {
          res.close();
        } catch (_) {}
      },
    );

    peers.add(peer);
    _byId[id] = peer;
    if (cid.isNotEmpty) _cidToPeer[cid] = id;

    // 心跳：推不动了就说明对端没了（尽力而为，主要靠客户端 /bye 告别）
    beat = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        res.write(': ping\n\n');
      } catch (_) {
        _kill(peer);
      }
    });

    // 上层照旧按 join 处理，只是这条 join 是房主自己造的
    _emit(id, enc('join', {'name': name.isEmpty ? '室友' : name, 'cid': cid}));
  }

  void _kill(Peer p) {
    if (!p.alive) return;
    p.forceClose();
    peers.remove(p);
    _byId.remove(p.id);
    _cidToPeer.removeWhere((_, pid) => pid == p.id);
    _emit(p.id, {'t': 'gone', 'd': {}});
  }

  void _emit(String peerId, Map<String, dynamic> msg) {
    for (final l in List.from(listeners)) {
      l(peerId, msg);
    }
  }

  void sendToPeer(String peerId, String line) => _byId[peerId]?.send(line);

  /// 把客户端自报的稳定身份绑到这条连接上。
  /// /events 建连时已经绑过一次，这里再绑是让意图显式化：
  /// /act 和 /bye 都靠 cid 找回连接，丢了就会"操作石沉大海"。
  void bindCid(String cid, String peerId) {
    if (cid.isEmpty) return;
    if (_byId.containsKey(peerId)) _cidToPeer[cid] = peerId;
  }

  void broadcast(String line) {
    for (final p in List.from(peers)) {
      p.send(line);
    }
  }

  Future<void> stop() async {
    listeners.clear();
    final old = List<Peer>.from(peers);
    peers.clear();
    _byId.clear();
    _cidToPeer.clear();
    for (final p in old) {
      p.forceClose();
    }
    final h = _http;
    _http = null;
    _port = null;
    try {
      await h?.close(force: true);
    } catch (_) {}
  }
}

/// 玩家：拉房主的 SSE 长连接收消息，POST 发操作
class LanGuest {
  LanGuest(this.cid);

  /// 本次开 App 的稳定身份，房主凭它认回座位
  final String cid;

  final List<void Function(Map<String, dynamic>)> listeners = [];

  HttpClient? _client;
  HttpClientResponse? _res;
  String _host = '';
  int _port = 0;
  bool _closing = false;

  bool get connected => _res != null;

  Future<String?> connect(
    String host,
    int port, {
    String name = '玩家',
    void Function(Map<String, dynamic>)? onMsg,
  }) async {
    if (onMsg != null) listeners.add(onMsg);
    _closing = false;
    _host = host;
    _port = port;

    _client?.close(force: true);
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(minutes: 10);
    _client = c;

    try {
      final url = '/events?cid=${Uri.encodeComponent(cid)}'
          '&name=${Uri.encodeComponent(name)}';
      final req = await c.get(host, port, url);
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return '房主回了 ${res.statusCode}，确认地址是房主屏幕上显示的那个';
      }
      _res = res;
      res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data:')) return;
          final m = fromLine(line.substring(5));
          if (m != null) {
            for (final l in List.from(listeners)) {
              l(m);
            }
          }
        },
        onError: (_) => _gone(),
        onDone: () => _gone(),
        cancelOnError: true,
      );
      return null;
    } on TimeoutException {
      return '连不上房主 $host:$port —— 检查是不是同一个 WiFi、房主屏幕上的地址填对没';
    } on Exception catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('denied') ||
          m.contains('permitted') ||
          m.contains('eacces') ||
          m.contains('eperm')) {
        return '连不上房主：本机不允许 App 联网（缺少 INTERNET 权限），不是地址问题，请装最新版狼邮杀';
      }
      return '连不上房主 $host:$port —— 检查是不是同一个 WiFi、房主屏幕上的地址填对没';
    }
  }

  void _gone() {
    if (_closing || _res == null) return;
    _res = null;
    for (final l in List.from(listeners)) {
      l({'t': 'gone', 'd': {}});
    }
  }

  void send(String line) {
    unawaited(_post(line.trimRight()));
  }

  Future<void> _post(String body) async {
    final c = _client;
    if (c == null) return;
    try {
      final bytes = utf8.encode(body);
      final req = await c.post(
          _host, _port, '/act?cid=${Uri.encodeComponent(cid)}');
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();
      await res.drain<void>();
    } catch (_) {
      // 单条消息丢了不致命：关键动作房主那边有"直接结算"兜底
    }
  }

  void close() {
    if (_closing) return;
    _closing = true;
    _res = null;
    final c = _client;
    _client = null;
    if (c == null) return;
    unawaited(() async {
      // 尽力而为地告诉房主"我走了"，好立刻腾出座位；发不出去也不影响别的
      try {
        final req =
            await c.post(_host, _port, '/bye?cid=${Uri.encodeComponent(cid)}');
        req.contentLength = 0;
        final res = await req.close();
        await res.drain<void>();
      } catch (_) {}
      c.close(force: true);
    }());
  }
}
