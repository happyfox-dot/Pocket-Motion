import 'dart:io';

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
  static const text = 'DJI · Osmo Pocket 4P';
  final bool enabled;
  final WatermarkPosition position;

  const WatermarkSettings({
    this.enabled = false,
    this.position = WatermarkPosition.bottomRight,
  });

  String get outputSuffix => enabled ? '_WM_${position.suffix}' : '';

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
    final font = await _findFont();
    await font.copy(p.join(staging.path, 'watermark-font.ttf'));
    await File(p.join(staging.path, 'watermark.txt'))
        .writeAsString(WatermarkSettings.text);
    final output = p.absolute(p.join(staging.path, 'watermarked.mp4'));
    final left =
        settings.position == WatermarkPosition.bottomLeft ||
        settings.position == WatermarkPosition.topLeft;
    final top =
        settings.position == WatermarkPosition.topLeft ||
        settings.position == WatermarkPosition.topRight;
    // Relative, fixed ASCII names keep drive letters, quotes and user paths out
    // of the filter expression. The source/output are separate process args.
    const margin = r'min(w\,h)/40';
    final filter =
        'scale=trunc(iw/2)*2:trunc(ih/2)*2,'
        'drawtext=fontfile=watermark-font.ttf:textfile=watermark.txt:'
        'expansion=none:fontsize=min(w\\,h)/28:fontcolor=white:'
        'borderw=1:bordercolor=black@0.4:shadowcolor=black@0.75:'
        'shadowx=1:shadowy=1:'
        'x=${left ? margin : 'w-tw-$margin'}:'
        'y=${top ? margin : 'h-th-$margin'}';
    onLog?.call('添加机型水印（${settings.position.label}），正在重新编码视频…');
    await runMediaTool('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      '-n',
      '-i',
      p.absolute(source),
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-vf',
      filter,
      '-c:v',
      'libx265',
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

  static Future<File> _findFont() async {
    final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final candidates = Platform.isWindows
        ? [
            p.join(windows, 'Fonts', 'arial.ttf'),
            p.join(windows, 'Fonts', 'segoeui.ttf'),
          ]
        : [
            '/System/Library/Fonts/Supplemental/Arial.ttf',
            '/Library/Fonts/Arial.ttf',
            '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
          ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    throw const FileSystemException('找不到水印字体（Arial / Segoe UI），请安装字体后重试');
  }
}
