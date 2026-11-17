import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'media_metadata.dart';
import 'tool_path.dart';

class ExportSkipped implements Exception {
  final String path;
  const ExportSkipped(this.path);
  @override
  String toString() => '已存在，保留原文件：${p.basename(path)}';
}

class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => '导出已取消';
}

enum ExportConflictPolicy {
  skip('跳过已有'),
  overwrite('覆盖更新'),
  rename('自动重命名');

  final String label;
  const ExportConflictPolicy(this.label);
}

class ExportCancelToken {
  bool _cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeGate;
  final Set<Process> _activeProcesses = {};

  bool get isCancelled => _cancelled;
  bool get isPaused => _paused;

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumeGate = Completer<void>();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    final gate = _resumeGate;
    _resumeGate = null;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    resume();
    for (final proc in _activeProcesses.toList()) {
      try {
        proc.kill();
      } catch (_) {}
    }
    _activeProcesses.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const ExportCancelled();
  }

  Future<void> checkpoint() async {
    if (_cancelled) throw const ExportCancelled();
    while (_paused && !_cancelled) {
      final gate = _resumeGate;
      if (gate == null) break;
      await gate.future;
    }
    if (_cancelled) throw const ExportCancelled();
  }

  void registerProcess(Process p) {
    if (_cancelled) {
      try {
        p.kill();
      } catch (_) {}
      throw const ExportCancelled();
    }
    _activeProcesses.add(p);
  }

  void unregisterProcess(Process p) {
    _activeProcesses.remove(p);
  }
}

class ExportOptions {
  final ExportConflictPolicy conflictPolicy;
  final bool useHardwareAccel;
  final ExportCancelToken? cancelToken;

  const ExportOptions({
    this.conflictPolicy = ExportConflictPolicy.skip,
    this.useHardwareAccel = true,
    this.cancelToken,
  });
}

Future<void> ensureOutputsAvailable(Iterable<String> paths) async {
  for (final path in paths) {
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw ExportSkipped(path);
    }
  }
}

/// Resolves target output paths according to conflict policy while keeping paired
/// files (such as `.HEIC` + `.MOV`) synchronized on the same suffix.
Future<List<String>> resolveExportTargets(
  List<String> desiredPaths,
  ExportConflictPolicy policy,
) async {
  switch (policy) {
    case ExportConflictPolicy.skip:
      await ensureOutputsAvailable(desiredPaths);
      return desiredPaths;
    case ExportConflictPolicy.overwrite:
      return desiredPaths;
    case ExportConflictPolicy.rename:
      var anyExists = false;
      for (final path in desiredPaths) {
        if (await FileSystemEntity.type(path) !=
            FileSystemEntityType.notFound) {
          anyExists = true;
          break;
        }
      }
      if (!anyExists) return desiredPaths;

      for (var index = 1; index < 10000; index++) {
        final candidates = [
          for (final path in desiredPaths)
            p.join(
              p.dirname(path),
              '${p.basenameWithoutExtension(path)}_$index${p.extension(path)}',
            ),
        ];
        var free = true;
        for (final c in candidates) {
          if (await FileSystemEntity.type(c) != FileSystemEntityType.notFound) {
            free = false;
            break;
          }
        }
        if (free) return candidates;
      }
      throw const FileSystemException('无法分配不冲突的输出文件名');
  }
}

