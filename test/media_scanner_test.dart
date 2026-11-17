import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dji_live_gallery/src/camera_discovery.dart';
import 'package:dji_live_gallery/src/media_scanner.dart';
import 'package:dji_live_gallery/src/models.dart';
import 'package:dji_live_gallery/src/export_support.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('pocket-scan-test-'),
  );
  tearDown(() async => root.delete(recursive: true));

  Future<File> file(String relative, String content) async {
    final result = File(p.join(root.path, relative));
    await result.parent.create(recursive: true);
    return result.writeAsString(content);
  }

  test(
    'disk root scans multiple DJI folders and uses markers, not duration',
    () async {
      await file(
        'DCIM/DJI_001/DJI_20261117120000_0001_D.MP4',
        '\x00TPLG_VIDEO_4K\x00TPLG_VIDEO_LIVEPHOTO_4K_2997\x00',
      );
      await file(
        'DCIM/DJI_002/DJI_20261117120100_0002_D.MP4',
        'short ordinary video',
      );
      await file('DCIM/DJI_002/DJI_20261117120200_0003_D.JPG', 'photo');
      await file('DCIM/DJI_001/proxy.LRF', 'TPLG_VIDEO_LIVEPHOTO_4K');
      final items = await MediaScanner().scan(root.path);
      expect(items.length, 3);
      final live = items.singleWhere((a) => a.kind == MediaKind.livePhoto);
      expect(live.template, 'TPLG_VIDEO_LIVEPHOTO_4K_2997');
      expect(live.shotAt, DateTime(2026, 11, 17, 12));
      expect(items.where((a) => a.kind == MediaKind.video).length, 1);
      expect(await CameraDiscovery().find(roots: [root.path]), [
        p.join(root.path, 'DCIM'),
      ]);
    },
  );

  test(
    'marker-like text is not sufficient and invalid dates stay unknown',
    () async {
      await file('DJI_20260231120000_0001_D.mp4', 'TPLG_VIDEO_LIVEPHOTO_FAKE');
      await file('ordinary.mp4', 'TPLG_VIDEO_LIVEPHOTOGRAPHY');
      final items = await MediaScanner().scan(root.path);
      expect(items.every((a) => a.shotAt == null), isTrue);
      expect(
        items.singleWhere((a) => a.filename == 'ordinary.mp4').kind,
        MediaKind.video,
      );
    },
  );

  test(
    'local copies keep marker classification without a DJI folder layout',
    () async {
      final original = await file(
        'camera/DJI_20261118120000_0001_D.MP4',
        '\x00TPLG_VIDEO_LIVEPHOTO_4K_2997\x00',
      );
      final copiedDir = await Directory(p.join(root.path, '电脑素材', '旅行'))
          .create(recursive: true);
      await original.copy(p.join(copiedDir.path, '重命名的实况.mp4'));
      await file('电脑素材/旅行/普通视频.MP4', '\x00TPLG_VIDEO_4K_2997\x00');
      await file('电脑素材/旅行/没有标记.mp4', 'ordinary short clip');
      final items = await MediaScanner().scan(p.join(root.path, '电脑素材'));
      expect(items, hasLength(3));
      expect(
        items.singleWhere((a) => a.filename == '重命名的实况.mp4').kind,
        MediaKind.livePhoto,
      );
      expect(items.where((a) => a.kind == MediaKind.video), hasLength(2));
      expect(
        await original.readAsString(),
        '\x00TPLG_VIDEO_LIVEPHOTO_4K_2997\x00',
      );
    },
  );

  test('empty or disconnected source reports an actionable error', () async {
    await expectLater(
      MediaScanner().scan(''),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      MediaScanner().scan(p.join(root.path, 'missing')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'rejects writing into the source before creating output folders',
    () async {
      final output = p.join(root.path, 'new', 'output');
      await expectLater(
        validateExportLocation(root.path, output),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(output).exists(), isFalse);
    },
  );

  test('existing outputs are preserved', () async {
    final existing = await file('saved.livp', 'original');
    await expectLater(
      ensureOutputsAvailable([existing.path]),
      throwsA(isA<ExportSkipped>()),
    );
    expect(await existing.readAsString(), 'original');
  });
}
