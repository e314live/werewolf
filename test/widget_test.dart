// UI 冒烟测试：验证首页/建房页/加入页能被构建出来（不连网、不发牌）
// 运行：flutter test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:werewolf/main.dart';
import 'package:werewolf/ui/host.dart';
import 'package:werewolf/ui/player.dart';

/// ListView 是懒加载的，默认 800x600 视口会把下半屏的元素裁掉，
/// 断言就会找不到 → 这里先把视口拉高。
void bigViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('首页两个入口都在', (WidgetTester tester) async {
    bigViewport(tester);
    await tester.pumpWidget(const WerewolfApp());
    expect(find.text('宿舍狼人杀'), findsOneWidget);
    expect(find.text('我是房主'), findsOneWidget);
    expect(find.text('我是玩家'), findsOneWidget);
  });

  testWidgets('房主建房页：人数 / 胜负条件 / 端口 都在', (WidgetTester tester) async {
    bigViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: HostPage()));
    await tester.pumpAndSettle();

    expect(find.text('开房间 · 当法官'), findsOneWidget);
    expect(find.text('9 人'), findsOneWidget);   // 默认人数
    expect(find.text('屠边'), findsOneWidget);    // 胜负条件
    expect(find.text('屠城'), findsOneWidget);
    expect(find.text('监听端口'), findsOneWidget); // 端口自愈入口
    expect(find.text('开启房间'), findsOneWidget);
  });

  testWidgets('房主页能加减人数', (WidgetTester tester) async {
    bigViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: HostPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('10 人'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('9 人'), findsOneWidget);
  });

  testWidgets('玩家加入页能渲染', (WidgetTester tester) async {
    bigViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    await tester.pumpAndSettle();
    expect(find.text('你的名字'), findsOneWidget);
    expect(find.text('进入房间'), findsOneWidget);
  });
}
