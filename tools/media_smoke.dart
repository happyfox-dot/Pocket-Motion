import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:dji_live_gallery/src/baidu_live_exporter.dart';
import 'package:dji_live_gallery/src/export_support.dart';
import 'package:dji_live_gallery/src/models.dart';
import 'package:dji_live_gallery/src/motion_photo_exporter.dart';

// Generates clearly synthetic media and exercises the real encoders. This
// checks file integrity only; it is not a substitute for phone/cloud validation.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Provide a temporary output folder');
  }
  final root = await Directory(args.single).create(recursive: true);
  for (final duration in [3.0, 0.7]) {
    final source = p.join(root.path, 'synthetic_${duration}s.mp4');
    await runMediaTool('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=320x240:rate=30:duration=$duration',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000:duration=$duration',
      '-c:v',
      'libx265',
      '-x265-params',
      'log-level=error',
      '-tag:v',
      'hvc1',
      '-c:a',
      'aac',
      '-shortest',
      source,
    ]);
    final asset = MediaAsset(
      path: source,
      filename: p.basename(source),
      kind: MediaKind.livePhoto,
      shotAt: DateTime(2026, 11, 17, 12),
      sizeBytes: await File(source).length(),
    );
    final output = p.join(root.path, 'output');
    final livp = await BaiduLiveExporter(onLog: stdout.writeln)
        .export(asset: asset, outDir: output);
    final motion = await MotionPhotoExporter(onLog: stdout.writeln)
        .export(asset: asset, outDir: output);
    stdout.writeln('ARTIFACT: $livp');
    stdout.writeln('ARTIFACT: $motion');
    try {
      await BaiduLiveExporter().export(asset: asset, outDir: output);
      throw StateError('Existing archive was not skipped');
    } on ExportSkipped {
      /* expected */
    }
  }
  final invalid = await File(p.join(root.path, 'broken.mp4'))
      .writeAsString('broken');
  try {
    await BaiduLiveExporter().export(
      asset: MediaAsset(
        path: invalid.path,
        filename: 'broken.mp4',
        kind: MediaKind.livePhoto,
        shotAt: null,
        sizeBytes: 6,
      ),
      outDir: p.join(root.path, 'output'),
    );
    throw StateError('Corrupt input was accepted');
  } on ProcessException {
    /* expected */
  }
  if (await File(p.join(root.path, 'output', 'broken.livp')).exists()) {
    throw StateError('A corrupt output was published');
  }
  stdout.writeln(
    'Media smoke checks passed. Phone and Baidu verification still required.',
  );
}
