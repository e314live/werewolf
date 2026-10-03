import 'package:flutter/material.dart';

import 'ui/host.dart';
import 'ui/player.dart';

void main() => runApp(const WerewolfApp());

class WerewolfApp extends StatelessWidget {
  const WerewolfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '狼邮杀',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A1B3D),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12101A),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _go(BuildContext ctx, Widget next) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => next));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 138,
                    height: 138,
                    fit: BoxFit.cover,
                    // 万一分发时资源缺失，退回 emoji，不至于开屏就报错
                    errorBuilder: (_, __, ___) =>
                        const Text('🐺', style: TextStyle(fontSize: 88)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '狼邮杀',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 5),
                ),
                const SizedBox(height: 6),
                const Text(
                  '同校园网直连 · 零后端 · 身份只在你自己手机上',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white54),
                ),
                const SizedBox(height: 54),
                _BigBtn(
                  icon: Icons.hub,
                  color: const Color(0xFF8E5BD6),
                  title: '我是房主',
                  sub: '开房间、当法官、发牌',
                  onTap: () => _go(context, const HostPage()),
                ),
                const SizedBox(height: 18),
                _BigBtn(
                  icon: Icons.mobile_friendly_outlined,
                  color: const Color(0xFF3F8EE0),
                  title: '我是玩家',
                  sub: '装 App 填地址，或用浏览器直接打开',
                  onTap: () => _go(context, const PlayerPage()),
                ),
                const SizedBox(height: 40),
                const Text(
                  '无需蓝牙配对 · 无需开热点 · 无需联网服务器\n'
                  '宿舍里连同一个校园网就能开局\n'
                  '苹果 / 鸿蒙的室友不用装东西，用浏览器打开房主的 http 地址即可',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, height: 1.7, color: Colors.white38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BigBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;

  const _BigBtn({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: color.withValues(alpha: 0.95))),
                  const SizedBox(height: 3),
                  Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
