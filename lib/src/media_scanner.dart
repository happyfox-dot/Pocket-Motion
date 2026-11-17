import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

/// The upstream Pocket 4P implementation found TPLG markers in the dbgi data
/// track. This is a heuristic, not a published DJI specification. A missing
/// marker leaves the clip in the video tab; duration alone never means Live.
class MediaScanner {
  static const _scanHeadBytes = 512 * 1024;
  static final _tplgRegex = RegExp(r'TPLG_[A-Za-z0-9_]+');

  Future<List<MediaAsset>> scan(
    String dirPath, {
    void Function(String)? onWarning,
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
    final assets = <MediaAsset>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final ext = p.extension(name).toLowerCase();
      if (!['.mp4', '.jpg', '.jpeg', '.dng'].contains(ext)) continue;
      try {
        final stat = await e.stat();
        String? template;
        var kind = MediaKind.photo;
        if (ext == '.mp4') {
          final file = await e.open();
          try {
            final bytes = await file.read(_scanHeadBytes);
            final matches = _tplgRegex
                .allMatches(String.fromCharCodes(bytes))
                .map((m) => m.group(0)!)
                .toList();
            final live = matches.where(
              (s) =>
                  s == 'TPLG_VIDEO_LIVEPHOTO' ||
                  s.startsWith('TPLG_VIDEO_LIVEPHOTO_'),
            );
            template = live.isNotEmpty ? live.first : matches.firstOrNull;
            kind = live.isNotEmpty ? MediaKind.livePhoto : MediaKind.video;
          } finally {
            await file.close();
          }
        }
        assets.add(
          MediaAsset(
            path: e.path,
            filename: name,
            kind: kind,
            shotAt: _parseFileNameTime(name),
            sizeBytes: stat.size,
            template: template,
          ),
        );
      } on FileSystemException catch (e) {
        onWarning?.call('无法读取 $name：${e.message}');
      }
    }
    assets.sort((a, b) {
      final time = (b.shotAt ?? DateTime(0)).compareTo(a.shotAt ?? DateTime(0));
      return time != 0 ? time : a.path.compareTo(b.path);
    });
    return assets;
  }

  static DateTime? _parseFileNameTime(String name) {
    final m = RegExp(r'^DJI_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_')
        .firstMatch(name);
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
