// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dji_live_gallery/main.dart';

void main() {
  testWidgets('empty library offers USB import and keeps export disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DjiLiveApp());
    await tester.pump();
    expect(find.text('查找 USB 相机 / 存储卡'), findsOneWidget);
    expect(find.text('选择本地素材文件夹'), findsOneWidget);
    final export = find.widgetWithText(FilledButton, '导出百度网盘实况 (.livp)');
    expect(export, findsOneWidget);
    expect(tester.widget<FilledButton>(export).onPressed, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, '视频'));
    await tester.pumpAndSettle();
    expect(find.text('导出视频'), findsOneWidget);
    expect(find.text('导出百度网盘实况 (.livp)'), findsNothing);
    expect(find.text('导出为 Apple 实况照片'), findsNothing);
    expect(find.text('添加机型水印'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '实况'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Shorter windows must still reach every action and the log panel.
    tester.view.physicalSize = const Size(960, 640);
    await tester.pump();
    await tester.tap(find.byTooltip('重新扫描'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final log = find.textContaining('扫描失败：');
    await tester.ensureVisible(log);
    await tester.pumpAndSettle();
    expect(log.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
