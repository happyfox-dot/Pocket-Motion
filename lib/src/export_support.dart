import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool_path.dart';

class ExportSkipped implements Exception {
  final String path;
  const ExportSkipped(this.path);
  @override
  String toString() => '已存在，保留原文件：${p.basename(path)}';
}

Future<void> ensureOutputsAvailable(Iterable<String> paths) async {
  for (final path in paths) {
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw ExportSkipped(path);
    }
  }
}

/// Resolve the nearest existing parent before creating anything at the target.
Future<void> validateExportLocation(String source, String destination) async {
  if (source.trim().isEmpty || destination.trim().isEmpty) {
    throw const FileSystemException('请先选择素材目录和导出位置');
  }
  final sourcePath = await Directory(source).resolveSymbolicLinks();
  final target = p.normalize(p.absolute(destination));
  var ancestor = Directory(target);
  while (!await ancestor.exists()) {
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) {
      throw const FileSystemException('导出位置不可用');
    }
    ancestor = parent;
  }
  final resolved = p.normalize(
    p.join(
      await ancestor.resolveSymbolicLinks(),
      p.relative(target, from: ancestor.path),
    ),
  );
  if (p.equals(sourcePath, resolved) || p.isWithin(sourcePath, resolved)) {
    throw const FileSystemException('请选择素材目录以外的导出位置，避免写入相机原件目录');
  }
}

/// Captures failures instead of treating an unfinished output as a success.
Future<ProcessResult> runMediaTool(
  String tool,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    ToolPath.find(tool),
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    final detail = result.stderr.toString();
    throw ProcessException(
      tool,
      arguments,
      detail.length > 1800 ? detail.substring(detail.length - 1800) : detail,
      result.exitCode,
    );
  }
  return result;
}

class VideoDetails {
  final double duration;
  final double coverTime;
  const VideoDetails(this.duration, this.coverTime);

  static Future<VideoDetails> probe(String path) async {
    final result = await runMediaTool('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=duration:format=duration',
      '-of',
      'json',
      path,
    ]);
    final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    final streams = data['streams'] as List? ?? [];
    if (streams.isEmpty) throw const FormatException('素材中没有可用的视频轨');
    final duration =
        double.tryParse('${streams.first['duration']}') ??
        double.tryParse('${data['format']?['duration']}');
    if (duration == null || !duration.isFinite || duration <= 0) {
      throw const FormatException('无法读取视频时长');
    }
    // Both the extracted still and its metadata must use the same timestamp.
    return VideoDetails(duration, duration >= 3 ? 1.5 : duration / 2);
  }
}
