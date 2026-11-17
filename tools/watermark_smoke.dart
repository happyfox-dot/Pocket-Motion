import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:dji_live_gallery/src/baidu_live_exporter.dart';
import 'package:dji_live_gallery/src/export_support.dart';
import 'package:dji_live_gallery/src/models.dart';
import 'package:dji_live_gallery/src/motion_photo_exporter.dart';
import 'package:dji_live_gallery/src/watermark.dart';

// Deliberately synthetic, flat backgrounds make text position testable in pixels.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Provide a new output directory');
  final root = Directory(args.single);
  if (await root.exists()) throw StateError('Use a new output directory');
  final sources = await Directory(p.join(root.path, "素材 空格'测试"))
      .create(recursive: true);
  final output = p.join(root.path, 'output');
  for (final position in WatermarkPosition.values) {
    final portrait =
        position == WatermarkPosition.topLeft ||
        position == WatermarkPosition.topRight;
    final sound =
        position == WatermarkPosition.bottomRight ||
        position == WatermarkPosition.topRight;
    final duration = position == WatermarkPosition.bottomRight ? 3.0 : 0.7;
    final name = 'synthetic_${position.suffix}';
    final source = p.join(sources.path, '$name.mp4');
    await runMediaTool('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      '-n',
      '-f',
      'lavfi',
      '-i',
      'color=c=0x254B52:s=${portrait ? '720x1280' : '1280x720'}:r=30:d=$duration',
      if (sound) ...[
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=48000:duration=$duration',
        '-c:a',
        'aac',
      ],
      '-c:v',
      'libx265',
      '-x265-params',
      'log-level=error',
      '-tag:v',
      'hvc1',
      '-shortest',
      source,
    ]);
    final original = await File(source).readAsBytes();
    final asset = MediaAsset(
      path: source,
      filename: p.basename(source),
      kind: MediaKind.livePhoto,
      shotAt: DateTime(2026, 11, 17, 12),
      sizeBytes: original.length,
    );
    final settings = WatermarkSettings(enabled: true, position: position);
    final livp = await BaiduLiveExporter(onLog: stdout.writeln)
        .export(asset: asset, outDir: output, watermark: settings);
    stdout.writeln('ARTIFACT: $livp');
    if (position == WatermarkPosition.bottomRight ||
        position == WatermarkPosition.topLeft) {
      final motion = await MotionPhotoExporter(onLog: stdout.writeln)
          .export(asset: asset, outDir: output, watermark: settings);
      stdout.writeln('ARTIFACT: $motion');
    }
    final published = await File(livp).readAsBytes();
    try {
      await BaiduLiveExporter().export(
        asset: asset,
        outDir: output,
        watermark: settings,
      );
      throw StateError('Existing output was not skipped');
    } on ExportSkipped {
      // Expected: no work should touch the completed file.
    }
    final preserved = await File(livp).readAsBytes();
    if (!_equal(published, preserved)) {
      throw StateError('Output was overwritten');
    }
    if (!_equal(original, await File(source).readAsBytes())) {
      throw StateError('Source was changed');
    }
    if (position == WatermarkPosition.bottomRight) {
      final plain = await BaiduLiveExporter().export(
        asset: asset,
        outDir: output,
      );
      if (plain == livp) {
        throw StateError('Watermark collides with plain output');
      }
      stdout.writeln('ARTIFACT (no watermark): $plain');
    }
  }
  stdout.writeln(
    'Watermark exports passed. Run verify_watermark.py on this folder.',
  );
}

bool _equal(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
