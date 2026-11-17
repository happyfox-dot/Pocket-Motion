import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'media_metadata.dart';
import 'models.dart';
import 'export_support.dart';
import 'watermark.dart';

/// Google Motion Photo 导出器。
///
/// 输出**单个 .jpg 文件**：结构 = [JPEG(含标准 EXIF APP1 + Google XMP APP1)] + [MP4字节]
/// 纯 Dart 直接从源 MP4 提取设备型号与拍摄时间并写入 EXIF，不依赖外部 exiftool 进程。
class MotionPhotoExporter {
  final void Function(String log)? onLog;
  MotionPhotoExporter({this.onLog});
  void _log(String s) {
    onLog?.call(s);
  }

  Future<String> export({
    required MediaAsset asset,
    required String outDir,
    WatermarkSettings watermark = const WatermarkSettings(),
    ExportOptions options = const ExportOptions(),
  }) async {
    await options.cancelToken?.checkpoint();
    await Directory(outDir).create(recursive: true);
    final base =
        '${p.basenameWithoutExtension(asset.filename)}${watermark.outputSuffix}_MP';
    final desiredPath = p.join(outDir, '$base.jpg');
    final outPath = (await resolveExportTargets(
      [desiredPath],
      options.conflictPolicy,
    )).single;

    final staging = await Directory(outDir).createTemp('.pocket-motion-');
    final tmpJpg = p.join(staging.path, 'still.jpg');
    final pending = p.join(staging.path, 'motion.jpg');
    try {
      final details = await VideoDetails.probe(
        asset.path,
        cancelToken: options.cancelToken,
      );
      final mp4Info =
          details.device ?? await MediaMetadata.extractFromMp4(asset.path);
      final shotAt = asset.shotAt ?? mp4Info.creationTime;
      final mediaPath = await WatermarkRenderer.prepareVideo(
        source: asset.path,
        staging: staging,
        settings: watermark,
        knownWidth: details.width,
        knownHeight: details.height,
        options: options,
        onLog: onLog,
      );
      final deviceLabel =
          mp4Info.model.toUpperCase().startsWith(mp4Info.make.toUpperCase())
          ? mp4Info.model
          : '${mp4Info.make} ${mp4Info.model}';

      // 1) 抽中间帧为纯 JPEG
      _log('抽帧: ${p.basenameWithoutExtension(outPath)} ($deviceLabel)');
      await runMediaTool('ffmpeg', [
        '-nostdin',
        '-y',
        '-ss',
        '${details.coverTime}',
        '-i',
        mediaPath,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        '-update',
        '1',
        tmpJpg,
      ], cancelToken: options.cancelToken);

      await options.cancelToken?.checkpoint();
      try {
        // 2) 读静态 JPEG，以及原片或已加水印的 MP4。
        var jpg = await File(tmpJpg).readAsBytes();
        final mp4Length = await File(mediaPath).length();
        final dims = MediaMetadata.extractJpegDimensions(jpg);

        // 3) 纯 Dart 构造 EXIF APP1 段与 Google Motion Photo XMP APP1 段并注入 SOI 之后
        final exifApp1 = MediaMetadata.buildExifApp1Segment(
          make: mp4Info.make,
          model: mp4Info.model,
          software: 'Pocket Motion',
          shotAt: shotAt,
          imageWidth: dims?.$1,
          imageHeight: dims?.$2,
        );
        final xmpApp1 = _buildXmpSegment(
          mp4Length: mp4Length,
          presentationUs: (details.coverTime * 1000000).round(),
        );
        jpg = MediaMetadata.injectIntoJpeg(jpg, [exifApp1, xmpApp1]);

        // 4) 拼接：JPEG + MP4
        final out = File(pending).openWrite();
        try {
          out.add(jpg);
          await out.addStream(File(mediaPath).openRead());
          await out.flush();
        } finally {
          await out.close();
        }
      } finally {
        try {
          if (File(tmpJpg).existsSync()) {
            File(tmpJpg).deleteSync();
          }
        } catch (_) {}
      }

      // 5) 文件系统时间归位
      if (shotAt != null) {
        try {
          await File(pending).setLastModified(shotAt);
        } catch (_) {}
      }

      await options.cancelToken?.checkpoint();
      await publishStagedFile(pending, outPath, options.conflictPolicy);
      _log('完成: ${p.basename(outPath)} (Motion Photo)');
      return outPath;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Uint8List _buildXmpSegment({
    required int mp4Length,
    required int presentationUs,
  }) {
    final xml =
        '''<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Pocket Motion">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
    xmlns:Container="http://ns.google.com/photos/1.0/container/"
    xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
    GCamera:MotionPhoto="1"
    GCamera:MotionPhotoVersion="1"
    GCamera:MotionPhotoPresentationTimestampUs="$presentationUs">
   <Container:Directory>
    <rdf:Seq>
     <rdf:li rdf:parseType="Resource">
      <Container:Item
        Item:Mime="image/jpeg"
        Item:Semantic="Primary"
        Item:Length="0"
        Item:Padding="0"/>
     </rdf:li>
     <rdf:li rdf:parseType="Resource">
      <Container:Item
        Item:Mime="video/mp4"
        Item:Semantic="MotionPhoto"
        Item:Length="$mp4Length"/>
     </rdf:li>
    </rdf:Seq>
   </Container:Directory>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';

    final prefix = 'http://ns.adobe.com/xap/1.0/\x00';
    final content = Uint8List.fromList([...prefix.codeUnits, ...xml.codeUnits]);
    final segLen = content.length + 2;
    final b = BytesBuilder()
      ..add([0xFF, 0xE1])
      ..add([(segLen >> 8) & 0xFF, segLen & 0xFF])
      ..add(content);
    return b.toBytes();
  }
}
