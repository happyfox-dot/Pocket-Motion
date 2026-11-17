import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'export_support.dart';

enum WatermarkPosition {
  bottomRight('右下角', 'BR'),
  bottomLeft('左下角', 'BL'),
  topRight('右上角', 'TR'),
  topLeft('左上角', 'TL');

  final String label;
  final String suffix;
  const WatermarkPosition(this.label, this.suffix);
}

class WatermarkSettings {
  static const text = 'DJI 图形标志 · OSMO POCKET 4P';
  static const assetPath = 'assets/watermarks/pocket4p_device.png';
  final bool enabled;
  final WatermarkPosition position;

  const WatermarkSettings({
    this.enabled = false,
    this.position = WatermarkPosition.bottomRight,
  });

  // Keep exports from the former plain-text renderer alongside this version.
  String get outputSuffix => enabled ? '_WM_DJI1_${position.suffix}' : '';

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'position': position.name,
  };

  factory WatermarkSettings.fromJson(Object? data) {
    if (data is! Map) return const WatermarkSettings();
    return WatermarkSettings(
      enabled: data['enabled'] == true,
      position: WatermarkPosition.values.firstWhere(
        (value) => value.name == data['position'],
        orElse: () => WatermarkPosition.bottomRight,
      ),
    );
  }
}

/// Render once, then take the still from this movie so both carry the same mark.
/// All temporary files belong to the exporter's private staging directory.
class WatermarkRenderer {
  static Future<String> prepareVideo({
    required String source,
    required Directory staging,
    required WatermarkSettings settings,
    void Function(String)? onLog,
  }) async {
    if (!settings.enabled) return source;
    final artwork = await _findArtwork();
    await artwork.copy(p.join(staging.path, 'watermark.png'));
    final size = await runMediaTool('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height',
      '-of',
      'json',
      p.absolute(source),
    ]);
    final streams =
        (jsonDecode(size.stdout.toString()) as Map)['streams'] as List;
    if (streams.isEmpty) throw const FormatException('素材中没有可用的视频轨');
    final width = streams.first['width'] as int? ?? 0;
    final height = streams.first['height'] as int? ?? 0;
    if (min(width, height) < 4) throw const FormatException('素材尺寸不可用');
    // The short edge is invariant under the 90-degree display rotation used
    // by phone/camera videos. ffmpeg still applies that rotation automatically.
    final artworkWidth = min(width, height) ~/ 4 * 2;
    final output = p.absolute(p.join(staging.path, 'watermarked.mp4'));
    final left =
        settings.position == WatermarkPosition.bottomLeft ||
        settings.position == WatermarkPosition.topLeft;
    final top =
        settings.position == WatermarkPosition.topLeft ||
        settings.position == WatermarkPosition.topRight;
    // Use the original Mimo PNG, including its transparent padding. Never
    // redraw the wordmark with a local font or add outlines/shadows. The canvas
    // width is half the video's short edge; this placement is our preset, not
    // a measured claim about every Mimo export mode. See assets/SOURCES.md.
    final filter =
        '[0:v:0]scale=trunc(iw/2)*2:trunc(ih/2)*2[video];'
        '[1:v:0]scale=w=$artworkWidth:h=-1:flags=lanczos[mark];'
        '[video][mark]overlay=x=${left ? '0' : 'main_w-overlay_w'}:'
        'y=${top ? '0' : 'main_h-overlay_h'}:'
        'eof_action=repeat:format=auto,format=yuv420p[out]';
    onLog?.call('添加 Pocket 4P 机型图形水印（${settings.position.label}），正在重新编码视频…');
    await runMediaTool('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      '-n',
      '-i',
      p.absolute(source),
      '-i',
      'watermark.png',
      '-filter_complex',
      filter,
      '-map',
      '[out]',
      '-map',
      '0:a?',
      '-c:v',
      'libx265',
      '-fps_mode',
      'passthrough',
      '-preset',
      'fast',
      '-crf',
      '18',
      '-x265-params',
      'log-level=error',
      '-tag:v',
      'hvc1',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      output,
    ], workingDirectory: p.absolute(staging.path));
    await VideoDetails.probe(output);
    return output;
  }

  static Future<File> _findArtwork() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      // Flutter Windows/Linux release bundles, independent of working folder.
      p.join(exeDir, 'data', 'flutter_assets', WatermarkSettings.assetPath),
      if (Platform.isMacOS)
        p.join(
          p.dirname(exeDir),
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
          WatermarkSettings.assetPath,
        ),
      // Standalone Dart smoke tools and development builds.
      p.absolute(WatermarkSettings.assetPath),
      if (Platform.script.scheme == 'file')
        p.join(
          p.dirname(p.dirname(Platform.script.toFilePath())),
          WatermarkSettings.assetPath,
        ),
    ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    throw const FileSystemException('缺少 Pocket 4P 水印图片，请使用完整程序文件夹启动');
  }
}
