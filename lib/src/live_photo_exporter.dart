import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'export_support.dart';
import 'media_metadata.dart';
import 'models.dart';
import 'watermark.dart';

/// Builds matching HEIC + MOV resources. Only publishes complete outputs.
class LivePhotoExporter {
  final void Function(String)? onLog;
  LivePhotoExporter({this.onLog});

  Future<(String, String)> export({
    required MediaAsset asset,
    required String outDir,
    WatermarkSettings watermark = const WatermarkSettings(),
    ExportOptions options = const ExportOptions(),
  }) async {
    await options.cancelToken?.checkpoint();
    await Directory(outDir).create(recursive: true);
    final base =
        '${p.basenameWithoutExtension(asset.filename)}${watermark.outputSuffix}I';
    final desiredHeic = p.join(outDir, '$base.HEIC');
    final desiredMov = p.join(outDir, '$base.MOV');
    final resolved = await resolveExportTargets(
      [desiredHeic, desiredMov],
      options.conflictPolicy,
    );
    final outHeic = resolved[0];
    final outMov = resolved[1];

    final staging = await Directory(outDir).createTemp('.pocket-apple-');
    var publishedPhoto = false;
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
      final uuid = _newUuid();
      final still = p.join(staging.path, 'frame.mp4');
      final photo = p.join(staging.path, 'photo.HEIC');
      final remux = p.join(staging.path, 'remux.mov');
      final video = p.join(staging.path, 'paired.MOV');
      onLog?.call(
        '处理 ${asset.filename}，封面 ${details.coverTime.toStringAsFixed(3)} 秒',
      );

      // Extract cover frame and remux container concurrently when both read the
      // same prepared mediaPath — halves subprocess wall-clock wait per clip!
      await Future.wait([
        runMediaTool('ffmpeg', [
          '-nostdin',
          '-v',
          'error',
          '-y',
          '-ss',
          '${details.coverTime}',
          '-i',
          mediaPath,
          '-map',
          '0:v:0',
          '-an',
          '-sn',
          '-dn',
          '-frames:v',
          '1',
          '-vf',
          'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
          '-c:v',
          'libx265',
          '-profile:v',
          'main',
          '-preset',
          'fast',
          '-crf',
          '16',
          '-x265-params',
          'log-level=error:bframes=0:ref=1',
          '-tag:v',
          'hvc1',
          still,
        ], cancelToken: options.cancelToken),
        runMediaTool('ffmpeg', [
          '-nostdin',
          '-v',
          'error',
          '-y',
          '-i',
          mediaPath,
          '-map',
          '0:v:0',
          '-map',
          '0:a?',
          '-c',
          'copy',
          '-f',
          'mov',
          remux,
        ], cancelToken: options.cancelToken),
      ]);

      await options.cancelToken?.checkpoint();

      // Run HEIC construction and streaming MOV metadata injection in a worker
      // Isolate so UI rendering never stalls during large batch exports.
      final make = mp4Info.make;
      final model = mp4Info.model;
      final coverSec = details.coverTime;
      await Isolate.run(() async {
        await MediaMetadata.buildHeicFromHevcMp4(
          hevcMp4Path: still,
          outHeicPath: photo,
          make: make,
          model: model,
          uuid: uuid,
          shotAt: shotAt,
        );
        await MediaMetadata.writeMovLivePhotoMetadata(
          srcMp4Path: remux,
          outMovPath: video,
          uuid: uuid,
          make: make,
          model: model,
          shotAt: shotAt,
          coverTimeSeconds: coverSec,
        );
      });

      await options.cancelToken?.checkpoint();
      // Fast pure-Dart structural confirmation (falls back to ffprobe if needed).
      await VideoDetails.probe(video, cancelToken: options.cancelToken);
      if (shotAt != null) {
        await File(photo).setLastModified(shotAt);
        await File(video).setLastModified(shotAt);
      }
      await publishStagedFile(photo, outHeic, options.conflictPolicy);
      publishedPhoto = true;
      await publishStagedFile(video, outMov, options.conflictPolicy);
      onLog?.call('完成：${p.basename(outHeic)} + ${p.basename(outMov)}');
      return (outHeic, outMov);
    } catch (_) {
      if (publishedPhoto &&
          options.conflictPolicy != ExportConflictPolicy.overwrite &&
          await File(outHeic).exists()) {
        await File(outHeic).delete();
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
