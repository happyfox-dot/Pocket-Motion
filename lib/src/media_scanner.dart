import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'models.dart';

class _CachedScanEntry {
  final int size;
  final int modifiedMicros;
  final MediaKind kind;
  final String? template;

  const _CachedScanEntry({
    required this.size,
    required this.modifiedMicros,
    required this.kind,
    required this.template,
  });
}

/// The upstream Pocket 4P implementation found TPLG markers in the dbgi data
/// track. This is a heuristic, not a published DJI specification. A missing
/// marker leaves the clip in the video tab; duration alone never means Live.
class MediaScanner {
  static const _scanHeadBytes = 512 * 1024;
  static const _maxCacheEntries = 5000;
  static final LinkedHashMap<String, _CachedScanEntry> _statCache =
      LinkedHashMap<String, _CachedScanEntry>();

  Future<List<MediaAsset>> scan(
    String dirPath, {
    void Function(String)? onWarning,
    void Function(int scanned, int total)? onProgress,
    int concurrency = 6,
  }) async {
    if (dirPath.trim().isEmpty) {
      throw const FileSystemException('请先选择本地素材文件夹或查找 USB 相机');
    }
    var dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemException('素材目录不存在，请重新选择文件夹；若为相机存储，请检查连接', dirPath);
    }
    // Accept the disk root, DCIM itself, or an individual DJI folder.
    final dcim = Directory(p.join(dir.path, 'DCIM'));
    if (await dcim.exists()) dir = dcim;

    final candidateFiles = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final ext = p.extension(e.path).toLowerCase();
      if (ext == '.mp4' || ext == '.jpg' || ext == '.jpeg' || ext == '.dng') {
        candidateFiles.add(e);
      }
    }

    final total = candidateFiles.length;
    if (total == 0) {
      onProgress?.call(0, 0);
      return <MediaAsset>[];
    }

    final assets = <MediaAsset>[];
    var cursor = 0;
    var done = 0;
    final workerCount = concurrency.clamp(1, 12);

    Future<void> worker() async {
      while (true) {
        final idx = cursor++;
        if (idx >= total) break;
        final fileEntity = candidateFiles[idx];
        final name = p.basename(fileEntity.path);
        final ext = p.extension(name).toLowerCase();
        try {
          final stat = await fileEntity.stat();
          final modifiedMicros = stat.modified.microsecondsSinceEpoch;
          final cached = _statCache[fileEntity.path];

          MediaKind kind;
          String? template;

          if (cached != null &&
              cached.size == stat.size &&
              cached.modifiedMicros == modifiedMicros) {
            kind = cached.kind;
            template = cached.template;
          } else if (ext == '.mp4') {
            final raf = await fileEntity.open();
            try {
              final bytes = await raf.read(_scanHeadBytes);
              final parsed = _scanMp4HeaderMarkers(bytes);
              kind = parsed.$1;
              template = parsed.$2;
            } finally {
              await raf.close();
            }
            _putCache(
              fileEntity.path,
              _CachedScanEntry(
                size: stat.size,
                modifiedMicros: modifiedMicros,
                kind: kind,
                template: template,
              ),
            );
          } else {
            kind = MediaKind.photo;
            template = null;
          }

          assets.add(
            MediaAsset(
              path: fileEntity.path,
              filename: name,
              kind: kind,
              shotAt: _parseFileNameTime(name),
              sizeBytes: stat.size,
              template: template,
            ),
          );
        } on FileSystemException catch (e) {
          onWarning?.call('无法读取 $name：${e.message}');
        } finally {
          done++;
          if (done == total || done % 10 == 0) {
            onProgress?.call(done, total);
          }
        }
      }
    }

    await Future.wait(
      List.generate(workerCount > total ? total : workerCount, (_) => worker()),
    );

    assets.sort((a, b) {
      final time = (b.shotAt ?? DateTime(0)).compareTo(a.shotAt ?? DateTime(0));
      return time != 0 ? time : a.path.compareTo(b.path);
    });
    return assets;
  }

  /// Zero-UTF16-allocation byte scan for `TPLG_[A-Za-z0-9_]+` markers.
  static (MediaKind, String?) _scanMp4HeaderMarkers(Uint8List bytes) {
    final len = bytes.length;
    String? firstTemplate;
    var i = 0;
    while (i + 5 < len) {
      // Match ASCII 'T' (0x54), 'P' (0x50), 'L' (0x4C), 'G' (0x47), '_' (0x5F)
      if (bytes[i] == 0x54 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x4C &&
          bytes[i + 3] == 0x47 &&
          bytes[i + 4] == 0x5F) {
        var end = i + 5;
        while (end < len && _isTokenByte(bytes[end])) {
          end++;
        }
        if (end > i + 5) {
          final token = String.fromCharCodes(bytes, i, end);
          if (token == 'TPLG_VIDEO_LIVEPHOTO' ||
              token.startsWith('TPLG_VIDEO_LIVEPHOTO_')) {
            return (MediaKind.livePhoto, token);
          }
          firstTemplate ??= token;
          i = end;
          continue;
        }
      }
      i++;
    }
    return (MediaKind.video, firstTemplate);
  }

  static bool _isTokenByte(int b) =>
      (b >= 0x30 && b <= 0x39) || // 0-9
      (b >= 0x41 && b <= 0x5A) || // A-Z
      (b >= 0x61 && b <= 0x7A) || // a-z
      b == 0x5F; // _

  static void _putCache(String path, _CachedScanEntry entry) {
    _statCache.remove(path);
    _statCache[path] = entry;
    while (_statCache.length > _maxCacheEntries) {
      _statCache.remove(_statCache.keys.first);
    }
  }

  static DateTime? _parseFileNameTime(String name) {
    final m = RegExp(
      r'^DJI_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_',
    ).firstMatch(name);
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
    final dt = DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
    if (dt.year != v[0] ||
        dt.month != v[1] ||
        dt.day != v[2] ||
        dt.hour != v[3] ||
        dt.minute != v[4] ||
        dt.second != v[5]) {
      return null;
    }
    return dt;
  }
}