/// Safely publishes a completed staged file to its final destination.
Future<void> publishStagedFile(
  String stagedPath,
  String finalPath,
  ExportConflictPolicy policy,
) async {
  if (policy == ExportConflictPolicy.overwrite) {
    final existingType = await FileSystemEntity.type(finalPath);
    if (existingType == FileSystemEntityType.file) {
      await File(finalPath).delete();
    } else if (existingType != FileSystemEntityType.notFound) {
      throw FileSystemException('目标路径被目录占用，无法覆盖', finalPath);
    }
  } else {
    await ensureOutputsAvailable([finalPath]);
  }
  try {
    await File(stagedPath).rename(finalPath);
  } on FileSystemException {
    await File(stagedPath).copy(finalPath);
    await File(stagedPath).delete();
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
/// Supports cancellation and immediate subprocess termination when [cancelToken] is active.
Future<ProcessResult> runMediaTool(
  String tool,
  List<String> arguments, {
  String? workingDirectory,
  ExportCancelToken? cancelToken,
}) async {
  if (cancelToken == null) {
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

  await cancelToken.checkpoint();
  final proc = await Process.start(
    ToolPath.find(tool),
    arguments,
    workingDirectory: workingDirectory,
  );
  cancelToken.registerProcess(proc);
  try {
    final stdoutFuture = proc.stdout.transform(utf8.decoder).join();
    final stderrFuture = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final code = await proc.exitCode;
    final outStr = await stdoutFuture;
    final errStr = await stderrFuture;
    cancelToken.throwIfCancelled();
    if (code != 0) {
      throw ProcessException(
        tool,
        arguments,
        errStr.length > 1800 ? errStr.substring(errStr.length - 1800) : errStr,
        code,
      );
    }
    return ProcessResult(proc.pid, code, outStr, errStr);
  } finally {
    cancelToken.unregisterProcess(proc);
  }
}

class HardwareHevcEncoder {
  final String codec;
  final String label;
  final List<String> qualityArgs;

  const HardwareHevcEncoder({
    required this.codec,
    required this.label,
    required this.qualityArgs,
  });
}

/// Detects working GPU HEVC encoders once per process and caches the result.
class HevcEncoderSelector {
  static Future<HardwareHevcEncoder?>? _probeFuture;
  static HardwareHevcEncoder? _cached;
  static bool _probed = false;

  static HardwareHevcEncoder? get cached => _cached;
  static bool get isProbed => _probed;

  static Future<HardwareHevcEncoder?> detect() {
    return _probeFuture ??= _runDetection();
  }

  static Future<HardwareHevcEncoder?> _runDetection() async {
    final candidates = <HardwareHevcEncoder>[
      if (Platform.isWindows) ...[
        const HardwareHevcEncoder(
          codec: 'hevc_nvenc',
          label: 'NVIDIA NVENC',
          qualityArgs: ['-preset', 'p4', '-cq', '19', '-b:v', '0'],
        ),
        const HardwareHevcEncoder(
          codec: 'hevc_qsv',
          label: 'Intel QSV',
          qualityArgs: ['-global_quality', '19'],
        ),
        const HardwareHevcEncoder(
          codec: 'hevc_amf',
          label: 'AMD AMF',
          qualityArgs: ['-rc', 'cqp', '-qp_i', '18', '-qp_p', '19'],
        ),
      ] else if (Platform.isMacOS) ...[
        const HardwareHevcEncoder(
          codec: 'hevc_videotoolbox',
          label: 'Apple VideoToolbox',
          qualityArgs: ['-q:v', '72'],
        ),
      ],
    ];

    for (final candidate in candidates) {
      try {
        final r = await Process.run(ToolPath.find('ffmpeg'), [
          '-nostdin',
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=black:s=128x128:d=0.1',
          '-frames:v',
          '1',
          '-pix_fmt',
          'yuv420p',
          '-c:v',
          candidate.codec,
          ...candidate.qualityArgs,
          '-tag:v',
          'hvc1',
          '-f',
          'null',
          '-',
        ]);
        if (r.exitCode == 0) {
          _cached = candidate;
          _probed = true;
          return candidate;
        }
      } catch (_) {}
    }
    _cached = null;
    _probed = true;
    return null;
  }
}

class VideoDetails {
  final double duration;
  final double coverTime;
  final int? width;
  final int? height;
  final Mp4DeviceInfo? device;

  const VideoDetails(
    this.duration,
    this.coverTime, {
    this.width,
    this.height,
    this.device,
  });

  /// Fast pure-Dart MP4/MOV header probe with automatic ffprobe fallback.
  static Future<VideoDetails> probe(
    String path, {
    ExportCancelToken? cancelToken,
  }) async {
    await cancelToken?.checkpoint();
    final fast = await MediaMetadata.tryProbeVideoFile(path);
    if (fast != null) {
      return VideoDetails(
        fast.duration,
        fast.coverTime,
        width: fast.width,
        height: fast.height,
        device: fast.device,
      );
    }

    final result = await runMediaTool('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height,duration:format=duration',
      '-of',
      'json',
      path,
    ], cancelToken: cancelToken);
    final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    final streams = data['streams'] as List? ?? [];
    if (streams.isEmpty) throw const FormatException('素材中没有可用的视频轨');
    final first = streams.first as Map;
    final duration =
        double.tryParse('${first['duration']}') ??
        double.tryParse('${data['format']?['duration']}');
    if (duration == null || !duration.isFinite || duration <= 0) {
      throw const FormatException('无法读取视频时长');
    }
    final width = first['width'] as int?;
    final height = first['height'] as int?;
    // Both the extracted still and its metadata must use the same timestamp.
    return VideoDetails(
      duration,
      duration >= 3 ? 1.5 : duration / 2,
      width: width,
      height: height,
    );
  }
}
