import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dji_live_gallery/src/export_controls.dart';
import 'package:dji_live_gallery/src/export_support.dart';

void main() {
  test('conflict policy skip, overwrite, and paired rename work safely', () async {
    final root = await Directory.systemTemp.createTemp('pocket-policy-test-');
    addTearDown(() async => root.delete(recursive: true));

    final heic = p.join(root.path, 'DJI_0001I.HEIC');
    final mov = p.join(root.path, 'DJI_0001I.MOV');
    await File(heic).writeAsString('old-heic');
    await File(mov).writeAsString('old-mov');

    // 1. skip throws ExportSkipped
    await expectLater(
      resolveExportTargets([heic, mov], ExportConflictPolicy.skip),
      throwsA(isA<ExportSkipped>()),
    );

    // 2. rename keeps paired suffixes synchronized (_1)
    final renamed = await resolveExportTargets(
      [heic, mov],
      ExportConflictPolicy.rename,
    );
    expect(p.basename(renamed[0]), 'DJI_0001I_1.HEIC');
    expect(p.basename(renamed[1]), 'DJI_0001I_1.MOV');

    // 3. overwrite safely replaces existing file from staged file
    final staged = p.join(root.path, 'staged.HEIC');
    await File(staged).writeAsString('new-heic');
    await publishStagedFile(staged, heic, ExportConflictPolicy.overwrite);
    expect(await File(heic).readAsString(), 'new-heic');
    expect(await File(staged).exists(), isFalse);
  });

  test('ExportCancelToken supports pause, resume, and cancel checkpoints', () async {
    final token = ExportCancelToken();
    token.pause();
    expect(token.isPaused, isTrue);

    var passedCheckpoint = false;
    final waiter = token.checkpoint().then((_) => passedCheckpoint = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(passedCheckpoint, isFalse);

    token.resume();
    await waiter;
    expect(passedCheckpoint, isTrue);

    token.cancel();
    expect(token.isCancelled, isTrue);
    await expectLater(token.checkpoint(), throwsA(isA<ExportCancelled>()));
  });

  testWidgets('ExportSettingsPanel and ActiveExportControlCard update state', (
    tester,
  ) async {
    var settings = const ExportControlSettings();
    var pauseToggled = false;
    var cancelPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  ExportSettingsPanel(
                    settings: settings,
                    hardwareLabel: 'AMD AMF',
                    onChanged: (next) => setState(() => settings = next),
                  ),
                  ActiveExportControlCard(
                    doneCount: 3,
                    totalCount: 10,
                    successCount: 3,
                    skippedCount: 0,
                    failCount: 0,
                    workerCount: 2,
                    paused: false,
                    cancelling: false,
                    activeNames: const ['DJI_0004.MP4'],
                    elapsed: const Duration(seconds: 6),
                    onTogglePause: () => pauseToggled = true,
                    onCancel: () => cancelPressed = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('AMD AMF'), findsOneWidget);
    await tester.tap(find.text('导完打开目录'));
    await tester.pumpAndSettle();
    expect(settings.openFolderWhenDone, isTrue);

    await tester.tap(find.text('暂停队列'));
    await tester.pump();
    expect(pauseToggled, isTrue);

    await tester.tap(find.text('取消导出'));
    await tester.pump();
    expect(cancelPressed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
