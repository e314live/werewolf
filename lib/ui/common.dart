import 'package:flutter/material.dart';

import '../core/judge.dart';

const Color bgDark = Color(0xFF12101A);
const Color cardDark = Color(0xFF1D1A28);

Panel tile({required Color color, required IconData icon, required Widget child}) => Panel(
      color: color,
      icon: icon,
      child: child,
    );

class Panel extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Widget child;
  const Panel({super.key, required this.color, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

/// 夜晚遮罩：天黑请闭眼
class SleepOverlay extends StatelessWidget {
  const SleepOverlay({super.key, required this.text, this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌙', style: TextStyle(fontSize: 96)),
          const SizedBox(height: 24),
          Text(
            text,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 6),
          ),
          if (sub != null) ...[
            const SizedBox(height: 16),
            Text(sub!, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.white38, height: 1.8)),
          ],
        ],
      ),
    );
  }
}

/// 选人格子
class PickerGrid extends StatelessWidget {
  const PickerGrid({
    super.key,
    required this.seatCount,
    required this.target,
    required this.onPick,
    this.helpers = const [],
    this.dead = const [],
    this.enabled = true,
    this.label,
  });

  final int seatCount;
  final int target;
  final ValueChanged<int> onPick;
  final List<int> helpers;
  final List<int> dead;
  final bool enabled;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(label!, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: List.generate(seatCount, (i) {
            final isSelf = i == target;
            final isHelper = helpers.contains(i);
            final isDead = dead.contains(i);
            final c = isHelper
                ? const Color(0xFFD33F49)
                : isDead
                    ? Colors.white24
                    : i.isEven
                        ? const Color(0xFF38324A)
                        : const Color(0xFF2A2538);
            return InkWell(
              onTap: enabled && !isDead ? () => onPick(i) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 60,
                height: 66,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelf
                      ? Border.all(color: const Color(0xFFE8A33D), width: 2.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isDead ? Colors.white30 : Colors.white)),
                    Text(
                      isHelper ? '狼' : isDead ? '出局' : '',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// 一个角色的身份大卡
class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.role, required this.name, this.extra});
  final Role role;
  final String name;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final c = Color(roleColor[role]!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.30), c.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: c.withValues(alpha: 0.75), width: 1.6),
      ),
      child: Column(
        children: [
          Text(roleName[role]!, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: c)),
          const SizedBox(height: 10),
          Text(name, style: const TextStyle(fontSize: 17, color: Colors.white70)),
          const SizedBox(height: 14),
          Text(roleDesc[role]!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.7, color: Colors.white60)),
          if (extra != null) ...[
            const SizedBox(height: 16),
            Text(extra!, style: const TextStyle(fontSize: 15, color: Color(0xFFE8A33D))),
          ],
        ],
      ),
    );
  }
}

String winnerText(String w) =>
    w == 'wolf' ? '狼人胜利，天黑到底' : (w == 'good' ? '好人胜利，天亮了' : '未知结果');

Future<bool> confirm(BuildContext ctx, String title, String content) async {
  return await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      ) ??
      false;
}
