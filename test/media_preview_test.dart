import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dji_live_gallery/src/media_preview.dart';
import 'package:dji_live_gallery/src/models.dart';

void main() {
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync('pocket-preview-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, String path, MediaKind kind) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MediaPreviewDialog(
                  asset: MediaAsset(
                    path: path,
                    filename: '预览样本',
                    kind: kind,
                    shotAt: null,
                    sizeBytes: 0,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    // File availability is checked asynchronously, outside Flutter's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('disconnected source gives a recoverable error and can close', (
    tester,
  ) async {
    await open(tester, '${directory.path}/missing.mp4', MediaKind.livePhoto);
    expect(find.text('无法预览'), findsOneWidget);
    expect(find.textContaining('请检查相机连接或重新扫描'), findsOneWidget);
    expect(find.byTooltip('播放'), findsNothing);
    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RAW photo explains the JPEG alternative without starting a player',
    (tester) async {
      final file = File('${directory.path}/sample.DNG')..writeAsBytesSync([0]);
      await open(tester, file.path, MediaKind.photo);
      expect(find.textContaining('暂不支持 DNG 原始照片预览'), findsOneWidget);
      expect(find.textContaining('JPEG'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing during file lookup does not update a disposed dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaPreviewDialog(
          asset: MediaAsset(
            path: '${directory.path}/missing.mp4',
            filename: '快速关闭',
            kind: MediaKind.video,
            shotAt: null,
            sizeBytes: 0,
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
