import 'dart:io';

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
  }) async {
    await Directory(outDir).create(recursive: true);
    final destination = p.join(
      outDir,
      '${p.basenameWithoutExtension(asset.filename)}${watermark.outputSuffix}.livp',
    );
    await ensureOutputsAvailable([destination]);
    final staging = await Directory(outDir).createTemp('.pocket-livp-');
    try {
      final (photo, video) = await LivePhotoExporter(onLog: onLog)
          .export(asset: asset, outDir: staging.path, watermark: watermark);
      final package = File(p.join(staging.path, 'result.livp'));
      await LivpArchive.write(
        photo: File(photo),
        video: File(video),
        output: package,
        shotAt: asset.shotAt,
      );
      await ensureOutputsAvailable([destination]);
      await package.rename(destination);
      onLog?.call('已生成 ${p.basename(destination)}；请先验证网盘下载效果');
      return destination;
    } finally {
      // Only the private directory created above is removed, never the source.
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
