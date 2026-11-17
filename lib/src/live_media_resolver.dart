import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'export_support.dart';
import 'models.dart';
import 'tool_path.dart';

/// Resolved media bundle ready for direct playback in the built-in Live Photo & Video player.
/// Supports camera MP4s, `.livp` archives, Apple `.HEIC + .MOV` pairs, and Android Motion Photos.
class ResolvedPlayableMedia {
  /// Playable video file path (null for pure static photos).
  final String? videoPath;

  /// Decoded static cover image path (JPEG/PNG) for Live Photo static frame or photo viewer.
  final String? coverImagePath;

  /// True if this item should use interactive Live Photo semantics (LIVE badge, cover + motion).
  final bool isLivePhoto;

  /// Human-readable source format badge, e.g. "LIVP 实况包", "Apple HEIC+MOV", "Motion Photo", "相机实况原片".
  final String formatBadge;

  const ResolvedPlayableMedia({
    required this.videoPath,
    required this.coverImagePath,
    required this.isLivePhoto,
    required this.formatBadge,
  });

  bool get isPurePhoto => videoPath == null && coverImagePath != null;
}

class LiveMediaResolver {
  static String? _cacheRoot;

  static Future<String> _ensureCacheDir() async {
    if (_cacheRoot != null && await Directory(_cacheRoot!).exists()) {
      return _cacheRoot!;
    }
    final dir = Directory(
      p.join(Directory.systemTemp.path, 'pocket_motion_player_cache'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheRoot = dir.path;
    return dir.path;
  }

  static Future<String> _itemCacheSubdir(String path) async {
    final root = await _ensureCacheDir();
    final stat = await File(path).stat();
    final key = Object.hash(
      path,
      stat.size,
      stat.modified.microsecondsSinceEpoch,
    ).toUnsigned(32).toRadixString(16);
    final sub = Directory(p.join(root, key));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return sub.path;
  }

  /// Resolves a [MediaAsset] or standalone local file into playable cover + video paths.
  static Future<ResolvedPlayableMedia> resolve(MediaAsset asset) async {
    final file = File(asset.path);
    if (!await file.exists()) {
      throw const FileSystemException('文件不可用，请检查相机连接或重新扫描');
    }

    final ext = p.extension(asset.path).toLowerCase();
    if (ext == '.dng') {
      throw const FormatException('暂不支持 DNG 原始照片预览，请查看配套 JPEG 照片');
    }

    // 1. Baidu Netdisk / iOS .livp package (Stored or Deflated ZIP containing image + mov)
    if (ext == '.livp') {
      return _resolveLivp(asset.path);
    }

    // 2. Apple .HEIC (either standalone HEIC photo or paired with sibling .MOV)
    if (ext == '.heic' || ext == '.heif') {
      return _resolveHeicOrPair(asset.path);
    }

    // 3. QuickTime .MOV (either paired with sibling .HEIC/.JPG or standalone video)
    if (ext == '.mov') {
      return _resolveMovOrPair(asset.path);
    }

    // 4. JPEG / PNG — check for embedded Android/Google Motion Photo video stream!
    if (ext == '.jpg' || ext == '.jpeg') {
      final motion = await _tryResolveMotionPhotoJpeg(asset.path);
      if (motion != null) return motion;
      // Also check if a sibling .MOV exists (JPG + MOV Apple pair)
      final siblingMov = await _findSiblingWithExts(asset.path, const ['.mov']);
      if (siblingMov != null) {
        return ResolvedPlayableMedia(
          videoPath: siblingMov,
          coverImagePath: asset.path,
          isLivePhoto: true,
          formatBadge: 'Apple JPG+MOV 实况',
        );
      }
      return ResolvedPlayableMedia(
        videoPath: null,
        coverImagePath: asset.path,
        isLivePhoto: false,
        formatBadge: 'JPEG 照片',
      );
    }

    if (ext == '.png' || ext == '.webp') {
      return ResolvedPlayableMedia(
        videoPath: null,
        coverImagePath: asset.path,
        isLivePhoto: false,
        formatBadge: '静态图片',
      );
    }

    // 5. Camera source Live Photo MP4 vs Ordinary Video MP4
    if (asset.kind == MediaKind.livePhoto) {
      final cover = await _extractVideoCoverJpg(asset.path);
      return ResolvedPlayableMedia(
        videoPath: asset.path,
        coverImagePath: cover,
        isLivePhoto: true,
        formatBadge: '相机实况原片',
      );
    }

    return ResolvedPlayableMedia(
      videoPath: asset.path,
      coverImagePath: null,
      isLivePhoto: false,
      formatBadge: '${ext.replaceFirst('.', '').toUpperCase()} 视频',
    );
  }

  /// Builds a [MediaAsset] from any user-picked file path for direct playback.
  static Future<MediaAsset> assetFromFile(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    final name = p.basename(filePath);
    final ext = p.extension(name).toLowerCase();

    MediaKind kind;
    if (ext == '.livp') {
      kind = MediaKind.livePhoto;
    } else if (ext == '.heic' || ext == '.heif') {
      final mov = await _findSiblingWithExts(filePath, const ['.mov']);
      kind = mov != null ? MediaKind.livePhoto : MediaKind.photo;
    } else if (ext == '.mov') {
      final pic = await _findSiblingWithExts(
        filePath,
        const ['.heic', '.heif', '.jpg', '.jpeg'],
      );
      kind = pic != null ? MediaKind.livePhoto : MediaKind.video;
    } else if (ext == '.jpg' || ext == '.jpeg') {
      final isMotion = await isMotionPhotoFile(filePath);
      if (isMotion) {
        kind = MediaKind.livePhoto;
      } else {
        final siblingMov = await _findSiblingWithExts(
          filePath,
          const ['.mov'],
        );
        kind = siblingMov != null ? MediaKind.livePhoto : MediaKind.photo;
      }
    } else if (ext == '.png' || ext == '.webp' || ext == '.dng') {
      kind = MediaKind.photo;
    } else {
      // .mp4 / .m4v / .mkv: check if DJI Live Photo marker is present
      kind = await _isDjiLiveMp4(filePath)
          ? MediaKind.livePhoto
          : MediaKind.video;
    }

    return MediaAsset(
      path: filePath,
      filename: name,
      kind: kind,
      shotAt: stat.modified,
      sizeBytes: stat.size,
    );
  }

  /// Scans the export directory (`baidu_live`, `live`, `movie`, `photo`) and
  /// returns playable items deduplicated across Apple `.HEIC + .MOV` pairs.
  static Future<List<MediaAsset>> scanExportedDirectory(String outDir) async {
    final root = Directory(outDir);
    if (!await root.exists()) return <MediaAsset>[];

    final allFiles = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final dirName = p.basename(p.dirname(entity.path));
      if (dirName.startsWith('.pocket-')) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (const {
        '.livp',
        '.heic',
        '.heif',
        '.mov',
        '.mp4',
        '.jpg',
        '.jpeg',
      }.contains(ext)) {
        allFiles.add(entity);
      }
    }

    // Deduplicate .MOV files when a sibling .HEIC/.JPG exists in the same folder.
    final fileSetLower = {
      for (final f in allFiles) p.normalize(f.path).toLowerCase(),
    };
    final result = <MediaAsset>[];
    for (final f in allFiles) {
      final ext = p.extension(f.path).toLowerCase();
      if (ext == '.mov') {
        final stem = p.join(
          p.dirname(f.path),
          p.basenameWithoutExtension(f.path),
        );
        final hasSiblingStill = [
          '$stem.heic',
          '$stem.heif',
          '$stem.jpg',
          '$stem.jpeg',
        ].any((cand) => fileSetLower.contains(p.normalize(cand).toLowerCase()));
        if (hasSiblingStill) continue;
      }
      result.add(await assetFromFile(f.path));
    }

    result.sort((a, b) {
      final ta = a.shotAt ?? DateTime(0);
      final tb = b.shotAt ?? DateTime(0);
      final cmp = tb.compareTo(ta);
      return cmp != 0 ? cmp : a.filename.compareTo(b.filename);
    });
    return result;
  }

  static Future<bool> _isDjiLiveMp4(String path) async {
    try {
      final raf = await File(path).open();
      try {
        final head = await raf.read(512 * 1024);
        final text = latin1.decode(head, allowInvalid: true);
        return text.contains('TPLG_VIDEO_LIVEPHOTO');
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _findSiblingWithExts(
    String path,
    List<String> targetExtsLower,
  ) async {
    final dir = Directory(p.dirname(path));
    if (!await dir.exists()) return null;
    final stemLower = p.basenameWithoutExtension(path).toLowerCase();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.equals(entity.path, path)) continue;
      final name = p.basename(entity.path);
      if (p.basenameWithoutExtension(name).toLowerCase() == stemLower &&
          targetExtsLower.contains(p.extension(name).toLowerCase())) {
        return entity.path;
      }
    }
    return null;
  }

  static Future<ResolvedPlayableMedia> _resolveLivp(String livpPath) async {
    final subDir = await _itemCacheSubdir(livpPath);
    final cachedCoverJpg = p.join(subDir, 'cover.jpg');
    final existingMov = File(p.join(subDir, 'motion.mov'));
    final existingMp4 = File(p.join(subDir, 'motion.mp4'));
    if (await File(cachedCoverJpg).exists() &&
        (await existingMov.exists() || await existingMp4.exists())) {
      return ResolvedPlayableMedia(
        videoPath: await existingMov.exists()
            ? existingMov.path
            : existingMp4.path,
        coverImagePath: cachedCoverJpg,
        isLivePhoto: true,
        formatBadge: 'LIVP 实况包',
      );
    }

    final bytes = await File(livpPath).readAsBytes();
    final entries = _extractZipEntries(bytes);
    String? rawStillPath;
    String? videoOutPath;

    for (final entry in entries) {
      final ext = p.extension(entry.name).toLowerCase();
      if (ext == '.mov' || ext == '.mp4') {
        videoOutPath = p.join(subDir, 'motion$ext');
        await File(videoOutPath).writeAsBytes(entry.data, flush: true);
      } else if (ext == '.heic' ||
          ext == '.heif' ||
          ext == '.jpg' ||
          ext == '.jpeg' ||
          ext == '.png') {
        rawStillPath = p.join(subDir, 'raw_still$ext');
        await File(rawStillPath).writeAsBytes(entry.data, flush: true);
      }
    }

    if (videoOutPath == null && rawStillPath == null) {
      throw const FormatException('LIVP 包内未找到有效的实况图片或视频资源');
    }

    String? displayCover;
    if (rawStillPath != null) {
      final stillExt = p.extension(rawStillPath).toLowerCase();
      if (stillExt == '.jpg' || stillExt == '.jpeg' || stillExt == '.png') {
        displayCover = rawStillPath;
      } else {
        displayCover = await _decodeHeicToJpg(rawStillPath, cachedCoverJpg);
      }
    }
    if (displayCover == null && videoOutPath != null) {
      displayCover = await _extractVideoCoverJpg(videoOutPath);
    }

    return ResolvedPlayableMedia(
      videoPath: videoOutPath,
      coverImagePath: displayCover,
      isLivePhoto: videoOutPath != null,
      formatBadge: 'LIVP 实况包',
    );
  }

  static Future<ResolvedPlayableMedia> _resolveHeicOrPair(
    String heicPath,
  ) async {
    final subDir = await _itemCacheSubdir(heicPath);
    final jpgOut = p.join(subDir, 'heic_decoded.jpg');
    final decoded = await _decodeHeicToJpg(heicPath, jpgOut);
    final siblingMov = await _findSiblingWithExts(
      heicPath,
      const ['.mov', '.mp4'],
    );
    if (siblingMov != null) {
      final cover = decoded ?? await _extractVideoCoverJpg(siblingMov);
      return ResolvedPlayableMedia(
        videoPath: siblingMov,
        coverImagePath: cover,
        isLivePhoto: true,
        formatBadge: 'Apple HEIC+MOV 实况',
      );
    }
    if (decoded == null) {
      throw const FormatException('无法解码该 HEIC 图像，请检查文件完整性');
    }
    return ResolvedPlayableMedia(
      videoPath: null,
      coverImagePath: decoded,
      isLivePhoto: false,
      formatBadge: 'HEIC 图像',
    );
  }

  static Future<ResolvedPlayableMedia> _resolveMovOrPair(String movPath) async {
    final siblingPic = await _findSiblingWithExts(
      movPath,
      const ['.heic', '.heif', '.jpg', '.jpeg'],
    );
    if (siblingPic != null) {
      final ext = p.extension(siblingPic).toLowerCase();
      String? cover;
      if (ext == '.jpg' || ext == '.jpeg') {
        cover = siblingPic;
      } else {
        final subDir = await _itemCacheSubdir(siblingPic);
        cover = await _decodeHeicToJpg(
          siblingPic,
          p.join(subDir, 'heic_decoded.jpg'),
        );
      }
      cover ??= await _extractVideoCoverJpg(movPath);
      return ResolvedPlayableMedia(
        videoPath: movPath,
        coverImagePath: cover,
        isLivePhoto: true,
        formatBadge: 'Apple HEIC+MOV 实况',
      );
    }
    return ResolvedPlayableMedia(
      videoPath: movPath,
      coverImagePath: null,
      isLivePhoto: false,
      formatBadge: 'MOV 视频',
    );
  }

  /// Checks whether a JPEG contains an embedded Android/Google Motion Photo MP4.
  static Future<bool> isMotionPhotoFile(String jpgPath) async {
    try {
      final raf = await File(jpgPath).open();
      try {
        final len = await raf.length();
        if (len < 32) return false;
        final head = await raf.read(len < 65536 ? len : 65536);
        return _parseMotionPhotoVideoLength(head) != null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Inspired by `ente/motion_photos`: locates XMP MotionPhoto video byte length/offset
  /// and extracts both clean still JPEG and embedded MP4 video stream.
  static Future<ResolvedPlayableMedia?> _tryResolveMotionPhotoJpeg(
    String jpgPath,
  ) async {
    final raf = await File(jpgPath).open();
    try {
      final totalLen = await raf.length();
      if (totalLen < 32) return null;
      final headLen = totalLen < 128 * 1024 ? totalLen : 128 * 1024;
      final head = await raf.read(headLen);
      final videoLen = _parseMotionPhotoVideoLength(head);
      if (videoLen == null || videoLen <= 12 || videoLen >= totalLen - 4) {
        return null;
      }

      final videoOffset = totalLen - videoLen;
      await raf.setPosition(videoOffset);
      final sig = await raf.read(12);
      if (sig.length < 8 ||
          latin1.decode(sig.sublist(4, 8), allowInvalid: true) != 'ftyp') {
        return null;
      }

      final subDir = await _itemCacheSubdir(jpgPath);
      final outMp4 = p.join(subDir, 'embedded_motion.mp4');
      final outStill = p.join(subDir, 'primary_still.jpg');

      if (!await File(outMp4).exists() || !await File(outStill).exists()) {
        // Stream primary JPEG and embedded MP4 separately
        await _copyRange(raf, 0, videoOffset, outStill);
        await _copyRange(raf, videoOffset, videoLen, outMp4);
      }

      return ResolvedPlayableMedia(
        videoPath: outMp4,
        coverImagePath: outStill,
        isLivePhoto: true,
        formatBadge: 'Motion Photo 动态照片',
      );
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  static int? _parseMotionPhotoVideoLength(Uint8List headBytes) {
    final text = latin1.decode(headBytes, allowInvalid: true);
    if (!text.contains('MotionPhoto') && !text.contains('MicroVideo')) {
      return null;
    }

    // Google Motion Photo 1.0 Container:Item pattern
    final itemMatch = RegExp(
      r'Item:Mime="video/mp4"[^>]*Item:Length="(\d+)"|Item:Length="(\d+)"[^>]*Item:Mime="video/mp4"',
      dotAll: true,
    ).firstMatch(text);
    if (itemMatch != null) {
      return int.tryParse(itemMatch.group(1) ?? itemMatch.group(2) ?? '');
    }

    // Legacy GCamera:MicroVideoOffset pattern (Xiaomi / Pixel / Samsung)
    final microMatch = RegExp(
      r'GCamera:MicroVideoOffset="(\d+)"|MicroVideoOffset="(\d+)"',
    ).firstMatch(text);
    if (microMatch != null) {
      return int.tryParse(microMatch.group(1) ?? microMatch.group(2) ?? '');
    }
    return null;
  }

  static Future<void> _copyRange(
    RandomAccessFile raf,
    int start,
    int length,
    String outPath,
  ) async {
    await raf.setPosition(start);
    final out = await File(outPath).open(mode: FileMode.write);
    try {
      final buf = Uint8List(256 * 1024);
      var rem = length;
      while (rem > 0) {
        final chunk = rem < buf.length ? rem : buf.length;
        final got = await raf.readInto(buf, 0, chunk);
        if (got <= 0) break;
        await out.writeFrom(buf, 0, got);
        rem -= got;
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  static Future<String?> _decodeHeicToJpg(
    String heicPath,
    String jpgOut,
  ) async {
    final outFile = File(jpgOut);
    if (await outFile.exists() && await outFile.length() > 0) return jpgOut;
    try {
      final r = await Process.run(ToolPath.find('ffmpeg'), [
        '-nostdin',
        '-v',
        'error',
        '-y',
        '-i',
        heicPath,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        '-update',
        '1',
        jpgOut,
      ]);
      if (r.exitCode == 0 && await outFile.exists()) {
        return jpgOut;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _extractVideoCoverJpg(String videoPath) async {
    try {
      final subDir = await _itemCacheSubdir(videoPath);
      final outJpg = p.join(subDir, 'video_cover.jpg');
      if (await File(outJpg).exists()) return outJpg;
      var coverSec = 0.0;
      try {
        final details = await VideoDetails.probe(videoPath);
        coverSec = details.coverTime;
      } catch (_) {}
      final r = await Process.run(ToolPath.find('ffmpeg'), [
        '-nostdin',
        '-v',
        'error',
        '-y',
        '-ss',
        '$coverSec',
        '-i',
        videoPath,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        '-update',
        '1',
        outJpg,
      ]);
      if (r.exitCode == 0 && await File(outJpg).exists()) return outJpg;
    } catch (_) {}
    return null;
  }

  /// Pure-Dart ZIP reader supporting both Stored (method=0, used by LIVP) and
  /// Deflate (method=8, used by generic third-party LIVP tools).
  static List<({String name, Uint8List data})> _extractZipEntries(
    Uint8List zipBytes,
  ) {
    final data = ByteData.sublistView(zipBytes);
    // Locate End of Central Directory (0x06054b50), accounting for up to 64KB ZIP comment
    var eocd = -1;
    final minPos = zipBytes.length > 65558 ? zipBytes.length - 65558 : 0;
    for (var i = zipBytes.length - 22; i >= minPos; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const FormatException('无法识别 LIVP 归档结构（缺少 ZIP 目录索引）');
    }

    final entryCount = data.getUint16(eocd + 10, Endian.little);
    var cdPos = data.getUint32(eocd + 16, Endian.little);
    final extracted = <({String name, Uint8List data})>[];

    for (var idx = 0; idx < entryCount && cdPos + 46 <= zipBytes.length; idx++) {
      if (data.getUint32(cdPos, Endian.little) != 0x02014b50) break;
      final method = data.getUint16(cdPos + 10, Endian.little);
      final compSize = data.getUint32(cdPos + 20, Endian.little);
      final nameLen = data.getUint16(cdPos + 28, Endian.little);
      final extraLen = data.getUint16(cdPos + 30, Endian.little);
      final commentLen = data.getUint16(cdPos + 32, Endian.little);
      final localOffset = data.getUint32(cdPos + 42, Endian.little);

      final nameBytes = zipBytes.sublist(cdPos + 46, cdPos + 46 + nameLen);
      final name = utf8.decode(nameBytes, allowMalformed: true);
      cdPos += 46 + nameLen + extraLen + commentLen;

      if (name.endsWith('/') || localOffset + 30 > zipBytes.length) continue;
      if (data.getUint32(localOffset, Endian.little) != 0x04034b50) continue;

      final localNameLen = data.getUint16(localOffset + 26, Endian.little);
      final localExtraLen = data.getUint16(localOffset + 28, Endian.little);
      final payloadStart = localOffset + 30 + localNameLen + localExtraLen;
      if (payloadStart + compSize > zipBytes.length) continue;

      final compressedSlice = Uint8List.sublistView(
        zipBytes,
        payloadStart,
        payloadStart + compSize,
      );
      if (method == 0) {
        extracted.add((name: name, data: compressedSlice));
      } else if (method == 8) {
        final inflated = ZLibCodec(raw: true).decode(compressedSlice);
        extracted.add((name: name, data: Uint8List.fromList(inflated)));
      }
    }
    return extracted;
  }
}
