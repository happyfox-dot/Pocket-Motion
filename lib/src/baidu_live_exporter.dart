import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'export_support.dart';
import 'live_photo_exporter.dart';
import 'livp_archive.dart';
import 'models.dart';
import 'watermark.dart';

class BaiduLiveExporter {
  final void Function(String)? onLog;
  BaiduLiveExporter({this.onLog});

  Future<String> export({
    required MediaAsset asset,
    required String outDir,
    WatermarkSettings watermark = const WatermarkSettings(),
    ExportOptions options = const ExportOptions(),
  }) async {
    await options.cancelToken?.checkpoint();
    await Directory(outDir).create(recursive: true);
    final desired = p.join(
      outDir,
      '${p.basenameWithoutExtension(asset.filename)}${watermark.outputSuffix}.livp',
    );
    final destination = (await resolveExportTargets(
      [desired],
      options.conflictPolicy,
    )).single;

    final staging = await Directory(outDir).createTemp('.pocket-livp-');
    try {
      final (photo, video) = await LivePhotoExporter(onLog: onLog).export(
        asset: asset,
        outDir: staging.path,
        watermark: watermark,
        options: ExportOptions(
          conflictPolicy: ExportConflictPolicy.skip,
          useHardwareAccel: options.useHardwareAccel,
          cancelToken: options.cancelToken,
        ),
      );
      await options.cancelToken?.checkpoint();
      final packagePath = p.join(staging.path, 'result.livp');
      final shotAt = asset.shotAt;

      // Offload byte-level CRC32 calculation and uncompressed ZIP assembly to a
      // background Isolate so the UI stays 60fps responsive.
      await Isolate.run(() async {
        await LivpArchive.write(
          photo: File(photo),
          video: File(video),
          output: File(packagePath),
          shotAt: shotAt,
        );
      });

      await options.cancelToken?.checkpoint();
      await publishStagedFile(packagePath, destination, options.conflictPolicy);
      onLog?.call('已生成 ${p.basename(destination)}');
      return destination;
    } finally {
      // Only the private directory created above is removed, never the source.
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
