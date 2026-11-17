import 'dart:async';
import 'dart:collection';
import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'tool_path.dart';

/// 限制并发抽帧进程数量，避免大量素材（尤其 USB 存储卡）同时拉起几十个 ffmpeg。
class _ThumbPool {
  final int maxConcurrent;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  _ThumbPool(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active >= maxConcurrent) {
      final gate = Completer<void>();
      _waiters.addLast(gate);
      await gate.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}

/// 懒加载缩略图：首次构建时用 ffmpeg 从 MP4 抽一帧，缓存到临时目录与内存索引。
class ThumbnailImage extends StatefulWidget {
  final String videoPath;
  final double size;
  final double? height;
  final bool expand;
  final double borderRadius;
  final bool isLive;

  const ThumbnailImage({
    super.key,
    required this.videoPath,
    this.size = 56,
    this.height,
    this.expand = false,
    this.borderRadius = 6,
    this.isLive = false,
  });

  @override
  State<ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<ThumbnailImage> {
  static final Map<String, String> _resolvedCache = {};
  static final Map<String, Future<String?>> _inflight = {};
  static final _ThumbPool _pool = _ThumbPool(3);
  static String? _cachedTempDir;

  String? _cachePath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _syncOrLoad();
  }

  @override
  void didUpdateWidget(covariant ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _syncOrLoad();
    }
  }

  void _syncOrLoad() {
    final hit = _resolvedCache[widget.videoPath];
    if (hit != null) {
      _cachePath = hit;
      _loading = false;
      return;
    }
    _cachePath = null;
    _loading = true;
    _ensureThumb(widget.videoPath);
  }

  static Future<String> _cacheDir() async {
    if (_cachedTempDir != null) return _cachedTempDir!;
    final dir = Directory(p.join(Directory.systemTemp.path, 'dji_live_thumbs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _cachedTempDir = dir.path;
    return dir.path;
  }

  Future<void> _ensureThumb(String targetPath) async {
    try {
      final task = _inflight.putIfAbsent(
        targetPath,
        () => _extractThumb(targetPath),
      );
      final result = await task;
      _inflight.remove(targetPath);
      if (!mounted || widget.videoPath != targetPath) return;
      setState(() {
        _cachePath = result;
        _loading = false;
      });
    } catch (_) {
      _inflight.remove(targetPath);
      if (mounted && widget.videoPath == targetPath) {
        setState(() => _loading = false);
      }
    }
  }

  static Future<String?> _extractThumb(String videoPath) async {
    try {
      final dir = await _cacheDir();
      final stat = await File(videoPath).stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      final key = Object.hash(
        videoPath,
        stat.size,
        stat.modified,
      ).toUnsigned(32).toRadixString(16);
      final cache = p.join(dir, '$key.jpg');
      final f = File(cache);
      if (await f.exists()) {
        _resolvedCache[videoPath] = cache;
        return cache;
      }
      return await _pool.run(() async {
        if (await f.exists()) {
          _resolvedCache[videoPath] = cache;
          return cache;
        }
        // 仅解首个关键帧并缩放到 360 宽，4K 视频抽帧耗时显著降低。
        final r = await Process.run(ToolPath.find('ffmpeg'), [
          '-nostdin',
          '-v',
          'error',
          '-y',
          '-skip_frame',
          'nokey',
          '-ss',
          '0',
          '-i',
          videoPath,
          '-frames:v',
          '1',
          '-vf',
          'scale=360:-1',
          '-q:v',
          '4',
          '-update',
          '1',
          cache,
        ]);
        if (r.exitCode == 0 && await f.exists()) {
          _resolvedCache[videoPath] = cache;
          return cache;
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxChild = Container(
      width: widget.expand ? double.infinity : widget.size,
      height: widget.expand
          ? double.infinity
          : (widget.height ?? widget.size * 0.66),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F6),
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _cachePath != null
          ? Image.file(
              File(_cachePath!),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.movie_outlined,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            )
          : const Icon(
              Icons.movie_outlined,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
    );

    return Stack(
      fit: widget.expand ? StackFit.expand : StackFit.loose,
      children: [
        boxChild,
        if (widget.isLive)
          Positioned(
            left: 5,
            bottom: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xD90F766E),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.motion_photos_on, size: 9, color: Colors.white),
                  SizedBox(width: 2.5),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
